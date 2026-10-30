package com.cyshine.bass_player

import kotlin.math.*

internal fun unit(x: Double) = x.coerceIn(0.0, 1.0)

internal fun smooth(x: Double) = (3 - 2 * x) * x * x

internal const val INCOMING_ENTRY_BOOST_DB = 2.0

/** A small playback-only lift, fading back to unity as the incoming track takes over. */
internal fun incomingMixGain(gain: Double): Double {
    val input = unit(gain)
    val boostDb = INCOMING_ENTRY_BOOST_DB * (1 - smooth(input))
    return unit(input * 10.0.pow(boostDb / 20))
}

internal fun power(db: Double) = 10.0.pow(db.coerceIn(-320.0, 48.0) / 10)

internal fun db(power: Double) =
    if (power <= 1e-16 || !power.isFinite()) -160.0 else 10 * log10(power)

internal data class MixRange(val start: Long, val end: Long)

internal data class MixRegion(
    val range: MixRange,
    val rms: Double,
    val density: Double,
    val confidence: Double,
)

internal data class MixSpectrum(
    val low: Double,
    val mid: Double,
    val high: Double,
    val lowShare: Double = power(low) / max(1e-32, power(low) + power(mid) + power(high)),
)

internal data class MixTempo(
    val bpm: Double,
    val beats: List<Long>,
    val offset: Int,
    val confidence: Double,
    val downbeat: Double,
    val stability: Double,
) {
    val reliable
        get() = confidence >= .5 && stability >= .56

    fun grid(n: Int) = beats.filterIndexed { i, _ -> (i - offset) % n == 0 }
}

internal data class MixProfile(
    val duration: Long,
    val audible: MixRange,
    val rms: Double,
    val peak: Double,
    val tempo: MixTempo?,
    val intro: MixRegion,
    val outro: MixRegion,
    val introSpectrum: MixSpectrum,
    val outroSpectrum: MixSpectrum,
)

internal data class GainNode(val p: Double, val outgoing: Double, val incoming: Double)

internal data class EffectNode(val p: Double, val value: Double)

internal data class MixEffect(
    val incoming: Boolean,
    val parameter: String,
    val nodes: List<EffectNode>,
) {
    fun value(p: Double): Double {
        if (p <= nodes.first().p) return nodes.first().value
        val b = nodes.indexOfFirst { it.p >= p }
        if (b < 0) return nodes.last().value
        val a = nodes[b - 1]
        val z = nodes[b]
        return a.value + (z.value - a.value) * unit((p - a.p) / (z.p - a.p))
    }
}

internal data class MixEvent(val name: String, val p: Double)

internal data class MixPlan(
    var mode: String,
    var confidence: Double,
    var outgoingCue: Long,
    var incomingCue: Long,
    var duration: Long,
    var outgoingRate: Double = 1.0,
    var incomingRate: Double = 1.0,
    var style: String = "SAFE_FALLBACK",
    var gain: List<GainNode> = emptyList(),
    var effects: List<MixEffect> = emptyList(),
    var events: List<MixEvent> = emptyList(),
) {
    fun gainAt(p: Double): GainNode {
        if (p <= gain.first().p) return gain.first()
        val b = gain.indexOfFirst { it.p >= p }
        if (b < 0) return gain.last()
        val a = gain[b - 1]
        val z = gain[b]
        val t = unit((p - a.p) / (z.p - a.p))
        return GainNode(
            p,
            a.outgoing + (z.outgoing - a.outgoing) * t,
            a.incoming + (z.incoming - a.incoming) * t,
        )
    }

    fun handoff(): Double {
        events
            .firstOrNull { it.name == "incoming_cue_restart" || it.name == "musical_handoff" }
            ?.let {
                return it.p
            }
        for (i in 1 until gain.size) {
            val a = gain[i - 1]
            val b = gain[i]
            if (b.incoming >= b.outgoing) {
                val da = a.incoming - a.outgoing
                val dz = b.incoming - b.outgoing
                return a.p + (b.p - a.p) * unit(-da / (dz - da))
            }
        }
        return .5
    }
}
