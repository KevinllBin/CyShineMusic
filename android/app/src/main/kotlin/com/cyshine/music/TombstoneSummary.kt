package com.cyshine.music

import java.io.ByteArrayOutputStream
import java.io.InputStream

/**
 * Condenses the protobuf tombstone Android keeps for a native crash into the
 * few lines needed to locate it: signal, abort message and the crashing
 * thread's backtrace. Field numbers follow AOSP debuggerd/proto/tombstone.proto.
 */
object TombstoneSummary {
    private const val MAX_BYTES = 8 * 1024 * 1024
    private const val MAX_FRAMES = 40
    private const val MAX_TEXT = 200
    private const val MAX_LOGS = 12
    private const val MAX_LOG_TEXT = 600

    fun read(stream: InputStream): String? {
        val bytes = stream.use { readBounded(it) } ?: return "tombstone too large"
        if (bytes.isEmpty()) return null
        return runCatching { summarize(bytes) }
            .getOrElse { "tombstone parse failed: ${it.javaClass.simpleName} size=${bytes.size}" }
    }

    private fun readBounded(stream: InputStream): ByteArray? {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(64 * 1024)
        while (true) {
            val count = stream.read(buffer)
            if (count < 0) break
            output.write(buffer, 0, count)
            if (output.size() > MAX_BYTES) return null
        }
        return output.toByteArray()
    }

    private fun summarize(bytes: ByteArray): String {
        var tid = 0L
        var signal = ""
        var abortMessage = ""
        val causes = mutableListOf<String>()
        // tid -> (start, length) of the embedded Thread message.
        val threads = mutableMapOf<Long, Pair<Int, Int>>()
        val logs = ArrayDeque<String>()
        fields(bytes, 0, bytes.size) { field, value, start, length ->
            when (field) {
                6 -> tid = value
                10 -> signal = signalText(bytes, start, length)
                14 -> abortMessage = text(bytes, start, length)
                15 -> fields(bytes, start, length) { f, _, s, l ->
                    if (f == 1) causes.add(text(bytes, s, l))
                }
                16 -> {
                    var key = 0L
                    var thread: Pair<Int, Int>? = null
                    fields(bytes, start, length) { f, v, s, l ->
                        if (f == 1) key = v
                        if (f == 2) thread = s to l
                    }
                    thread?.let { threads[key] = it }
                }
                18 -> fields(bytes, start, length) { f, _, s, l ->
                    if (f == 2) logLine(bytes, s, l)?.let {
                        if (logs.size == MAX_LOGS) logs.removeFirst()
                        logs.addLast(it)
                    }
                }
            }
        }
        val lines = mutableListOf("signal: $signal tid=$tid")
        if (abortMessage.isNotEmpty()) lines.add("abort: $abortMessage")
        causes.forEach { lines.add("cause: $it") }
        val thread = threads[tid]
        if (thread == null) {
            lines.add("crashing thread not found threads=${threads.size}")
        } else {
            threadLines(bytes, thread.first, thread.second, lines)
        }
        logs.forEach { lines.add("log: $it") }
        return lines.joinToString("\n")
    }

    /**
     * The engine reports why a render target could not be made (the "Impeller
     * validation" errors) to logcat just before it crashes on the missing one.
     */
    private fun logLine(bytes: ByteArray, start: Int, length: Int): String? {
        var priority = 0L
        var tag = ""
        var message = ""
        fields(bytes, start, length) { field, value, s, l ->
            when (field) {
                4 -> priority = value
                5 -> tag = text(bytes, s, l)
                6 -> message = text(bytes, s, l, MAX_LOG_TEXT)
            }
        }
        // 5 is android.util.Log.WARN.
        if (priority < 5 || tag != "flutter" && !message.contains("Impeller")) return null
        return "$tag: $message"
    }

    private fun signalText(bytes: ByteArray, start: Int, length: Int): String {
        var name = ""
        var codeName = ""
        var hasFaultAddress = false
        var faultAddress = 0L
        fields(bytes, start, length) { field, value, s, l ->
            when (field) {
                2 -> name = text(bytes, s, l)
                4 -> codeName = text(bytes, s, l)
                8 -> hasFaultAddress = value != 0L
                9 -> faultAddress = value
            }
        }
        val fault = if (hasFaultAddress) " fault=0x${faultAddress.toULong().toString(16)}" else ""
        return "$name $codeName$fault"
    }

    private fun threadLines(bytes: ByteArray, start: Int, length: Int, lines: MutableList<String>) {
        var name = ""
        val frames = mutableListOf<Pair<Int, Int>>()
        fields(bytes, start, length) { field, _, s, l ->
            if (field == 2) name = text(bytes, s, l)
            if (field == 4) frames.add(s to l)
        }
        lines.add("thread: $name frames=${frames.size}")
        val seenFiles = mutableSetOf<String>()
        frames.take(MAX_FRAMES).forEachIndexed { index, (s, l) ->
            var relPc = 0L
            var function = ""
            var offset = 0L
            var file = ""
            var buildId = ""
            fields(bytes, s, l) { field, value, fs, fl ->
                when (field) {
                    1 -> relPc = value
                    4 -> function = text(bytes, fs, fl)
                    5 -> offset = value
                    6 -> file = text(bytes, fs, fl)
                    8 -> buildId = text(bytes, fs, fl)
                }
            }
            val line = StringBuilder("#%02d pc 0x%s %s".format(index, relPc.toULong().toString(16), file))
            if (function.isNotEmpty()) line.append(" ($function+$offset)")
            if (buildId.isNotEmpty() && seenFiles.add(file)) line.append(" (BuildId: $buildId)")
            lines.add(line.toString())
        }
    }

    private fun text(bytes: ByteArray, start: Int, length: Int, max: Int = MAX_TEXT): String {
        val value = String(bytes, start, length, Charsets.UTF_8).trim()
        return if (value.length <= max) value else value.substring(0, max) + "…"
    }

    /**
     * Walks one protobuf message. Varint fields report [value]; length-delimited
     * fields report the payload's start and length within [bytes].
     */
    private inline fun fields(
        bytes: ByteArray,
        start: Int,
        length: Int,
        visit: (field: Int, value: Long, start: Int, length: Int) -> Unit,
    ) {
        var position = start
        val end = start + length
        while (position < end) {
            var tag = 0L
            var shift = 0
            while (true) {
                val byte = bytes[position++].toInt()
                tag = tag or ((byte and 0x7f).toLong() shl shift)
                if (byte and 0x80 == 0) break
                shift += 7
            }
            val field = (tag ushr 3).toInt()
            when ((tag and 7).toInt()) {
                0 -> {
                    var value = 0L
                    shift = 0
                    while (true) {
                        val byte = bytes[position++].toInt()
                        if (shift < 64) value = value or ((byte and 0x7f).toLong() shl shift)
                        if (byte and 0x80 == 0) break
                        shift += 7
                    }
                    visit(field, value, 0, 0)
                }
                1 -> position += 8
                2 -> {
                    var size = 0
                    shift = 0
                    while (true) {
                        val byte = bytes[position++].toInt()
                        size = size or ((byte and 0x7f) shl shift)
                        if (byte and 0x80 == 0) break
                        shift += 7
                    }
                    require(size >= 0 && position + size <= end)
                    visit(field, 0L, position, size)
                    position += size
                }
                5 -> position += 4
                else -> throw IllegalArgumentException("wire type")
            }
        }
    }
}
