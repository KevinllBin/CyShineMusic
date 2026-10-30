package com.cyshine.bass_player

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.ParcelFileDescriptor
import android.util.Log
import com.un4seen.bass.BASS
import com.un4seen.bass.BASS_FX
import com.un4seen.bass.BASSmix
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.*

/** Owns local decode sources. The plugin retains the output mixer and its global EQ. */
internal class GrooveShiftEngine(
    private val context: Context,
    private val handler: Handler,
    private val open: (String, Int) -> Int,
    private val event: (String, String, Map<String, Any?>) -> Unit,
) {
    private class Source(val uri: String, val handle: Int, val descriptor: ParcelFileDescriptor?) {
        val traceId = "local-${sourceSerial.incrementAndGet()}"

        fun close() {
            BASSmix.BASS_Mixer_ChannelRemove(handle)
            BASS.BASS_StreamFree(handle)
            descriptor?.close()
        }
    }

    private class Prepared(val id: String, val source: Source, val plan: MixPlan) {
        @Volatile var committed = false
        @Volatile var started = false
        @Volatile var handed = false
        var notified = false
        val syncs = ArrayList<Int>()
        val callbacks = ArrayList<BASS.SYNCPROC>()
        val fx = ArrayList<Pair<Int, Int>>()
    }

    companion object {
        private val sourceSerial = AtomicInteger()
    }

    var onDiagnostic: ((String, Map<String, Any?>) -> Unit)? = null

    private fun trace(action: String, fields: Map<String, Any?> = emptyMap()) {
        val callback = onDiagnostic ?: return
        callback(action, clockDetails() + fields)
    }

    fun sourceId(): String? = (if (prepared?.handed == true) prepared?.source else current)?.traceId

    fun clockDetails(): Map<String, Any?> {
        val p = prepared
        val source = if (p?.handed == true) p.source else current
        fun position(handle: Int, mixed: Boolean): Long? {
            if (handle == 0) return null
            val bytes =
                if (mixed) BASSmix.BASS_Mixer_ChannelGetPosition(handle, BASS.BASS_POS_BYTE)
                else BASS.BASS_ChannelGetPosition(handle, BASS.BASS_POS_BYTE)
            if (bytes < 0) return null
            return (BASS.BASS_ChannelBytes2Seconds(handle, bytes) * 1000).toLong()
        }
        return linkedMapOf(
            "generation" to generation.get(),
            "transition" to p?.id,
            "source" to source?.traceId,
            "mixer" to mixer,
            "currentHandle" to current?.handle,
            "incomingHandle" to p?.source?.handle,
            "committed" to p?.committed,
            "started" to p?.started,
            "handed" to p?.handed,
            "ended" to playbackEnded,
            "mixerMs" to position(mixer, false),
            "sourceHeardMs" to source?.let { position(it.handle, true) },
            "sourceDecodedMs" to source?.let { position(it.handle, false) },
        )
    }

    private val generation = AtomicInteger()
    private val worker = Executors.newSingleThreadExecutor { r ->
        Thread(r, "GrooveShift-analysis").apply { isDaemon = true }
    }
    private val cache = LinkedHashMap<String, MixProfile>()
    @Volatile private var current: Source? = null
    @Volatile private var prepared: Prepared? = null
    private var requestedId: String? = null
    @Volatile private var mixer = 0
    @Volatile
    var enabled = false
        private set

    @Volatile private var playbackEnded = false
    private var lastPositionSource: Source? = null
    private var lastPositionMs = 0L

    val active
        get() = mixer != 0

    fun load(uri: String): Int {
        close()
        playbackEnded = false
        lastPositionSource = null
        lastPositionMs = 0L
        val source = source(uri)
        val info = BASS.BASS_CHANNELINFO()
        try {
            checkBass(BASS.BASS_ChannelGetInfo(source.handle, info), "local format")
            mixer =
                BASSmix.BASS_Mixer_StreamCreate(
                    info.freq,
                    2,
                    BASS.BASS_SAMPLE_FLOAT or
                        BASSmix.BASS_MIXER_END or
                        BASSmix.BASS_MIXER_POSEX or
                        (if (BASS.BASS_GetDevice() == 0) BASS.BASS_STREAM_DECODE else 0),
                )
            checkBass(mixer != 0, "create mixer")
            checkBass(
                BASSmix.BASS_Mixer_StreamAddChannel(
                    mixer,
                    source.handle,
                    BASSmix.BASS_MIXER_CHAN_DOWNMIX or BASSmix.BASS_MIXER_CHAN_NORAMPIN,
                ),
                "add source",
            )
            current = source
            trace("local_loaded", mapOf("durationMs" to duration()))
            return mixer
        } catch (t: Throwable) {
            source.close()
            if (mixer != 0) BASS.BASS_StreamFree(mixer)
            mixer = 0
            throw t
        }
    }

    private fun source(uri: String): Source {
        val parsed = Uri.parse(uri)
        var descriptor: ParcelFileDescriptor? = null
        val flags = BASS.BASS_SAMPLE_FLOAT or BASS.BASS_STREAM_DECODE
        val raw =
            try {
                if (parsed.scheme == "content") {
                    descriptor =
                        context.contentResolver.openFileDescriptor(parsed, "r")
                            ?: error("Local URI is not readable")
                    android.system.Os.lseek(
                        descriptor.fileDescriptor,
                        0,
                        android.system.OsConstants.SEEK_CUR,
                    )
                    var decoded = BASS.BASS_StreamCreateFile(descriptor, 0, 0, flags)
                    if (decoded == 0)
                        decoded =
                            com.un4seen.bass.BASSFLAC.BASS_FLAC_StreamCreateFile(
                                descriptor,
                                0,
                                0,
                                flags,
                            )
                    if (decoded == 0)
                        decoded =
                            com.un4seen.bass.BASSAPE.BASS_APE_StreamCreateFile(
                                descriptor,
                                0,
                                0,
                                flags,
                            )
                    if (decoded == 0)
                        decoded =
                            com.un4seen.bass.BASSALAC.BASS_ALAC_StreamCreateFile(
                                descriptor,
                                0,
                                0,
                                flags,
                            )
                    decoded
                } else {
                    require(
                        parsed.scheme == null || parsed.scheme == "" || parsed.scheme == "file"
                    ) {
                        "智能过渡仅支持本地歌曲"
                    }
                    open(if (parsed.scheme == "file") parsed.path!! else uri, flags)
                }
            } catch (failure: Throwable) {
                descriptor?.close()
                throw failure
            }
        if (raw == 0) {
            descriptor?.close()
            error("Open local decode: BASS " + BASS.BASS_ErrorGetCode())
        }
        val tempo =
            BASS_FX.BASS_FX_TempoCreate(raw, BASS.BASS_STREAM_DECODE or BASS_FX.BASS_FX_FREESOURCE)
        if (tempo == 0) {
            BASS.BASS_StreamFree(raw)
            descriptor?.close()
            error("Create tempo: BASS " + BASS.BASS_ErrorGetCode())
        }
        return Source(uri, tempo, descriptor)
    }

    fun position(): Long {
        val p = prepared
        val source = if (p?.handed == true) p.source else current
        if (source == null) return 0
        val total = durationFor(source)
        if (playbackEnded && total != null) return total
        val bytes = BASSmix.BASS_Mixer_ChannelGetPosition(source.handle, BASS.BASS_POS_BYTE)
        val raw =
            if (bytes < 0) 0
            else
                (BASS.BASS_ChannelBytes2Seconds(source.handle, bytes) * 1000)
                    .toLong()
                    .coerceAtLeast(0)
        if (lastPositionSource !== source) {
            lastPositionSource = source
            lastPositionMs = raw
            return raw
        }
        // BASSmix may expose a zero source cursor after the final decoded block
        // has already reached the mixer. Never re-anchor the public clock to 0.
        if (total != null && total > 3000 && raw <= 1000 && lastPositionMs >= total - 1500) {
            return total
        }
        lastPositionMs = raw
        return raw
    }

    private fun durationFor(source: Source): Long? {
        val bytes = BASS.BASS_ChannelGetLength(source.handle, BASS.BASS_POS_BYTE)
        return if (bytes <= 0) null
        else (BASS.BASS_ChannelBytes2Seconds(source.handle, bytes) * 1000).toLong()
    }

    fun markPlaybackEnded() {
        trace("eof")
        playbackEnded = true
    }

    fun resetPlaybackEnded() {
        playbackEnded = false
        lastPositionMs = 0L
    }

    fun duration(): Long? {
        val p = prepared
        val s = if (p?.handed == true) p.source else current
        if (s == null) return null
        return durationFor(s)
    }

    fun seek(ms: Long): Boolean {
        trace("seek", mapOf("targetMs" to ms))
        cancel("seek")
        resetPlaybackEnded()
        val source = current ?: return false
        return BASSmix.BASS_Mixer_ChannelSetPosition(
            source.handle,
            BASS.BASS_ChannelSeconds2Bytes(source.handle, ms / 1000.0),
            BASS.BASS_POS_BYTE or BASSmix.BASS_POS_MIXER_RESET,
        )
    }

    fun configure(value: Boolean) {
        enabled = value
        trace("configure", mapOf("enabled" to value))
        if (!value) cancel("disabled")
    }

    fun confirm(id: String) {
        prepared?.takeIf { it.id == id && !it.started }?.committed = true
        trace("confirm", mapOf("requested" to id))
    }

    fun next(id: String?, uri: String?) {
        if (id == requestedId) return
        cancel("next_changed")
        requestedId = id
        trace("prepare_request", mapOf("requested" to id))
        if (!enabled || id == null || uri == null || current == null) return
        val analysisStarted = android.os.SystemClock.elapsedRealtime()
        val token = generation.get()
        val out = current!!
        val output = mixer
        worker.execute {
            try {
                val a = profile(out.uri, token)
                val b = profile(uri, token)
                if (generation.get() != token) return@execute
                handler.post {
                    if (generation.get() != token || current !== out || mixer != output || !enabled)
                        return@post
                    try {
                        val plan = GrooveShiftPlanner.plan(a, b, position())
                        fun profileSummary(x: MixProfile) =
                            mapOf(
                                "durationMs" to x.duration,
                                "bpm" to x.tempo?.bpm,
                                "beatConfidence" to x.tempo?.confidence,
                                "stability" to x.tempo?.stability,
                                "rms" to x.rms,
                                "audible" to listOf(x.audible.start, x.audible.end),
                                "intro" to listOf(x.intro.range.start, x.intro.range.end),
                                "outro" to listOf(x.outro.range.start, x.outro.range.end),
                            )
                        trace(
                            "plan",
                            mapOf(
                                "requested" to id,
                                "analysisMs" to
                                    (android.os.SystemClock.elapsedRealtime() - analysisStarted),
                                "out" to profileSummary(a),
                                "in" to profileSummary(b),
                                "mode" to plan.mode,
                                "style" to plan.style,
                                "confidence" to plan.confidence,
                                "outgoingCueMs" to plan.outgoingCue,
                                "incomingCueMs" to plan.incomingCue,
                                "transitionMs" to plan.duration,
                                "outgoingRate" to plan.outgoingRate,
                                "incomingEntryBoostDb" to INCOMING_ENTRY_BOOST_DB,
                                "handoff" to plan.handoff(),
                                "events" to plan.events.map { "${it.name}@${it.p}" },
                            ),
                        )
                        Log.i(
                            "GrooveShift",
                            "mode=${plan.mode} style=${plan.style} cue=${plan.outgoingCue} duration=${plan.duration} rate=${plan.outgoingRate}",
                        )
                        event(
                            "planned",
                            id,
                            mapOf(
                                "mode" to plan.mode,
                                "style" to plan.style,
                                "transitionDurationMs" to plan.duration,
                            ),
                        )
                        if (plan.duration <= 0 || plan.outgoingCue - position() <= 2250) {
                            trace(
                                "fallback",
                                mapOf(
                                    "reason" to
                                        if (plan.duration <= 0) "zero_overlap" else "cue_late"
                                ),
                            )
                            return@post
                        }
                        plan.gain = GrooveShiftPlanner.executionGain(plan, a, b)
                        val incoming = source(uri)
                        val p = Prepared(id, incoming, plan)
                        try {
                            arm(p, out, output, token)
                            prepared = p
                            trace("armed")
                        } catch (t: Throwable) {
                            cleanup(p, output)
                            incoming.close()
                            throw t
                        }
                    } catch (t: Throwable) {
                        trace("prepare_failed", mapOf("error" to t.toString().take(350)))
                        Log.w("GrooveShift", "Preparation failed, ordinary advance retained", t)
                    }
                }
            } catch (t: Throwable) {
                handler.post {
                    if (generation.get() == token)
                        trace("analysis_failed", mapOf("error" to t.toString().take(350)))
                }
                if (generation.get() == token)
                    Log.w("GrooveShift", "Analysis failed, ordinary advance retained", t)
            }
        }
    }

    private fun profile(uri: String, token: Int): MixProfile {
        val parsed = Uri.parse(uri)
        val file = if (parsed.scheme == "file") File(parsed.path!!) else File(uri)
        val key =
            if (parsed.scheme == "content") uri else "$uri:${file.length()}:${file.lastModified()}"
        cache[key]?.let {
            return it
        }
        val s = source(uri)
        try {
            val info = BASS.BASS_CHANNELINFO()
            checkBass(BASS.BASS_ChannelGetInfo(s.handle, info), "analysis format")
            val analyzer = GrooveShiftAnalyzer(info.freq, info.chans)
            val buffer = ByteBuffer.allocateDirect(65536).order(ByteOrder.nativeOrder())
            val pcm = FloatArray(16384)
            while (generation.get() == token) {
                buffer.clear()
                val count = BASS.BASS_ChannelGetData(s.handle, buffer, 65536)
                if (count < 0) {
                    check(BASS.BASS_ErrorGetCode() == BASS.BASS_ERROR_ENDED) {
                        "Analysis decode failed"
                    }
                    break
                }
                if (count == 0) break
                buffer.asFloatBuffer().get(pcm, 0, count / 4)
                analyzer.accept(pcm, count / 4)
            }
            check(generation.get() == token) { "Analysis cancelled" }
            val result = analyzer.finish()
            // Content providers may change bytes without exposing a reliable mtime.
            if (parsed.scheme != "content") {
                cache[key] = result
                while (cache.size > 128) cache.remove(cache.keys.first())
            }
            return result
        } finally {
            s.close()
        }
    }

    private fun arm(p: Prepared, out: Source, output: Int, token: Int) {
        BASS.BASS_ChannelLock(output, true)
        try {
            val plan = p.plan
            val source = p.source
            checkBass(
                BASS.BASS_ChannelSetPosition(
                    source.handle,
                    BASS.BASS_ChannelSeconds2Bytes(source.handle, plan.incomingCue / 1000.0),
                    BASS.BASS_POS_BYTE,
                ),
                "incoming seek",
            )
            checkBass(
                BASSmix.BASS_Mixer_StreamAddChannel(
                    output,
                    source.handle,
                    BASSmix.BASS_MIXER_CHAN_DOWNMIX or
                        BASSmix.BASS_MIXER_CHAN_NORAMPIN or
                        BASSmix.BASS_MIXER_CHAN_PAUSE,
                ),
                "preload",
            )
            val now =
                BASS.BASS_ChannelGetPosition(output, BASS.BASS_POS_BYTE or BASS.BASS_POS_DECODE)
            val sourcePosition = BASS.BASS_ChannelGetPosition(out.handle, BASS.BASS_POS_BYTE)
            val decodedMs = BASS.BASS_ChannelBytes2Seconds(out.handle, sourcePosition) * 1000
            val cue =
                now +
                    BASS.BASS_ChannelSeconds2Bytes(output, (plan.outgoingCue - decodedMs) / 1000.0)
            check(cue > now + BASS.BASS_ChannelSeconds2Bytes(output, 2.25)) { "Cue elapsed" }
            fun valid() = generation.get() == token && mixer == output && prepared === p && enabled
            sync(p, output, cue - BASS.BASS_ChannelSeconds2Bytes(output, 2.0), false) {
                if (valid()) handler.post { if (valid()) event("reserve", p.id, emptyMap()) }
            }
            // Install FX and callbacks before the audio callback can start the incoming decoder.
            val processors = GrooveShiftEffects(plan, out.handle, source.handle)
            p.fx.addAll(processors.handles)
            val duration = plan.duration / 1000.0
            val grid = ceil(plan.duration / 25.0).toInt().coerceIn(1, 960)
            val points =
                ((0..grid).map { it.toDouble() / grid } +
                        plan.effects.flatMap { it.nodes.map { n -> n.p } })
                    .distinct()
                    .sorted()
            for (t in points) sync(
                p,
                output,
                cue + BASS.BASS_ChannelSeconds2Bytes(output, duration * t),
                true,
            ) {
                if (valid() && p.started) processors.apply(t)
            }
            for (e in plan.events) {
                if (e.name == "incoming_cue_restart" || e.name.endsWith("_repeat")) {
                    sync(
                        p,
                        output,
                        cue + BASS.BASS_ChannelSeconds2Bytes(output, duration * e.p),
                        true,
                    ) {
                        if (valid() && p.started) {
                            val target =
                                if (e.name == "incoming_cue_restart") plan.incomingCue.toDouble()
                                else {
                                    val beats =
                                        when (e.name) {
                                            "outgoing_four_beat_repeat" -> 4.0
                                            "outgoing_two_beat_repeat" -> 2.0
                                            "outgoing_beat_repeat" -> 1.0
                                            "outgoing_half_beat_repeat" -> .5
                                            else -> .25
                                        }
                                    val drop = plan.events.first { it.name == "performance_drop" }.p
                                    plan.outgoingCue + plan.duration * drop * plan.outgoingRate -
                                        beats *
                                            (plan.effects
                                                .first { it.parameter == "echo_delay_ms" }
                                                .value(0.0) * 4) *
                                            plan.outgoingRate
                                }
                            val channel =
                                if (e.name == "incoming_cue_restart") source.handle else out.handle
                            val firedMs = android.os.SystemClock.elapsedRealtime()
                            val success =
                                BASSmix.BASS_Mixer_ChannelSetPosition(
                                    channel,
                                    BASS.BASS_ChannelSeconds2Bytes(
                                        channel,
                                        max(0.0, target) / 1000,
                                    ),
                                    BASS.BASS_POS_BYTE,
                                )
                            val error = if (success) 0 else BASS.BASS_ErrorGetCode()
                            handler.post {
                                trace(
                                    "source_seek",
                                    mapOf(
                                        "event" to e.name,
                                        "targetMs" to target,
                                        "eventProgress" to e.p,
                                        "firedMonoMs" to firedMs,
                                        "success" to success,
                                        "bassError" to error,
                                        "transition" to p.id,
                                    ),
                                )
                            }
                        }
                    }
                }
            }
            sync(p, output, cue, true) {
                if (valid() && p.committed) {
                    p.started = true
                    BASS.BASS_ChannelSetAttribute(
                        out.handle,
                        BASS_FX.BASS_ATTRIB_TEMPO,
                        ((plan.outgoingRate - 1) * 100).toFloat(),
                    )
                    fun envelope(channel: Int, incoming: Boolean) {
                        val nodes =
                            plan.gain
                                .map {
                                    BASSmix.BASS_MIXER_NODE(
                                        BASS.BASS_ChannelSeconds2Bytes(output, duration * it.p),
                                        (if (incoming) incomingMixGain(it.incoming)
                                            else it.outgoing)
                                            .toFloat(),
                                    )
                                }
                                .toTypedArray()
                        checkBass(
                            BASSmix.BASS_Mixer_ChannelSetEnvelope(
                                channel,
                                BASSmix.BASS_MIXER_ENV_VOL or
                                    (if (incoming) 0 else BASSmix.BASS_MIXER_ENV_REMOVE),
                                nodes,
                                nodes.size,
                            ),
                            "gain envelope",
                        )
                    }
                    envelope(out.handle, false)
                    envelope(source.handle, true)
                    processors.apply(0.0)
                    BASSmix.BASS_Mixer_ChannelFlags(source.handle, 0, BASSmix.BASS_MIXER_CHAN_PAUSE)
                    handler.post { if (valid()) event("started", p.id, emptyMap()) }
                } else handler.post { if (prepared === p) cancel() }
            }
            // Playback-time callbacks account for the output buffer before exposing the new
            // metadata.
            sync(
                p,
                output,
                cue + BASS.BASS_ChannelSeconds2Bytes(output, duration * plan.handoff()),
                false,
            ) {
                if (valid() && p.started) {
                    p.handed = true
                    handler.post { if (valid()) notifyHandoff(p) }
                }
            }
            sync(p, output, cue + BASS.BASS_ChannelSeconds2Bytes(output, duration), false) {
                if (valid() && p.started)
                    handler.post {
                        if (!valid()) return@post
                        if (!p.handed) p.handed = true
                        notifyHandoff(p)
                        BASS.BASS_ChannelLock(output, true)
                        try {
                            cleanup(p, output)
                            out.close()
                            current = source
                            prepared = null
                            requestedId = null
                            BASS.BASS_ChannelSetAttribute(
                                source.handle,
                                BASS_FX.BASS_ATTRIB_TEMPO,
                                0f,
                            )
                        } finally {
                            BASS.BASS_ChannelLock(output, false)
                        }
                        event("finished", p.id, emptyMap())
                    }
            }
        } finally {
            BASS.BASS_ChannelLock(output, false)
        }
    }

    private fun sync(p: Prepared, output: Int, position: Long, mix: Boolean, action: () -> Unit) {
        val callback = BASS.SYNCPROC { _, _, _, _ ->
            try {
                action()
            } catch (t: Throwable) {
                Log.e("GrooveShift", "Automation failed", t)
                handler.post {
                    trace(
                        "automation_failed",
                        mapOf("error" to t.toString().take(350), "failedTransition" to p.id),
                    )
                    if (prepared === p) cancel("automation_failed")
                }
            }
        }
        val handle =
            BASS.BASS_ChannelSetSync(
                output,
                BASS.BASS_SYNC_POS or
                    BASS.BASS_SYNC_ONETIME or
                    (if (mix) BASS.BASS_SYNC_MIXTIME else 0),
                position,
                callback,
                null,
            )
        checkBass(handle != 0, "schedule automation")
        p.syncs.add(handle)
        p.callbacks.add(callback)
    }

    private fun cleanup(p: Prepared, output: Int) {
        for (s in p.syncs) BASS.BASS_ChannelRemoveSync(output, s)
        for ((channel, fx) in p.fx) BASS.BASS_ChannelRemoveFX(channel, fx)
        for (channel in listOfNotNull(current?.handle, p.source.handle)) {
            BASSmix.BASS_Mixer_ChannelSetEnvelope(
                channel,
                BASSmix.BASS_MIXER_ENV_VOL,
                emptyArray(),
                0,
            )
            BASS.BASS_ChannelSetAttribute(channel, BASS.BASS_ATTRIB_VOL, 1f)
            BASS.BASS_ChannelSetAttribute(channel, BASS_FX.BASS_ATTRIB_TEMPO, 0f)
        }
    }

    private fun notifyHandoff(p: Prepared) {
        if (p.notified) return
        p.notified = true
        event("handoff", p.id, emptyMap())
    }

    fun invalidate() {
        generation.incrementAndGet()
    }

    fun cancel(reason: String = "transport") {
        if (prepared != null || requestedId != null) trace("cancel", mapOf("reason" to reason))
        generation.incrementAndGet()
        requestedId = null
        val p = prepared ?: return
        val output = mixer
        BASS.BASS_ChannelLock(output, true)
        try {
            if (p.handed) notifyHandoff(p)
            val retained = if (p.handed) p.source else current
            val audiblePosition =
                retained?.let {
                    BASSmix.BASS_Mixer_ChannelGetPosition(it.handle, BASS.BASS_POS_BYTE)
                } ?: -1
            prepared = null
            cleanup(p, output)
            if (p.handed) {
                current?.close()
                current = p.source
            } else p.source.close()
            if (p.started && retained != null && audiblePosition >= 0) {
                BASSmix.BASS_Mixer_ChannelSetPosition(
                    retained.handle,
                    audiblePosition,
                    BASS.BASS_POS_BYTE or BASSmix.BASS_POS_MIXER_RESET,
                )
            }
        } finally {
            BASS.BASS_ChannelLock(output, false)
        }
        event("cancelled", p.id, emptyMap())
    }

    fun close() {
        cancel("close")
        current?.close()
        current = null
        mixer = 0
    }

    fun dispose() {
        close()
        worker.shutdownNow()
    }

    private fun checkBass(ok: Boolean, label: String) {
        check(ok) { "$label: BASS ${BASS.BASS_ErrorGetCode()}" }
    }
}
