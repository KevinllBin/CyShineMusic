package com.cyshine.bass_player

import android.os.SystemClock
import android.util.Log
import org.json.JSONObject

internal enum class DiagnosticCategory(val scope: String) {
    PLAYBACK("player-trace"),
    SMART_TRANSITION("groove-shift-trace"),
}

/** Called on the engine handler, never writes files or serializes on the audio callback. */
internal class PlaybackDiagnostics(private val emit: (Map<String, Any?>) -> Unit) {
    private val lines = ArrayDeque<Map<String, Any?>>()
    private val lastAt = LinkedHashMap<String, Long>()
    private val omitted = HashMap<String, Int>()
    private var sequence = 0L
    var playbackEnabled = false
        private set
    var smartTransitionEnabled = false
        private set

    fun configure(playback: Boolean, smartTransition: Boolean) {
        playbackEnabled = playback
        smartTransitionEnabled = smartTransition
        lastAt.clear()
        omitted.clear()
    }

    fun record(
        action: String,
        fields: Map<String, Any?>,
        intervalMs: Long = 0,
        category: DiagnosticCategory = DiagnosticCategory.SMART_TRANSITION,
    ) {
        val enabled = when (category) {
            DiagnosticCategory.PLAYBACK -> playbackEnabled
            DiagnosticCategory.SMART_TRANSITION -> smartTransitionEnabled
        }
        if (!enabled) return
        val now = SystemClock.elapsedRealtime()
        val previous = lastAt[action]
        if (intervalMs > 0 && previous != null && now - previous < intervalMs) {
            omitted[action] = (omitted[action] ?: 0) + 1
            return
        }
        lastAt[action] = now
        if (lastAt.size > 32) lastAt.remove(lastAt.keys.first())
        val line =
            linkedMapOf<String, Any?>(
                "traceSeq" to ++sequence,
                "monoMs" to now,
                "action" to action,
                "scope" to category.scope,
            )
        line.putAll(fields)
        omitted.remove(action)?.let { line["omitted"] = it }
        lines.addLast(line)
        while (lines.size > 240) lines.removeFirst()
        Log.i("CyShineTrace", JSONObject(line).toString())
        emit(line)
    }

    fun recent(): List<Map<String, Any?>> = lines.toList()
}
