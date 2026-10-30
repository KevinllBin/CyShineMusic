package com.cyshine.bass_player

import com.un4seen.bass.BASS
import com.un4seen.bass.BASS_FX
import kotlin.math.*

internal class GrooveShiftEffects(private val plan: MixPlan, outgoing: Int, incoming: Int) {
    private data class Processor(
        val channel: Int,
        val fx: Int,
        val envelope: MixEffect,
        val sampleRate: Int,
        val channels: Int,
    )

    private val processors = ArrayList<Processor>()
    val handles
        get() = processors.map { it.channel to it.fx }

    init {
        try {
            for (envelope in plan.effects) {
                if (
                    envelope.parameter !in
                        setOf("low_shelf_gain_db", "low_pass_cutoff_hz", "echo_wet")
                )
                    continue
                val channel = if (envelope.incoming) incoming else outgoing
                val info = BASS.BASS_CHANNELINFO()
                check(BASS.BASS_ChannelGetInfo(channel, info))
                val fx =
                    BASS.BASS_ChannelSetFX(
                        channel,
                        if (envelope.parameter == "echo_wet") BASS_FX.BASS_FX_BFX_ECHO4
                        else BASS_FX.BASS_FX_BFX_BQF,
                        0,
                    )
                check(fx != 0) { "Install transition effect: ${BASS.BASS_ErrorGetCode()}" }
                processors.add(Processor(channel, fx, envelope, info.freq, info.chans))
            }
            apply(0.0)
        } catch (t: Throwable) {
            for (p in processors) BASS.BASS_ChannelRemoveFX(p.channel, p.fx)
            throw t
        }
    }

    fun apply(t: Double) {
        for (p in processors) {
            val e = p.envelope
            val v = e.value(t)
            val parameters: Any =
                if (e.parameter == "echo_wet") {
                    fun value(name: String, default: Double) =
                        plan.effects
                            .firstOrNull { it.incoming == e.incoming && it.parameter == name }
                            ?.value(t) ?: default
                    val wet = v.coerceIn(0.0, .38)
                    val feedback = value("echo_feedback", .24).coerceIn(0.0, .38)
                    BASS_FX.BASS_BFX_ECHO4().apply {
                        fDryMix = sqrt(unit(1 - wet * wet / (1 - feedback * feedback))).toFloat()
                        fWetMix = wet.toFloat()
                        fFeedback = feedback.toFloat()
                        fDelay = (value("echo_delay_ms", 125.0) / 1000).coerceIn(.04, 1.5).toFloat()
                        bStereo = p.channels > 1
                        lChannel = -1
                    }
                } else
                    BASS_FX.BASS_BFX_BQF().apply {
                        lChannel = -1
                        fBandwidth = 0f
                        if (e.parameter == "low_shelf_gain_db") {
                            lFilter = 7
                            fCenter = min(160.0, p.sampleRate * .49).toFloat()
                            fGain = v.coerceIn(-15.0, 6.0).toFloat()
                            fS = 1f
                        } else {
                            lFilter = 0
                            fCenter = min(v.coerceIn(400.0, 18000.0), p.sampleRate * .49).toFloat()
                            fQ = .82f
                        }
                    }
            check(BASS.BASS_FXSetParameters(p.fx, parameters)) {
                "Transition FX parameters: ${BASS.BASS_ErrorGetCode()}"
            }
        }
    }
}
