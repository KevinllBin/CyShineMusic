package com.cyshine.bass_player

import java.io.BufferedInputStream
import java.io.File
import java.io.IOException
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URL
import java.nio.ByteBuffer
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ProgressiveHttpSourceTest {
    @get:Rule
    val folder = TemporaryFolder()

    private lateinit var server: RangeServer
    private val sources = ArrayList<ProgressiveHttpSource>()
    private val content = ByteArray(4 * 1024 * 1024) { (it * 31 + it / 251).toByte() }

    @Before
    fun startServer() {
        server = RangeServer(content)
    }

    @After
    fun stopServer() {
        sources.forEach { it.close() }
        server.close()
    }

    private fun source(path: String = "/audio.flac", url: String = server.url(path)): ProgressiveHttpSource =
        ProgressiveHttpSource(url, emptyMap(), File(folder.root, "s${sources.size}.part"), {}, ::fastRetryConnection)
            .also(sources::add)

    private fun fastRetryConnection(url: URL): HttpURLConnection = url.openConnection() as HttpURLConnection

    private fun waitFor(timeoutMs: Long = 10_000, message: String = "condition", predicate: () -> Boolean) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (!predicate()) {
            if (System.currentTimeMillis() > deadline) throw AssertionError("timed out waiting for $message")
            Thread.sleep(5)
        }
    }

    /** Reads like BASS's update thread: whatever exists now, spinning while nothing arrives. */
    private fun readAll(source: ProgressiveHttpSource, timeoutMs: Long = 30_000): ByteArray {
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteBuffer.allocateDirect(32 * 1024)
        val deadline = System.currentTimeMillis() + timeoutMs
        while (true) {
            buffer.clear()
            val count = source.FILEREADPROC(buffer, buffer.capacity(), null)
            if (count < 0) return output.toByteArray()
            if (count == 0) {
                if (System.currentTimeMillis() > deadline) throw AssertionError("stalled at ${output.size()}")
                Thread.sleep(2)
                continue
            }
            val bytes = ByteArray(count)
            buffer.position(0)
            buffer.get(bytes)
            output.write(bytes)
        }
    }

    private fun readOnce(source: ProgressiveHttpSource, length: Int = 4096): Pair<Int, ByteArray> {
        val buffer = ByteBuffer.allocateDirect(length)
        val count = source.FILEREADPROC(buffer, length, null)
        val bytes = ByteArray(maxOf(count, 0))
        buffer.position(0)
        buffer.get(bytes)
        return count to bytes
    }

    @Test
    fun rangesMergeAndReportRuns() {
        val ranges = ByteRanges()
        ranges.add(10, 20)
        ranges.add(30, 40)
        assertEquals(20, ranges.runEnd(10))
        assertEquals(20, ranges.runEnd(19))
        assertEquals(20, ranges.runEnd(20))
        assertEquals(25, ranges.runEnd(25))
        assertEquals(30L, ranges.nextRun(20))
        assertEquals(20, ranges.gapStart(25))
        assertEquals(0, ranges.gapStart(5))
        assertEquals(12, ranges.gapStart(12))
        ranges.add(20, 30)
        assertEquals(40, ranges.runEnd(10))
        assertEquals(30, ranges.totalBytes())
        ranges.add(5, 50)
        assertEquals("[5-50]", ranges.toString())
        ranges.add(60, 70)
        ranges.add(55, 58)
        assertEquals("[5-50,55-58,60-70]", ranges.toString())
        assertNull(ranges.nextRun(60))
    }

    @Test
    fun parsesContentRange() {
        val range = parseContentRange("bytes 5-9/20")!!
        assertEquals(5, range.start)
        assertEquals(9, range.endInclusive)
        assertEquals(20L, range.total)
        assertNull(parseContentRange("bytes 5-9/*")!!.total)
        assertNull(parseContentRange("bytes */20"))
        assertNull(parseContentRange("bytes 9-5/20"))
        assertNull(parseContentRange(null))
    }

    @Test
    fun deliversTheWholeFileAndOnlyThenEndOfFile() {
        val source = source()
        source.open(5_000)
        assertEquals(content.size.toLong(), source.FILELENPROC(null))
        assertArrayEquals(content, readAll(source))
        assertEquals(-1, source.FILEREADPROC(ByteBuffer.allocateDirect(16), 16, null))
        waitFor(message = "complete") { source.isComplete }
    }

    @Test
    fun droppedConnectionsResumeInsteadOfEndingTheFile() {
        // The bug in the field log: a dropped download used to end the track there.
        server.dropAfterBytes = 512 * 1024
        val source = source()
        source.open(5_000)
        assertArrayEquals(content, readAll(source))
        assertTrue("expected resumed requests", server.ranges.size > 3)
        assertTrue(server.ranges.any { it.startsWith("bytes=") && !it.startsWith("bytes=0-") })
    }

    @Test
    fun missingDataStallsRatherThanEnds() {
        server.bytesPerSecond = 256 * 1024
        val source = source()
        source.open(5_000)
        assertTrue(source.FILESEEKPROC(content.size - 300_000L, null))
        server.refuseAll = true
        val (count, _) = readOnce(source)
        assertEquals("a read past the download must stall, not report EOF", 0, count)
        server.refuseAll = false
        server.bytesPerSecond = 0
        waitFor(message = "data after the outage") { readOnce(source).first > 0 }
    }

    @Test
    fun seekingPastTheDownloadRequestsThatRangeWithoutDownloadingEverything() {
        server.bytesPerSecond = 128 * 1024
        val source = source()
        source.open(5_000)
        val target = content.size - 1_000_000L
        assertTrue(source.FILESEEKPROC(target, null))
        source.beginBlocking(10_000)
        val (count, bytes) = readOnce(source, 8192)
        assertFalse("nothing was starved", source.endBlocking())
        assertTrue(count > 0)
        assertArrayEquals(content.copyOfRange(target.toInt(), target.toInt() + count), bytes)
        assertTrue(
            "expected a range request at the target: ${server.ranges}",
            server.ranges.any { it.startsWith("bytes=$target-") },
        )
        assertTrue("download should not have reached the target sequentially", source.downloadedBytes < target)
    }

    @Test
    fun prioritizedSeekStartsSlightlyBeforeTheTargetForDecoderStepBack() {
        server.bytesPerSecond = 128 * 1024
        val source = source()
        source.open(5_000)
        val target = 3_000_000L
        source.prioritize(target)
        waitFor(message = "seek data") { source.isBuffered(target, 4096) }
        val expected = target - ProgressiveHttpSource.SEEK_LOOKBACK_BYTES
        assertTrue(server.ranges.toString(), server.ranges.any { it.startsWith("bytes=$expected-") })
        assertTrue(source.FILESEEKPROC(target - 1024, null))
        assertTrue("step back lands in fetched data", readOnce(source).first > 0)
    }

    @Test
    fun blockingReadWaitsForDataAndGivesUpAtItsBudget() {
        server.refuseAll = false
        server.bytesPerSecond = 64 * 1024
        val source = source()
        source.open(5_000)
        assertTrue(source.FILESEEKPROC(3_500_000, null))
        server.hang = true
        source.beginBlocking(150)
        val started = System.currentTimeMillis()
        val (count, _) = readOnce(source)
        val elapsed = System.currentTimeMillis() - started
        assertTrue("reports starvation", source.endBlocking())
        assertEquals(0, count)
        assertTrue("waited $elapsed", elapsed in 100..3_000)
    }

    @Test
    fun blockingReadCanBeInterrupted() {
        server.hang = true
        val source = source()
        val opener = thread { runCatching { source.open(200) } }
        opener.join()
        server.hang = false
        source.open(5_000)
        server.bytesPerSecond = 16 * 1024
        assertTrue(source.FILESEEKPROC(3_900_000, null))
        server.hang = true
        var count = -5
        val reader = thread {
            source.beginBlocking(60_000)
            count = readOnce(source).first
        }
        Thread.sleep(100)
        val started = System.currentTimeMillis()
        source.interruptBlocking()
        reader.join(5_000)
        assertFalse(reader.isAlive)
        assertEquals(0, count)
        assertTrue(System.currentTimeMillis() - started < 3_000)
    }

    @Test
    fun cancelAbortsOpen() {
        server.hang = true
        val source = source()
        var failure: Throwable? = null
        val opener = thread { failure = runCatching { source.open(60_000) }.exceptionOrNull() }
        Thread.sleep(100)
        source.cancel()
        opener.join(5_000)
        assertFalse(opener.isAlive)
        assertEquals(SourceException.Kind.CANCELLED, (failure as SourceException).kind)
    }

    @Test
    fun expiredUrlIsFatalAndFlagged() {
        val changes = AtomicInteger()
        server.bytesPerSecond = 256 * 1024
        val source = ProgressiveHttpSource(
            server.url("/audio.flac"),
            emptyMap(),
            File(folder.root, "expired.part"),
            { changes.incrementAndGet() },
        ).also(sources::add)
        source.open(5_000)
        server.statusOverride = 403
        source.retryNow(reconnect = true)
        waitFor(message = "fatal failure") { source.failure != null }
        assertTrue(source.failure!!.expiredUrl)
        assertEquals(403, source.failure!!.status)
        waitFor(message = "state notification") { changes.get() > 0 }
    }

    @Test
    fun openFailsAtOnceOnHttpErrors() {
        server.statusOverride = 404
        val source = source()
        val started = System.currentTimeMillis()
        val failure = runCatching { source.open(10_000) }.exceptionOrNull() as SourceException
        assertEquals(SourceException.Kind.HTTP, failure.kind)
        assertTrue(failure.expiredUrl)
        assertTrue(System.currentTimeMillis() - started < 3_000)
    }

    @Test
    fun openFailsAtOnceWhenTheHostRefusesConnections() {
        val closedPort = ServerSocket(0, 1, InetAddress.getLoopbackAddress()).use { it.localPort }
        val source = source(url = "http://127.0.0.1:$closedPort/audio.flac")
        val started = System.currentTimeMillis()
        val failure = runCatching { source.open(10_000) }.exceptionOrNull() as SourceException
        assertEquals(SourceException.Kind.OFFLINE, failure.kind)
        assertTrue(System.currentTimeMillis() - started < 3_000)
    }

    @Test
    fun openTimesOutOnAServerThatNeverAnswers() {
        server.hang = true
        val source = source()
        val failure = runCatching { source.open(150) }.exceptionOrNull() as SourceException
        assertEquals(SourceException.Kind.TIMEOUT, failure.kind)
    }

    @Test
    fun serverErrorsAreRetriedAndReportedThenClear() {
        server.bytesPerSecond = 512 * 1024
        val source = source()
        source.open(5_000)
        server.statusOverride = 503
        source.retryNow(reconnect = true)
        waitFor(message = "network error") { source.networkError != null }
        assertEquals("http 503", source.networkError)
        assertNull(source.failure)
        server.statusOverride = 0
        source.retryNow(reconnect = false)
        waitFor(message = "recovery") { source.networkError == null && source.downloadedBytes > 0 }
        assertNull(source.failure)
    }

    @Test
    fun serverThatIgnoresRangesStillPlaysSequentially() {
        server.honorRanges = false
        server.bytesPerSecond = 2 * 1024 * 1024
        val source = source()
        source.open(5_000)
        assertTrue(source.FILESEEKPROC(3_000_000, null))
        // Waiting would hold up stream creation; a seek retries once this arrives.
        source.beginBlocking(10_000)
        val started = System.currentTimeMillis()
        assertEquals(0, readOnce(source, 1024).first)
        assertTrue("reports starvation", source.endBlocking())
        assertTrue(System.currentTimeMillis() - started < 1_000)

        waitFor(message = "sequential download") { source.isBuffered(3_000_000, 1024) }
        val (count, bytes) = readOnce(source, 1024)
        assertTrue(count > 0)
        assertArrayEquals(content.copyOfRange(3_000_000, 3_000_000 + count), bytes)
        assertEquals("the only request is the first", 1, server.ranges.size)
        assertTrue(source.FILESEEKPROC(0, null))
        assertArrayEquals(content, readAll(source))
    }

    @Test
    fun blockingReadsNearTheDownloadStillWaitWithoutRanges() {
        server.honorRanges = false
        server.bytesPerSecond = 256 * 1024
        val source = source()
        source.open(5_000)
        assertTrue(source.FILESEEKPROC(ProgressiveHttpSource.REDIRECT_WINDOW_BYTES / 2, null))
        source.beginBlocking(10_000)
        assertTrue(readOnce(source, 1024).first > 0)
        assertFalse(source.endBlocking())
    }

    @Test
    fun aServerThatKeepsEndingTheFileEarlyBecomesFatal() {
        server.bytesPerSecond = 512 * 1024
        val source = source()
        source.open(5_000)
        server.emptyBodies = true
        source.retryNow(reconnect = true)
        waitFor(timeoutMs = 20_000, message = "fatal failure") { source.failure != null }
        assertEquals(SourceException.Kind.HTTP, source.failure!!.kind)
        assertFalse(source.failure!!.expiredUrl)
    }

    @Test
    fun errorsAreClearedWhenNothingIsLeftToFetch() {
        val source = source()
        source.open(5_000)
        assertArrayEquals(content, readAll(source))
        waitFor(message = "complete") { source.isComplete }
        assertNull(source.networkError)
    }

    @Test
    fun errorsKeepUrlTokensOutOfLogs() {
        val secret = "http://127.0.0.1:1/a.flac?vkey=SECRET"
        val failure = object : HttpURLConnection(URL(secret)) {
            override fun connect() = throw IOException("cannot reach $secret")
            override fun disconnect() = Unit
            override fun usingProxy() = false
            override fun getResponseCode(): Int = throw IOException("cannot reach $secret")
        }
        val source = ProgressiveHttpSource(secret, emptyMap(), File(folder.root, "t.part"), {}, { failure })
            .also(sources::add)
        val thrown = runCatching { source.open(100) }.exceptionOrNull()!!
        assertFalse(thrown.message, thrown.message!!.contains("SECRET"))
        assertTrue(thrown.message, thrown.message!!.contains("cannot reach"))
    }

    @Test
    fun unknownLengthIsUnsupportedSoTheCallerCanUseBassStreams() {
        server.chunked = true
        server.honorRanges = false
        val source = source()
        val failure = runCatching { source.open(5_000) }.exceptionOrNull() as SourceException
        assertEquals(SourceException.Kind.UNSUPPORTED, failure.kind)
    }

    @Test
    fun htmlPagesAreNotMistakenForTheFile() {
        server.contentType = "text/html; charset=utf-8"
        server.honorRanges = false
        val source = source()
        val failure = runCatching { source.open(300) }.exceptionOrNull()
        assertNotNull(failure)
        assertEquals(0L, source.FILELENPROC(null))
    }

    @Test
    fun followsRedirectsAndKeepsRequestingTheTarget() {
        server.redirects["/audio.flac"] = "/moved/audio.flac"
        val source = source()
        source.open(5_000)
        assertArrayEquals(content, readAll(source))
        assertEquals(1, server.paths.count { it == "/audio.flac" })
    }

    @Test
    fun expiredRedirectTargetFallsBackToTheOriginalLink() {
        server.redirects["/audio.flac"] = "/moved/audio.flac"
        server.dropAfterBytes = 512 * 1024
        val source = source()
        source.open(5_000)
        waitFor(message = "partial download") { source.downloadedBytes > 0 }
        server.statuses["/moved/audio.flac"] = 403
        server.redirects["/audio.flac"] = "/fresh/audio.flac"
        assertArrayEquals(content, readAll(source))
        assertNull(source.failure)
        assertTrue(server.paths.contains("/fresh/audio.flac"))
    }

    @Test
    fun tailIsFetchedBesideTheMainDownload() {
        server.bytesPerSecond = 128 * 1024
        val source = source()
        source.open(5_000)
        val tail = content.size - ProgressiveHttpSource.TAIL_BYTES
        waitFor(message = "tail") { source.isBuffered(tail, ProgressiveHttpSource.TAIL_BYTES) }
        assertTrue(source.downloadedBytes < content.size)
        assertTrue(server.ranges.toString(), server.ranges.contains("bytes=$tail-${content.size - 1}"))
        // Reading tags at the end must not drag the main download away from the start.
        val before = server.ranges.size
        assertTrue(source.FILESEEKPROC(content.size - 128L, null))
        assertEquals(128, readOnce(source).first)
        assertTrue(source.FILESEEKPROC(0, null))
        Thread.sleep(50)
        assertEquals(before, server.ranges.size)
    }

    @Test
    fun holdKeepsReadsBackUntilEnoughIsBuffered() {
        server.bytesPerSecond = 128 * 1024
        val source = source()
        source.open(5_000)
        source.holdUntilBuffered(256 * 1024)
        val blockedAtStart = readOnce(source).first
        assertEquals("the hold applies while the buffer is small", 0, blockedAtStart)
        waitFor(message = "hold release") { source.isBuffered(0, 256 * 1024) }
        waitFor(message = "reads flowing") { readOnce(source).first > 0 }
    }

    @Test
    fun aFailingDownloadDoesNotWithholdBufferedData() {
        server.bytesPerSecond = 256 * 1024
        val source = source()
        source.open(5_000)
        waitFor(message = "some data") { source.isBuffered(0, 4096) }
        server.statusOverride = 503
        source.retryNow(reconnect = true)
        waitFor(message = "network error") { source.networkError != null }
        source.holdUntilBuffered(Long.MAX_VALUE / 2)
        assertTrue("buffered bytes still play during an outage", readOnce(source).first > 0)
    }

    @Test
    fun closeDeletesTheCacheAndEndsReads() {
        val file = File(folder.root, "closing.part")
        server.bytesPerSecond = 128 * 1024
        val source = ProgressiveHttpSource(server.url("/audio.flac"), emptyMap(), file, {})
        source.open(5_000)
        assertTrue(file.exists())
        source.close()
        assertFalse(file.exists())
        assertEquals(-1, source.FILEREADPROC(ByteBuffer.allocateDirect(16), 16, null))
        assertFalse(source.FILESEEKPROC(0, null))
        source.close()
    }

    /** Minimal HTTP/1.1 file server with scriptable failure modes. */
    private class RangeServer(private val content: ByteArray) {
        private val socket = ServerSocket(0, 50, InetAddress.getLoopbackAddress())
        private val clients = CopyOnWriteArrayList<Socket>()
        val ranges = CopyOnWriteArrayList<String>()
        val paths = CopyOnWriteArrayList<String>()
        val redirects = java.util.concurrent.ConcurrentHashMap<String, String>()
        val statuses = java.util.concurrent.ConcurrentHashMap<String, Int>()
        @Volatile var dropAfterBytes = 0
        @Volatile var bytesPerSecond = 0
        @Volatile var refuseAll = false
        @Volatile var hang = false
        @Volatile var statusOverride = 0
        @Volatile var honorRanges = true
        @Volatile var chunked = false
        @Volatile var contentType = "audio/flac"
        @Volatile var emptyBodies = false

        init {
            thread(isDaemon = true) {
                while (!socket.isClosed) {
                    val client = try {
                        socket.accept()
                    } catch (_: IOException) {
                        return@thread
                    }
                    clients += client
                    thread(isDaemon = true) { serve(client) }
                }
            }
        }

        fun url(path: String) = "http://127.0.0.1:${socket.localPort}$path"

        fun close() {
            socket.close()
            clients.forEach { runCatching { it.close() } }
        }

        private fun serve(client: Socket) {
            try {
                client.use {
                    val input = BufferedInputStream(it.getInputStream())
                    val output = it.getOutputStream()
                    while (true) {
                        val head = readHead(input) ?: return
                        if (!respond(head, output)) return
                    }
                }
            } catch (_: IOException) {
            }
        }

        private fun readHead(input: BufferedInputStream): List<String>? {
            val lines = ArrayList<String>()
            val line = StringBuilder()
            while (true) {
                val value = input.read()
                if (value < 0) return null
                if (value == '\n'.code) {
                    val text = line.toString().trimEnd('\r')
                    line.clear()
                    if (text.isEmpty()) return lines
                    lines += text
                } else {
                    line.append(value.toChar())
                }
            }
        }

        private fun respond(head: List<String>, output: OutputStream): Boolean {
            val path = head.first().split(' ')[1]
            paths += path
            val range = head.firstOrNull { it.startsWith("Range:", ignoreCase = true) }
                ?.substringAfter(':')?.trim()
            if (range != null) ranges += range
            while (hang) Thread.sleep(5)
            if (refuseAll) return false
            redirects[path]?.let { target ->
                output.write("HTTP/1.1 302 Found\r\nLocation: $target\r\nContent-Length: 0\r\n\r\n".toByteArray())
                output.flush()
                return true
            }
            val status = statusOverride.takeIf { it != 0 } ?: statuses[path]
            if (status != null) {
                output.write("HTTP/1.1 $status Error\r\nContent-Length: 0\r\n\r\n".toByteArray())
                output.flush()
                return true
            }
            if (chunked) {
                output.write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Type: $contentType\r\n\r\n0\r\n\r\n".toByteArray())
                output.flush()
                return true
            }
            var start = 0
            var end = content.size - 1
            val partial = honorRanges && range != null
            if (partial) {
                val (first, last) = range!!.removePrefix("bytes=").split('-')
                start = first.toInt()
                if (last.isNotEmpty()) end = last.toInt()
            }
            val headers = buildString {
                append(if (partial) "HTTP/1.1 206 Partial Content\r\n" else "HTTP/1.1 200 OK\r\n")
                if (partial) append("Content-Range: bytes $start-$end/${content.size}\r\n")
                if (honorRanges) append("Accept-Ranges: bytes\r\n")
                append("Content-Type: $contentType\r\n")
                append("Content-Length: ${end - start + 1}\r\n\r\n")
            }
            output.write(headers.toByteArray())
            output.flush()
            if (emptyBodies) return false
            var position = start
            var sent = 0
            val started = System.nanoTime()
            while (position <= end) {
                while (hang) Thread.sleep(5)
                val rate = bytesPerSecond
                if (rate > 0) {
                    val allowed = (System.nanoTime() - started) / 1_000_000_000.0 * rate
                    if (sent > allowed) {
                        Thread.sleep(1)
                        continue
                    }
                }
                val count = minOf(16 * 1024, end - position + 1)
                output.write(content, position, count)
                output.flush()
                position += count
                sent += count
                if (dropAfterBytes > 0 && sent >= dropAfterBytes) return false
            }
            return true
        }
    }
}
