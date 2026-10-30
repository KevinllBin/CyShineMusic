package com.cyshine.bass_player

import kotlin.math.*

/** Scalar rules verified against the original 12.5.1 reference corpus. */
internal object GrooveShiftPlanner {
    fun baseGain(a: MixProfile, b: MixProfile): Pair<List<GainNode>, Double> {
        val ar = a.outro
        val br = b.intro
        val difference =
            (br.rms.coerceIn(-160.0, 24.0) - ar.rms.coerceIn(-160.0, 24.0)).coerceIn(-120.0, 120.0)
        val adjustment =
            (sqrt(ar.confidence * br.confidence) * .45 + .55) * difference.coerceIn(-9.0, 9.0) * .72
        val onset = unit((br.density - .18) / .24)
        val relative =
            unit(
                ((br.rms.coerceIn(-160.0, 24.0) - b.rms.coerceIn(-160.0, 24.0)).coerceIn(
                    -120.0,
                    120.0,
                ) + 3) / 6
            )
        val protect =
            unit((br.confidence * .45 + .55) * max(.28 * relative + .72 * onset, .62 * relative))
        return (0..32).map { i ->
            val p = i / 32.0
            if (i == 0) GainNode(p, 1.0, 0.0)
            else if (i == 32) GainNode(p, 0.0, 1.0)
            else {
                val angle = p.pow(1 - .3 * protect) * PI / 2
                val go = cos(angle)
                val correction =
                    -(1 - (1 - smooth(p)) * (protect * .42)) *
                        (1 - smooth(unit((p - .58) / .42))) *
                        adjustment
                val gi = 10.0.pow(correction / 20) * sin(angle)
                val scale = if (go + gi > 1) 1 / (go + gi) else 1.0
                GainNode(p, unit(go * scale), unit(gi * scale))
            }
        } to protect
    }

