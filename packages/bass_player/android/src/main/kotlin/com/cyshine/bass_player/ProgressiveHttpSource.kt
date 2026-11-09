package com.cyshine.bass_player

import com.un4seen.bass.BASS
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.net.ConnectException
import java.net.HttpURLConnection
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException
import java.net.URL
import java.net.UnknownHostException
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.util.TreeMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import javax.net.ssl.SSLException
import kotlin.concurrent.withLock
import kotlin.math.max
import kotlin.math.min

/** Downloaded byte spans keyed by start, end exclusive; touching spans merge. Not thread-safe. */
internal class ByteRanges {
    private val spans = TreeMap<Long, Long>()

    fun add(start: Long, end: Long) {
        if (end <= start) return
        var from = start
        var to = end
        spans.floorEntry(start)?.let { if (it.value >= start) from = it.key }
        while (true) {
            val next = spans.ceilingEntry(from) ?: break
            if (next.key > to) break
            to = max(to, next.value)
            spans.remove(next.key)
        }
        spans[from] = to
    }

    /** End of the downloaded run containing [position], or [position] when it is missing. */
    fun runEnd(position: Long): Long {
        val span = spans.floorEntry(position) ?: return position
        return if (span.value > position) span.value else position
    }

    /** How far back the gap at [position] reaches, ie. the end of the preceding run. */
    fun gapStart(position: Long): Long {
        val span = spans.floorEntry(position) ?: return 0
        return min(span.value, position)
    }

    /** Start of the first downloaded run after [position], or null. */
    fun nextRun(position: Long): Long? = spans.higherKey(position)

    fun totalBytes(): Long = spans.entries.sumOf { it.value - it.key }

    override fun toString(): String =
        spans.entries.joinToString(",", "[", "]") { "${it.key}-${it.value}" }
}

internal class ContentRange(val start: Long, val endInclusive: Long, val total: Long?)

private val CONTENT_RANGE = Regex("""^\s*bytes\s+(\d+)-(\d+)/(\d+|\*)\s*$""", RegexOption.IGNORE_CASE)

internal fun parseContentRange(value: String?): ContentRange? {
    val match = CONTENT_RANGE.find(value ?: return null) ?: return null
    val (first, last, total) = match.destructured
    val start = first.toLongOrNull() ?: return null
    val end = last.toLongOrNull() ?: return null
    if (end < start) return null
    return ContentRange(start, end, total.toLongOrNull())
}

internal class SourceException(
    val kind: Kind,
    message: String,
    val status: Int = 0,
    cause: Throwable? = null,
) : IOException(message, cause) {
    enum class Kind { OFFLINE, TIMEOUT, HTTP, UNSUPPORTED, CANCELLED }

    /** The server refused a URL that worked before; music sources hand out expiring links. */
    val expiredUrl: Boolean get() = kind == Kind.HTTP && status in setOf(401, 403, 404, 410)
}

/** A response worth retrying, such as 503 from an overloaded CDN. */
private class TransientHttpException(val status: Int) : IOException("HTTP $status")

/** The response body ended before its declared length. */
private class TruncatedBodyException(position: Long, end: Long) :
    IOException("connection closed at $position of $end")

/**
 * Random-access HTTP file for a BASS unbuffered user stream.
 *
 * BASS internet streams download strictly forward and treat a dropped download
 * as the end of the file, so a network loss completed tracks early and seeking
 * past the downloaded part failed. This source caches bytes in a sparse file,
 * resumes and redirects the download with range requests and only reports EOF
 * at the real end:
 *  - reads on BASS's threads return 0 while data is missing, which stalls the
 *    channel until [setResumeBytes] worth of data is buffered again;
 *  - reads on the thread inside [beginBlocking] wait for the data instead, as
 *    stream creation and seeking need it.
 */