    fun plan(
        a: MixProfile,
        b: MixProfile,
        position: Long,
        mask: Int = 63,
        gapless: Boolean = false,
    ): MixPlan {
        val ta = a.tempo
        val tb = b.tempo
        val ar = a.outro
        val br = b.intro
        val (curve, protect) = baseGain(a, b)
        val p = MixPlan("ENERGY_CROSSFADE", .42, 0, br.range.start, 0, gain = curve)
        fun trim() {
            p.mode = "SILENCE_TRIM"
            p.confidence = .3
            p.outgoingCue = a.audible.end
            p.incomingCue = b.audible.start
            p.duration = 0
            p.outgoingRate = 1.0
        }
        fun energy() {
            val duration =
                max(
                    0L,
                    minOf(
                        max(2000L, ((1 - protect * .35) * 8000).roundToLong()),
                        a.audible.end - ar.range.start,
                        b.duration - br.range.start,
                    ),
                )
            if (duration < 2000) trim()
            else {
                p.mode = "ENERGY_CROSSFADE"
                p.confidence = .42
                p.outgoingCue = max(ar.range.start, a.audible.end - duration)
                p.duration = duration
                p.outgoingRate = 1.0
            }
        }
        if (gapless) {
            p.mode = "GAPLESS"
            p.confidence = 1.0
            p.outgoingCue = a.duration
            p.incomingCue = 0
        } else if (ta?.reliable != true || tb?.reliable != true) energy()
        else {
            var ratio = tb.bpm / ta.bpm
            while (ratio > 1.5) ratio /= 2
            while (ratio < 2.0 / 3) ratio *= 2
            if (abs(ratio - 1) > .12) energy()
            else {
                val rate = if (abs(ratio - 1) > 1e-9) ratio else 1.0
                val phrase = ta.downbeat >= .52 && tb.downbeat >= .52
                val beats = if (max(ar.density, br.density) >= .24 || protect >= .45) 16 else 24
                val desired = (beats * 60000 / tb.bpm).roundToLong().coerceIn(2000, 12000)
                val incoming =
                    tb.grid(if (phrase) 24 else 4).firstOrNull {
                        it >= br.range.start && it < br.range.end
                    } ?: br.range.start
                val latest = ar.range.end - (desired * rate).roundToLong()
                val earliest = ar.range.end - (12000 * rate).roundToLong()
                val candidates =
                    if (phrase) (ta.grid(24) + ta.grid(4)).distinct().sorted() else ta.grid(4)
                val cue =
                    candidates.lastOrNull {
                        it >= ar.range.start && it < ar.range.end && it >= earliest && it <= latest
                    } ?: latest.coerceIn(ar.range.start, ar.range.end)
                val duration =
                    max(
                        0L,
                        minOf(
                            ((ar.range.end - cue) / rate).roundToLong(),
                            b.duration - incoming,
                            12000,
                        ),
                    )
                if (duration < 2000) energy()
                else {
                    p.mode = if (abs(rate - 1) <= 1e-9) "BEAT_ALIGNED" else "BEAT_MATCHED"
                    p.confidence =
                        unit(
                            (ta.confidence * tb.confidence * ta.stability * tb.stability).pow(.25) +
                                (if (phrase) min(ta.downbeat, tb.downbeat) * .08 else 0.0)
                        )
                    p.outgoingCue = cue
                    p.incomingCue = incoming
                    p.duration = duration
                    p.outgoingRate = rate
                }
            }
        }
        if (p.duration > 0 && p.outgoingCue < position + 5000) {
            val minimum = position + 5000
            if (minimum >= a.audible.end) trim()
            else {
                var cue =
                    if (ta?.reliable == true)
                        ta.beats.firstOrNull { it >= minimum && it < a.audible.end } ?: minimum
                    else minimum
                fun available(c: Long) =
                    minOf(
                        (max(0L, a.audible.end - c) / p.outgoingRate).toLong(),
                        max(0L, b.duration - p.incomingCue),
                        12000,
                    )
                if (available(cue) < 2000) cue = minimum
                var duration = min(p.duration, available(cue))
                if (duration >= 2000 && tb?.reliable == true) {
                    val beat = 60000 / tb.bpm
                    var n = floor(duration / beat).toInt()
                    n -= n % 4
                    if (n >= 4 && (n * beat).roundToLong() <= duration)
                        duration = (n * beat).roundToLong()
                }
                if (duration < 2000) trim()
                else {
                    p.outgoingCue = cue
                    p.duration = duration
                }
            }
        }
        if (p.duration == 0L) {
            p.gain = listOf(GainNode(0.0, 1.0, 0.0), GainNode(1.0, 0.0, 1.0))
            p.style = if (gapless) "ORIGINAL_CONTINUITY" else "SAFE_FALLBACK"
            return p
        }
        val fade = a.audible.end - ar.range.end
        if (fade >= 3500 && b.duration - br.range.start >= 3500) {
            val delta = unit((ar.rms - br.rms - 6) / 12)
            val density = unit((ar.density - .12) / .32)
            val window = min(10000L, b.duration - br.range.start)
            val raw =
                a.audible.end -
                    (fade + 1800 + delta * 900 - density * 700)
                        .roundToLong()
                        .coerceIn(min(5000L, window), window)
            val cue =
                maxOf(raw, p.outgoingCue, a.audible.end - (b.duration - br.range.start))
                    .coerceIn(a.audible.start, a.audible.end)
            if (a.audible.end - cue >= 3500) {
                p.mode = "ENERGY_CROSSFADE"
                p.outgoingCue = cue
                p.incomingCue = br.range.start
                p.duration = a.audible.end - cue
                p.outgoingRate = 1.0
                GrooveShiftArrangement.fade(p, delta, density, mask and 7 == 7)
                return p
            }
        }
        val qualified = p.mode.startsWith("BEAT_") && p.confidence >= .52
        val sample = mask and 2 != 0
        val spectral = mask and 1 != 0
        val effects = mask and 28 == 28
        val n =
            if (qualified && tb != null) floor(p.duration / (60000 / tb.bpm) + .02).toInt() else 0
        p.style =
            when {
                qualified && sample && spectral && effects && mask and 32 != 0 && n >= 8 ->
                    "STRUCTURAL_RECOMPOSITION"
                qualified && sample && spectral && effects -> "PERFORMANCE_HANDOFF"
                qualified && sample && spectral -> "SPECTRAL_HANDOFF"
                qualified && sample && br.density >= .24 -> "BREATH_DROP"
                qualified && mask and 16 != 0 && ar.confidence >= .78 -> "ECHO_RELEASE"
                sample && spectral -> "SPECTRAL_HANDOFF"
                else -> "TRANSPARENT_BLEND"
            }
        GrooveShiftArrangement.arrange(p, a, b, mask, qualified)
        return p
    }