internal class ProgressiveHttpSource(
    private val originalUrl: String,
    headers: Map<String, String>,
    private val cacheFile: File,
    private val onStateChanged: (ProgressiveHttpSource) -> Unit,
    private val openConnection: (URL) -> HttpURLConnection = { it.openConnection() as HttpURLConnection },
) : BASS.BASS_FILEPROCS {
    private val requestHeaders = LinkedHashMap(headers)
    private val lock = ReentrantLock()
    private val changed = lock.newCondition()
    private val ranges = ByteRanges()
    private val file = RandomAccessFile(cacheFile, "rw")
    private val channel: FileChannel = file.channel
    private val connections = HashSet<HttpURLConnection>()

    // Everything below is guarded by lock.
    private var effectiveUrl = originalUrl
    private var length = -1L
    private var rangeSupported = false
    private var readPosition = 0L
    private var priority: Long? = null
    private var holdBytes = 0L
    private var resumeBytes = DEFAULT_RESUME_BYTES
    private var closed = false
    private var cancelled = false
    private var complete = false
    private var fatal: SourceException? = null
    private var transientError: IOException? = null
    private var retrySignal = false
    private var received = false
    private var blockingThread: Thread? = null
    private var blockingDeadline = 0L
    private var starved = false
    private var mainConnection: HttpURLConnection? = null
    private var mainPosition = -1L
    private var redirectMain = false
    private var tailStart = -1L
    private var tailPending = false
    private var worker: Thread? = null

    val totalBytes: Long get() = lock.withLock { length }
    val downloadedBytes: Long get() = lock.withLock { ranges.totalBytes() }
    val isComplete: Boolean get() = lock.withLock { complete }
    val failure: SourceException? get() = lock.withLock { fatal }
    val priorityPosition: Long? get() = lock.withLock { priority }

    /** Latest retryable failure while the download has not recovered; null while data flows. */
    val networkError: String? get() = lock.withLock { transientError?.let(::describe) }

    /** Starts downloading and waits for the response that reveals the file length. */
    fun open(timeoutMs: Long) {
        lock.withLock {
            if (worker == null) {
                worker = Thread(::downloadLoop, "CyShine-HTTP").apply {
                    isDaemon = true
                    start()
                }
            }
            var remaining = TimeUnit.MILLISECONDS.toNanos(timeoutMs)
            // Unreachable hosts fail at once so the caller can try another source;
            // timeouts and resets keep retrying until the deadline.
            while (length < 0 && fatal == null && !closed && !cancelled && remaining > 0 &&
                !failsOpen(transientError)
            ) {
                remaining = changed.awaitNanos(remaining)
            }
            if (length >= 0) return
            fatal?.let { throw it }
            if (closed || cancelled) {
                throw SourceException(SourceException.Kind.CANCELLED, "load cancelled")
            }
            val last = transientError
            throw SourceException(
                classify(last),
                last?.let(::describe) ?: "no response within ${timeoutMs}ms",
                cause = last,
            )
        }
    }

    /** Lets reads on the calling thread wait up to [budgetMs] for missing data. */
    fun beginBlocking(budgetMs: Long) = lock.withLock {
        blockingThread = Thread.currentThread()
        blockingDeadline = now() + budgetMs
        starved = false
    }

    /** Ends [beginBlocking]; true when a read gave up because its data had not arrived. */
    fun endBlocking(): Boolean = lock.withLock {
        blockingThread = null
        val result = starved
        starved = false
        result
    }

    /** Makes a waiting read give up now, so a newer command does not queue behind it. */
    fun interruptBlocking() = lock.withLock {
        blockingDeadline = 0
        changed.signalAll()
    }

    /** Aborts [open] and blocking reads for a load that has been superseded. */
    fun cancel() = lock.withLock {
        cancelled = true
        blockingDeadline = 0
        changed.signalAll()
    }

    /** Moves the start of the decoder's next read back to the beginning of the file. */
    fun rewind() = lock.withLock { readPosition = 0 }

    /** Downloads around [position] first, eg. the file offset of a pending seek. */
    fun prioritize(position: Long?) {
        var stale: HttpURLConnection? = null
        lock.withLock {
            priority = position?.let { if (length > 0) it.coerceIn(0, length - 1) else max(it, 0) }
            // Someone is waiting for this data, so skip any retry delay.
            if (position != null) retrySignal = true
            stale = staleMainConnection()
            changed.signalAll()
        }
        stale?.let(::disconnectQuietly)
    }

    fun isBuffered(position: Long, bytes: Long): Boolean = lock.withLock {
        if (length < 0) return false
        val from = position.coerceIn(0, length)
        val end = ranges.runEnd(from)
        end - from >= bytes || end >= length
    }

    fun runEnd(position: Long): Long = lock.withLock { ranges.runEnd(position) }

    /** Data BASS needs buffered again before stalled playback resumes. */
    fun setResumeBytes(bytes: Long) = lock.withLock { resumeBytes = bytes }

    /** Holds BASS reads until [bytes] are buffered, eg. before playback starts. */
    fun holdUntilBuffered(bytes: Long) = lock.withLock { holdBytes = bytes }

    /** Skips a pending retry delay; [reconnect] also drops a connection on a replaced network. */
    fun retryNow(reconnect: Boolean) {
        var stale: HttpURLConnection? = null
        lock.withLock {
            retrySignal = true
            if (reconnect && mainConnection != null && !redirectMain) {
                redirectMain = true
                stale = mainConnection
            }
            changed.signalAll()
        }
        stale?.let(::disconnectQuietly)
    }

    fun close() {
        val active: List<HttpURLConnection>
        lock.withLock {
            if (closed) return
            closed = true
            active = connections.toList()
            changed.signalAll()
        }
        active.forEach(::disconnectQuietly)
        try {
            channel.close()
            file.close()
        } catch (_: IOException) {
        }
        cacheFile.delete()
    }

    // BASS frees the stream before the plugin closes this source.
    override fun FILECLOSEPROC(user: Any?) = Unit

    override fun FILELENPROC(user: Any?): Long = lock.withLock { max(length, 0) }

    override fun FILESEEKPROC(offset: Long, user: Any?): Boolean {
        var stale: HttpURLConnection? = null
        try {
            lock.withLock {
                if (closed || offset < 0 || (length >= 0 && offset > length)) return false
                readPosition = offset
                stale = staleMainConnection()
                changed.signalAll()
            }
        } finally {
            stale?.let(::disconnectQuietly)
        }
        return true
    }

    override fun FILEREADPROC(buffer: ByteBuffer, length: Int, user: Any?): Int {
        var stale: HttpURLConnection? = null
        val blocking: Boolean
        try {
            lock.withLock {
                if (closed) return -1
                if (this.length < 0) return 0
                if (readPosition >= this.length) return -1
                blocking = Thread.currentThread() === blockingThread
                if (ranges.runEnd(readPosition) <= readPosition) {
                    // A seek attempt is reading: its position beats the earlier estimate.
                    if (blocking && priority != null) priority = readPosition
                    stale = staleMainConnection()
                    changed.signalAll()
                }
            }
        } finally {
            stale?.let(::disconnectQuietly)
        }

        val position: Long
        val count: Int
        lock.withLock {
            if (closed) return -1
            var available = ranges.runEnd(readPosition) - readPosition
            if (blocking) {
                while (available <= 0 && !closed && !cancelled && fatal == null) {
                    val remaining = blockingDeadline - now()
                    if (remaining <= 0) break
                    // Only the sequential download can deliver this, possibly much later.
                    // Decoders tolerate a missing tail and seeks retry when it arrives.
                    if (!rangeSupported && readPosition > mainPosition + REDIRECT_WINDOW_BYTES) break
                    changed.await(min(remaining, 250), TimeUnit.MILLISECONDS)
                    available = ranges.runEnd(readPosition) - readPosition
                }
                if (available <= 0) {
                    starved = true
                    return 0
                }
            } else {
                if (holdBytes > 0) {
                    val end = ranges.runEnd(readPosition)
                    // A failing download cannot fill the hold; play what has arrived.
                    val downloading = transientError == null && fatal == null
                    if (downloading && end - readPosition < holdBytes && end < this.length) return 0
                    if (available > 0) holdBytes = 0
                }
                if (available <= 0) {
                    // Returning 0 stalls the channel; refill a few seconds before resuming.
                    holdBytes = resumeBytes
                    return 0
                }
            }
            position = readPosition
            count = min(length.toLong(), available).toInt()
        }

        val read = try {
            readCache(buffer, position, count)
        } catch (_: IOException) {
            return if (lock.withLock { closed }) -1 else 0
        }
        lock.withLock { if (readPosition == position) readPosition = position + read }
        return read
    }

    private fun downloadLoop() {
        var failures = 0
        var emptyBodies = 0
        while (true) {
            val plan = lock.withLock { nextTransfer() }
            if (plan == null) {
                if (lock.withLock { complete }) onStateChanged(this)
                return
            }
            try {
                transfer(plan.first, plan.second, main = true)
                failures = 0
            } catch (error: SourceException) {
                if (error.kind != SourceException.Kind.CANCELLED) {
                    lock.withLock {
                        if (fatal == null) fatal = error
                        changed.signalAll()
                    }
                    onStateChanged(this)
                }
                return
            } catch (error: IOException) {
                val redirected = lock.withLock {
                    if (closed) return
                    redirectMain.also { redirectMain = false }
                }
                if (redirected) continue
                // Only connections that deliver nothing back off further.
                val progressed = lock.withLock { received.also { received = false } }
                failures = if (progressed) 1 else failures + 1
                // A server that keeps answering without the data will not recover by retrying.
                emptyBodies = if (error is TruncatedBodyException && !progressed) emptyBodies + 1 else 0
                if (emptyBodies >= MAX_EMPTY_BODIES) {
                    lock.withLock {
                        if (fatal == null) {
                            fatal = SourceException(SourceException.Kind.HTTP, error.message ?: "truncated response")
                        }
                        changed.signalAll()
                    }
                    onStateChanged(this)
                    return
                }
                setTransientError(error)
                waitForRetry(min(MAX_RETRY_DELAY_MS, FIRST_RETRY_DELAY_MS shl min(failures - 1, 5)))
            } catch (error: RuntimeException) {
                lock.withLock {
                    if (fatal == null) {
                        fatal = SourceException(SourceException.Kind.UNSUPPORTED, error.toString(), cause = error)
                    }
                    changed.signalAll()
                }
                onStateChanged(this)
                return
            }
        }
    }

    /** Next range to request as start to inclusive end, or null when there is nothing to do. */
    private fun nextTransfer(): Pair<Long, Long?>? {
        while (true) {
            if (closed || fatal != null) return null
            if (length < 0) return 0L to null
            val needed = neededPosition()
            if (needed != null) {
                // A seek decoder often steps back a little from the requested offset.
                val start = if (priority != null) {
                    max(ranges.gapStart(needed), needed - SEEK_LOOKBACK_BYTES)
                } else {
                    needed
                }
                return start to rangeEnd(start)
            }
            val gap = ranges.runEnd(0)
            if (gap < length && !(tailPending && gap >= tailStart)) return gap to rangeEnd(gap)
            if (!tailPending) {
                complete = true
                // Nothing is left to fetch, so an earlier failure no longer matters.
                transientError = null
                changed.signalAll()
                return null
            }
            changed.await()
        }
    }

    /** First missing byte the decoder needs next, excluding the tail being fetched. */
    private fun neededPosition(): Long? {
        val anchor = (priority ?: readPosition).coerceIn(0, length)
        val needed = ranges.runEnd(anchor)
        if (needed >= length) return null
        if (tailPending && needed >= tailStart) return null
        return needed
    }

    private fun rangeEnd(start: Long): Long? {
        var end = ranges.nextRun(start)
        if (tailPending && start < tailStart) end = min(end ?: tailStart, tailStart)
        return end?.let { it - 1 }
    }

    /** The main connection when the needed data is not about to arrive on it. */
    private fun staleMainConnection(): HttpURLConnection? {
        val connection = mainConnection ?: return null
        if (redirectMain || !rangeSupported || length < 0) return null
        val needed = neededPosition() ?: return null
        if (needed >= mainPosition && needed <= mainPosition + REDIRECT_WINDOW_BYTES) return null
        redirectMain = true
        return connection
    }

    private fun shouldLeaveMain(position: Long): Boolean {
        if (closed) throw SourceException(SourceException.Kind.CANCELLED, "closed")
        if (redirectMain) return true
        if (!rangeSupported) return false
        // Data ahead is already cached; request what is missing rather than download it again.
        if (ranges.runEnd(position) - position > REDIRECT_WINDOW_BYTES) return true
        val needed = neededPosition() ?: return false
        return needed < position || needed > position + REDIRECT_WINDOW_BYTES
    }

    private fun fetchTail() {
        try {
            val (start, end) = lock.withLock { tailStart to length - 1 }
            transfer(start, end, main = false)
        } catch (_: Exception) {
            // The main download fetches the tail on demand instead.
        } finally {
            lock.withLock {
                tailPending = false
                changed.signalAll()
            }
        }
    }

    private fun transfer(start: Long, endInclusive: Long?, main: Boolean) {
        val connection = openRange(start, endInclusive)
        // Registered before the length is published, so nothing that reacts to it can miss this.
        if (main) {
            lock.withLock {
                mainConnection = connection
                mainPosition = start
                redirectMain = false
            }
        }
        try {
            val status = connection.responseCode
            // Portals and error pages answer 200 with HTML; it must not become the file.
            if (status in 200..299 && connection.contentType?.startsWith("text/html", ignoreCase = true) == true) {
                throw IOException("unexpected ${connection.contentType} response")
            }
            val bodyStart: Long
            val bodyEnd: Long
            when {
                status == HttpURLConnection.HTTP_PARTIAL -> {
                    val range = parseContentRange(connection.getHeaderField("Content-Range"))
                        ?: throw IOException("206 response without Content-Range")
                    if (range.start != start) throw IOException("range starts at ${range.start}, wanted $start")
                    val total = range.total
                        ?: throw SourceException(SourceException.Kind.UNSUPPORTED, "unknown file length")
                    acceptLength(total, rangesWork = true)
                    bodyStart = start
                    bodyEnd = range.endInclusive + 1
                }
                status == HttpURLConnection.HTTP_OK -> {
                    if (!main) throw IOException("range ignored")
                    val total = connection.contentLengthLong
                    if (total <= 0) {
                        throw SourceException(SourceException.Kind.UNSUPPORTED, "unknown content length")
                    }
                    val acceptRanges = connection.getHeaderField("Accept-Ranges")
                        ?.contains("bytes", ignoreCase = true) == true
                    acceptLength(total, rangesWork = start == 0L && acceptRanges)
                    if (start > 0) lock.withLock { rangeSupported = false }
                    bodyStart = 0
                    bodyEnd = total
                }
                status == HTTP_TIMEOUT || status == HTTP_TOO_MANY_REQUESTS -> throw TransientHttpException(status)
                status in 400..499 -> {
                    val retryOriginal = lock.withLock {
                        (effectiveUrl != originalUrl).also { if (it) effectiveUrl = originalUrl }
                    }
                    // A redirect target can expire before the link that produced it.
                    if (retryOriginal) throw IOException("HTTP $status from redirected URL")
                    throw SourceException(SourceException.Kind.HTTP, "HTTP $status", status)
                }
                else -> throw TransientHttpException(status)
            }
            copyBody(connection, bodyStart, bodyEnd, main)
        } finally {
            if (main) {
                lock.withLock {
                    if (mainConnection === connection) {
                        mainConnection = null
                        mainPosition = -1
                    }
                }
            }
            release(connection)
        }
    }

    private fun openRange(start: Long, endInclusive: Long?): HttpURLConnection {
        var url = lock.withLock { effectiveUrl }
        repeat(MAX_REDIRECTS + 1) {
            val connection = openConnection(URL(url))
            connection.instanceFollowRedirects = false
            connection.connectTimeout = CONNECT_TIMEOUT_MS
            connection.readTimeout = READ_TIMEOUT_MS
            connection.useCaches = false
            requestHeaders.forEach { (name, value) -> connection.setRequestProperty(name, value) }
            if (requestHeaders.keys.none { it.equals("User-Agent", ignoreCase = true) }) {
                connection.setRequestProperty("User-Agent", USER_AGENT)
            }
            // Transparent gzip would hide Content-Length and break byte ranges.
            connection.setRequestProperty("Accept-Encoding", "identity")
            connection.setRequestProperty("Range", "bytes=$start-${endInclusive ?: ""}")
            lock.withLock {
                if (closed) throw SourceException(SourceException.Kind.CANCELLED, "closed")
                connections += connection
            }
            val status = try {
                connection.responseCode
            } catch (error: IOException) {
                release(connection)
                throw error
            }
            if (status !in 300..399 || status == HttpURLConnection.HTTP_NOT_MODIFIED) {
                lock.withLock { effectiveUrl = url }
                return connection
            }
            val location = connection.getHeaderField("Location")
            release(connection)
            if (location.isNullOrBlank()) {
                throw SourceException(SourceException.Kind.HTTP, "HTTP $status without Location", status)
            }
            url = URL(URL(url), location).toString()
        }
        throw SourceException(SourceException.Kind.HTTP, "too many redirects")
    }

    private fun acceptLength(total: Long, rangesWork: Boolean) {
        var fetchTail = false
        lock.withLock {
            when {
                length < 0 -> {
                    length = total
                    rangeSupported = rangesWork
                    file.setLength(total)
                    if (rangesWork && total >= TAIL_MIN_FILE_BYTES) {
                        tailStart = total - TAIL_BYTES
                        tailPending = true
                        fetchTail = true
                    }
                    changed.signalAll()
                }
                length != total -> throw SourceException(
                    SourceException.Kind.HTTP,
                    "file length changed from $length to $total",
                )
                rangesWork -> rangeSupported = true
            }
        }
        // Decoders read tags at the end while opening; fetch them beside the main download.
        if (fetchTail) {
            Thread(::fetchTail, "CyShine-HTTP-tail").apply {
                isDaemon = true
                start()
            }
        }
    }

    private fun copyBody(connection: HttpURLConnection, bodyStart: Long, bodyEnd: Long, main: Boolean) {
        val input = connection.inputStream
        val buffer = ByteArray(CHUNK_BYTES)
        var position = bodyStart
        var flowing = false
        if (main) lock.withLock { mainPosition = position }
        while (position < bodyEnd) {
            if (main && lock.withLock { shouldLeaveMain(position) }) return
            val count = input.read(buffer, 0, min(buffer.size.toLong(), bodyEnd - position).toInt())
            if (count < 0) throw TruncatedBodyException(position, bodyEnd)
            if (count == 0) continue
            writeCache(position, buffer, count)
            position += count
            lock.withLock {
                received = true
                if (main) mainPosition = position
            }
            if (!flowing) {
                flowing = true
                setTransientError(null)
            }
        }
    }

    private fun writeCache(position: Long, data: ByteArray, count: Int) {
        val buffer = ByteBuffer.wrap(data, 0, count)
        var offset = position
        try {
            while (buffer.hasRemaining()) offset += channel.write(buffer, offset)
        } catch (error: IOException) {
            if (lock.withLock { closed }) throw SourceException(SourceException.Kind.CANCELLED, "closed")
            // A full disk does not clear up by downloading again.
            throw SourceException(SourceException.Kind.UNSUPPORTED, "cache write failed: ${error.message}", cause = error)
        }
        lock.withLock {
            ranges.add(position, position + count)
            changed.signalAll()
        }
    }

    private fun readCache(target: ByteBuffer, position: Long, count: Int): Int {
        val view = target.duplicate()
        view.limit(view.position() + count)
        var total = 0
        while (total < count) {
            val read = channel.read(view, position + total)
            if (read <= 0) break
            total += read
        }
        return total
    }

    private fun setTransientError(error: IOException?) {
        val flipped = lock.withLock {
            val before = transientError != null
            transientError = error
            changed.signalAll()
            before != (error != null)
        }
        if (flipped) onStateChanged(this)
    }

    private fun waitForRetry(delayMs: Long) = lock.withLock {
        var remaining = TimeUnit.MILLISECONDS.toNanos(delayMs)
        while (!closed && !retrySignal && remaining > 0) remaining = changed.awaitNanos(remaining)
        retrySignal = false
    }

    private fun release(connection: HttpURLConnection) {
        lock.withLock { connections -= connection }
        disconnectQuietly(connection)
    }

    private fun disconnectQuietly(connection: HttpURLConnection) {
        try {
            connection.disconnect()
        } catch (_: Exception) {
        }
    }

    private fun now() = System.nanoTime() / 1_000_000

    companion object {
        const val USER_AGENT = "BASS/2.4"
        const val CONNECT_TIMEOUT_MS = 8_000
        const val READ_TIMEOUT_MS = 15_000
        const val MAX_REDIRECTS = 5
        const val CHUNK_BYTES = 64 * 1024
        const val REDIRECT_WINDOW_BYTES = 128L * 1024
        const val SEEK_LOOKBACK_BYTES = 64L * 1024
        const val TAIL_BYTES = 64L * 1024
        const val TAIL_MIN_FILE_BYTES = 1024L * 1024
        const val DEFAULT_RESUME_BYTES = 256L * 1024
        const val FIRST_RETRY_DELAY_MS = 500L
        const val MAX_RETRY_DELAY_MS = 5_000L
        const val MAX_EMPTY_BODIES = 4
        private const val HTTP_TIMEOUT = 408
        private const val HTTP_TOO_MANY_REQUESTS = 429

        private val URL_QUERY = Regex("""\?\S*""")

        // This reaches exported logs, and playback links carry signed tokens.
        private fun describe(error: IOException): String = when (error) {
            is UnknownHostException -> "dns: ${error.message}"
            is SocketTimeoutException -> "timeout"
            is TransientHttpException -> "http ${error.status}"
            else -> "${error.javaClass.simpleName}: ${error.message}"
        }.replace(URL_QUERY, "?...")

        private fun failsOpen(error: IOException?): Boolean =
            error is UnknownHostException || error is ConnectException ||
                error is NoRouteToHostException || error is TransientHttpException ||
                error is SSLException

        private fun classify(error: IOException?): SourceException.Kind = when (error) {
            null, is SocketTimeoutException -> SourceException.Kind.TIMEOUT
            is TransientHttpException -> SourceException.Kind.HTTP
            // BASS does not verify certificates, so its own stream may still connect.
            is SSLException -> SourceException.Kind.UNSUPPORTED
            else -> SourceException.Kind.OFFLINE
        }
    }
}