    fun executionGain(
        p: MixPlan,
        a: MixProfile,
        b: MixProfile,
        outScale: Double = 1.0,
        inScale: Double = 1.0,
    ): List<GainNode> {
        fun scaled(db: Double, scale: Double) =
            db.coerceIn(-160.0, 24.0) + (if (scale <= 0) -160.0 else log10(scale) * 20)
        val outDb = scaled(a.outro.rms, outScale)
        val inDb = scaled(b.intro.rms, inScale)
        val fadeMs = max(0L, a.audible.end - a.outro.range.end)
        val fadeStart =
            if (fadeMs >= 3500) unit((a.outro.range.end - p.outgoingCue).toDouble() / p.duration)
            else 1.0
        val fadeDb = if (fadeStart < 1) (fadeMs / 1000.0 * .75 + 9).coerceIn(9.0, 18.0) else 0.0
        fun effectRatio(incoming: Boolean, s: MixSpectrum, t: Double): Double {
            fun value(name: String, default: Double) =
                p.effects.firstOrNull { it.incoming == incoming && it.parameter == name }?.value(t)
                    ?: default
            val low = value("low_shelf_gain_db", 0.0)
            val cutoff = value("low_pass_cutoff_hz", 18000.0).coerceIn(40.0, 18000.0)
            val powers = listOf(power(s.low), power(s.mid), power(s.high))
            val total = powers.sum()
            if (total <= 1e-32) return 1.0
            fun lp(f: Double) = 1 / (1 + (f / cutoff).pow(4))
            return ((lp(100.0) * 10.0.pow(low.coerceIn(-18.0, 18.0) / 10) * powers[0] +
                    lp(1000.0) * powers[1] +
                    lp(4800.0) * powers[2]) / total)
                .coerceIn(1e-4, 16.0)
        }
        return ((0..32).map { it / 32.0 } + p.gain.map { it.p }).distinct().sorted().map { t ->
            val g = p.gainAt(t)
            var go = g.outgoing
            var gi = g.incoming
            if (t > 0 && t < 1 && go + gi > 1e-12) {
                val balance = smooth(unit(gi / (go + gi)))
                val fade =
                    if (fadeStart < 1 && t > fadeStart)
                        smooth(unit((t - fadeStart) / (1 - fadeStart)))
                    else 0.0
                val target = outDb + (inDb - outDb) * balance
                val mixed =
                    effectRatio(false, a.outroSpectrum, t) *
                        power(outDb - fade * fadeDb) *
                        go *
                        go + effectRatio(true, b.introSpectrum, t) * power(inDb) * gi * gi
                if (mixed > 1e-32) {
                    val scale =
                        minOf(
                            10.0.pow((target - log10(mixed) * 10).coerceIn(-6.0, 3.25) / 20),
                            if (go > 1e-12) 1 / go else Double.POSITIVE_INFINITY,
                            if (gi > 1e-12) 1 / gi else Double.POSITIVE_INFINITY,
                        )
                    go = unit(go * scale)
                    gi = unit(gi * scale)
                }
            }
            GainNode(t, go, gi)
        }
    }
}
