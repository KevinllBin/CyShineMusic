package com.cyshine.bass_player

import kotlin.math.*

/** Streaming 11025 Hz, 1024 point Hann FFT with 256 sample hops. No full PCM retention. */
internal class GrooveShiftAnalyzer(private val sampleRate: Int, private val channels: Int) {
    private val frame = FloatArray(1024)
    private val window = DoubleArray(1024) { .5 - cos(it * 2 * PI / 1023) * .5 }
    private val real = DoubleArray(1024)
    private val imag = DoubleArray(1024)
    private val previous = DoubleArray(513)
    private val rms = ArrayList<Float>()
    private val flux = ArrayList<Float>()
    private val bassFlux = ArrayList<Float>()
    private val bands = Array(3) { ArrayList<Float>() }
    private var filled = 0
    private var inputFrames = 0L
    private var samples = 0L
    private var squares = 0.0
    private var peak = 0.0
    private var last = 0.0
    private var next = 0.0
    private val step = sampleRate / 11025.0
    private var z1 = 0.0
    private var z2 = 0.0
    private val omega = 2 * PI * 4961.25 / sampleRate
    private val alpha = sin(omega) / sqrt(2.0)
    private val divisor = 1 + alpha
    private val b0 = (1 - cos(omega)) / 2 / divisor
    private val b1 = (1 - cos(omega)) / divisor
    private val a1 = -2 * cos(omega) / divisor
    private val a2 = (1 - alpha) / divisor

    fun accept(pcm: FloatArray, count: Int) {
        var i = 0
        while (i + channels <= count) {
            var sum = 0.0
            var sq = 0.0
            var strongest = 0.0
            for (c in 0 until channels) {
                val x = pcm[i + c].toDouble().let { if (it.isFinite()) it else 0.0 }
                sum += x
                sq += x * x
                if (abs(x) > abs(strongest)) strongest = x
            }
            val mean = sum / channels
            var mono = if (abs(mean) >= sqrt(sq / channels) * .125) mean else strongest
            if (sampleRate > 11025) {
                val y = b0 * mono + z1
                z1 = b1 * mono - a1 * y + z2
                z2 = b0 * mono - a2 * y
                mono = y
            }
            val index = inputFrames.toDouble()
            if (inputFrames == 0L) {
                push(mono)
                next += step
            } else
                while (next <= index) {
                    push(last + (mono - last) * (next - (index - 1)).coerceIn(0.0, 1.0))
                    next += step
                }
            last = mono
            inputFrames++
            i += channels
        }
    }

    private fun push(value: Double) {
        val x = if (value.isFinite()) value else 0.0
        squares += x * x
        peak = max(peak, abs(x))
        samples++
        frame[filled++] = x.toFloat()
        if (filled == 1024) {
            feature()
            frame.copyInto(frame, 0, 256, 1024)
            filled = 768
        }
    }

    private fun feature() {
        var energy = 0.0
        for (i in frame.indices) {
            val x = frame[i].toDouble()
            energy += x * x
            real[i] = x * window[i]
            imag[i] = 0.0
        }
        rms.add(db(energy / 1024).toFloat())
        var j = 0
        for (i in 1..1023) {
            var bit = 512
            while (j and bit != 0) {
                j = j xor bit
                bit = bit shr 1
            }
            j = j xor bit
            if (i < j) {
                val r = real[i]
                real[i] = real[j]
                real[j] = r
                val q = imag[i]
                imag[i] = imag[j]
                imag[j] = q
            }
        }
        var size = 2
        while (size <= 1024) {
            val cr = cos(-2 * PI / size)
            val ci = sin(-2 * PI / size)
            for (start in 0 until 1024 step size) {
                var wr = 1.0
                var wi = 0.0
                for (k in 0 until size / 2) {
                    val a = start + k
                    val b = a + size / 2
                    val tr = wr * real[b] - wi * imag[b]
                    val ti = wr * imag[b] + wi * real[b]
                    real[b] = real[a] - tr
                    imag[b] = imag[a] - ti
                    real[a] += tr
                    imag[a] += ti
                    val w = wr * cr - wi * ci
                    wi = wi * cr + wr * ci
                    wr = w
                }
            }
            size *= 2
        }
        var onset = 0.0
        var lowOnset = 0.0
        val energyBands = DoubleArray(3)
        for (k in 1..512) {
            val p = real[k] * real[k] + imag[k] * imag[k]
            val magnitude = ln(sqrt(p) + 1)
            val delta = max(0.0, magnitude - previous[k])
            previous[k] = magnitude
            onset += delta
            val hz = k * 11025.0 / 1024
            if (hz <= 220) lowOnset += delta
            energyBands[if (hz <= 180) 0 else if (hz <= 4000) 1 else 2] += p
        }
        flux.add((onset / 512).toFloat())
        bassFlux.add((lowOnset / 20).toFloat())
        for (k in 0..2) bands[k].add(db(energyBands[k] / 1048576).toFloat())
    }

    fun finish(): MixProfile {
        if (filled >= 256 && rms.isEmpty()) {
            for (i in filled..1023) frame[i] = 0f
            feature()
        }
        val duration = inputFrames * 1000 / sampleRate
        val integrated = db(if (samples > 0) squares / samples else 0.0)
        val energy = rms.toFloatArray()
        val onset = normalize(flux.toFloatArray())
        val lowOnset = normalize(bassFlux.toFloatArray())
        val threshold = max(-60.0, integrated - 36)
        var start = 0
        var end = 0
        if (energy.any { it > -150 }) {
            var run = 0
            start = -1
            for (i in energy.indices) {
                run = if (energy[i] >= threshold) run + 1 else 0
                if (run >= 7) {
                    start = i - 6
                    break
                }
            }
            if (start < 0) {
                start = 0
                end = energy.size
            } else {
                end = energy.size
                run = 0
                for (i in energy.lastIndex downTo start) {
                    run = if (energy[i] >= threshold) run + 1 else 0
                    if (run >= 7) {
                        end = (i + 7).coerceIn(start + 1, energy.size)
                        break
                    }
                }
            }
        }
        val audibleStart = floor(start * 1000 / FPS).toLong().coerceIn(0, duration)
        val audibleEnd =
            if (start == end) audibleStart
            else (ceil(end * 1000 / FPS).toLong() + 93).coerceIn(audibleStart, duration)
        val tempo = tempo(onset, lowOnset, start, end)
        val fade = fade(energy, onset, start, end)
        var exitEnd =
            if (fade == null) audibleEnd
            else floor(fade * 1000 / FPS).toLong().coerceIn(audibleStart, audibleEnd)
        if (fade != null && tempo?.reliable == true)
            tempo
                .grid(4)
                .lastOrNull {
                    it in audibleStart..exitEnd &&
                        exitEnd - it <= (480000 / tempo.bpm).roundToLong()
                }
                ?.let { exitEnd = it }
        val grid =
            if (tempo?.reliable == true) tempo.grid(if (tempo.downbeat >= .58) 16 else 4)
            else emptyList()
        val length =
            if (tempo?.reliable == true) (1920000 / tempo.bpm).toLong().coerceIn(4000, 24000)
            else 10000L
        val introStart = min(audibleEnd, grid.firstOrNull { it >= audibleStart } ?: audibleStart)
        val intro = MixRange(introStart, min(audibleEnd, introStart + length))
        var exitStart = max(audibleStart, exitEnd - length)
        grid.lastOrNull { it in audibleStart..exitStart }?.let { exitStart = it }
        val outro = MixRange(min(exitStart, exitEnd), exitEnd)
        fun bounds(r: MixRange): IntRange {
            if (energy.isEmpty() || r.start == r.end) return IntRange.EMPTY
            val lo = floor(r.start * FPS / 1000).toInt().coerceIn(0, energy.lastIndex)
            val hi = ceil(r.end * FPS / 1000).toInt().coerceIn(lo + 1, energy.size)
            return lo until hi
        }
        fun region(r: MixRange): MixRegion {
            val ix = bounds(r)
            return MixRegion(
                r,
                if (ix.isEmpty()) -160.0 else ix.sumOf { energy[it].toDouble() } / ix.count(),
                if (ix.isEmpty()) 0.0 else ix.count { onset[it] >= .35f }.toDouble() / ix.count(),
                tempo?.confidence ?: .25,
            )
        }
        fun spectrum(r: MixRange): MixSpectrum {
            val ix = bounds(r)
            val values =
                (0..2).map { k ->
                    if (ix.isEmpty()) -160.0
                    else
                        db(
                            ix.sumOf {
                                val v = bands[k][it]
                                if (v <= -160) 0.0 else 10.0.pow(v / 10.0)
                            } / ix.count()
                        )
                }
            val total = values.sumOf { if (it <= -160) 0.0 else power(it) }
            return MixSpectrum(
                values[0],
                values[1],
                values[2],
                if (total <= 1e-16) 0.0 else unit(power(values[0]) / total),
            )
        }
        return MixProfile(
            duration,
            MixRange(audibleStart, audibleEnd),
            integrated,
            if (peak <= 1e-8) -160.0 else 20 * log10(peak),
            tempo,
            region(intro),
            region(outro),
            spectrum(intro),
            spectrum(outro),
        )
    }

    private fun normalize(x: FloatArray): FloatArray {
        val sums = DoubleArray(x.size + 1)
        for (i in x.indices) sums[i + 1] = sums[i] + x[i]
        val y =
            FloatArray(x.size) { i ->
                val lo = max(0, i - 22)
                val hi = min(x.size, i + 23)
                max(0.0, x[i] - (sums[hi] - sums[lo]) / max(1, hi - lo) * .65).toFloat()
            }
        val positive = y.filter { it > 0 }.sorted()
        if (positive.isEmpty()) return y
        val scale = max(1e-8f, positive[floor((positive.size - 1) * .95).toInt()])
        for (i in y.indices) y[i] = (y[i] / scale).coerceIn(0f, 1f)
        return y
    }

    private fun correlation(x: FloatArray, start: Int, end: Int, lag: Int): Double {
        var aa = 0.0
        var bb = 0.0
        var ab = 0.0
        for (i in start + lag until end) {
            val a = x[i].toDouble()
            val b = x[i - lag].toDouble()
            aa += a * a
            bb += b * b
            ab += a * b
        }
        val norm = sqrt(aa * bb)
        return if (norm > 1e-12) ab / norm else 0.0
    }

    private fun refine(c: DoubleArray, i: Int): Double {
        val v = c[i - 1] - 2 * c[i] + c[i + 1]
        return if (abs(v) < 1e-12) i.toDouble()
        else i + ((c[i - 1] - c[i + 1]) * .5 / v).coerceIn(-.5, .5)
    }

    private fun median(x: List<Double>): Double {
        if (x.isEmpty()) return 0.0
        val s = x.sorted()
        return if (s.size % 2 == 0) (s[s.size / 2 - 1] + s[s.size / 2]) / 2 else s[s.size / 2]
    }

    private fun interpolate(x: FloatArray, p: Double): Double {
        val i = floor(p).toInt().coerceIn(0, x.lastIndex)
        val j = min(x.lastIndex, i + 1)
        return x[i] + (x[j] - x[i]).toDouble() * unit(p - i)
    }

    private fun tempo(x: FloatArray, low: FloatArray, start: Int, end: Int): MixTempo? {
        val count = end - start
        if (count < 344.53125 || end > x.size) return null
        val c = DoubleArray(82) { if (it >= 13) correlation(x, start, end, it) else 0.0 }
        fun score(c: DoubleArray, i: Int) = c[i] + c.getOrElse(i * 2) { 0.0 } * .35 + c[i / 2] * .12
        val best =
            (13..40).maxByOrNull { i ->
                score(c, i) *
                    (.84 + .16 * exp(-.5 * ((ln((2583.984375 / i) / 115) / ln(2.0)) / .9).pow(2)))
            } ?: return null
        if (score(c, best) <= 0) return null
        val period = refine(c, best)
        val phases = max(16, ceil(period * 4).toInt())
        val phase =
            (0 until phases).maxByOrNull { i ->
                var sum = 0.0
                var n = 0
                var t = start + i * period / phases
                while (t < end) {
                    sum += interpolate(x, t)
                    n++
                    t += period
                }
                if (n == 0) 0.0 else sum / sqrt(n.toDouble())
            } ?: 0
        val beats = ArrayList<Double>()
        val radius = max(1, floor(period * .16).toInt())
        var t = start + phase * period / phases
        while (t < end) {
            val center = t.toInt()
            val lo = max(start, center - radius)
            val hi = min(end - 1, center + radius)
            val at =
                (lo..hi).maxByOrNull { i -> x[i] - (abs(i - t) / max(period, 1.0) * .08).toFloat() }
                    ?: center
            if (beats.isEmpty() || at - beats.last() > period * .55) beats.add(at.toDouble())
            t += period
        }
        if (beats.size < 8) return null
        val intervals = beats.zipWithNext { a, b -> b - a }
        val med = median(intervals)
        val stability = unit(1 - (median(intervals.map { abs(it - med) }) / med) / .12)
        val parts = min(4, floor(count / 344.53125).toInt())
        val drifts = ArrayList<Double>()
        if (parts >= 2)
            for (part in 0 until parts) {
                val lo = start + count * part / parts
                val hi = start + count * (part + 1) / parts
                if (hi - lo <= 40) continue
                val local = DoubleArray(82) { if (it >= 13) correlation(x, lo, hi, it) else 0.0 }
                val candidate = (13..40).maxByOrNull { score(local, it) } ?: continue
                if (score(local, candidate) > .05) {
                    var ratio = refine(local, candidate) / period
                    while (ratio >= sqrt(2.0)) ratio /= 2
                    while (ratio < 1 / sqrt(2.0)) ratio *= 2
                    drifts.add(abs(ln(ratio) / ln(2.0)))
                }
            }
        val consistent =
            min(stability, if (drifts.size >= 2) unit(1 - drifts.average() / .12) else 1.0)
        val competitor =
            (13..40)
                .filter {
                    abs(it - best) > 2 &&
                        abs(it.toDouble() / best - 2) >= .08 &&
                        abs(it.toDouble() / best - .5) >= .08
                }
                .maxOfOrNull { c[it] } ?: 0.0
        val prominence = if (c[best] > 1e-12) unit((c[best] - competitor) / c[best]) else 0.0
        val hit = beats.sumOf { interpolate(x, it) } / beats.size
        val background = (start until end).sumOf { x[it].toDouble() } / max(1, count)
        val contrast = if (hit > 0) unit((hit - background) / max(hit, 1e-12)) else 0.0
        val confidence = unit(consistent * .2 + contrast * .34 + prominence * .46)
        val strength = DoubleArray(4)
        val counts = IntArray(4)
        for ((i, b) in beats.withIndex()) {
            val at = b.toInt().coerceIn(0, x.lastIndex)
            strength[i % 4] += x[at] * .25 + low[at] * .75
            counts[i % 4]++
        }
        for (i in 0..3) if (counts[i] > 0) strength[i] /= counts[i]
        val offset = (0..3).maxByOrNull { strength[it] } ?: 0
        val downbeat =
            if (strength[offset] > 1e-12)
                unit((strength[offset] - strength.average()) / strength[offset] * 2)
            else 0.0
        return MixTempo(
            2583.984375 / med,
            beats.map { (it * 1000 / FPS).toLong() },
            offset,
            confidence,
            downbeat,
            consistent,
        )
    }

    private fun fade(energy: FloatArray, onset: FloatArray, start: Int, end: Int): Int? {
        if (end - start < 238) return null
        val sums = DoubleArray(energy.size + 1)
        for (i in energy.indices) sums[i + 1] = sums[i] + energy[i]
        val y =
            DoubleArray(energy.size) { i ->
                val lo = max(0, i - 22)
                val hi = min(energy.size, i + 23)
                (sums[hi] - sums[lo]) / (hi - lo)
            }
        fun avg(lo: Int, hi: Int): Double {
            var s = 0.0
            for (i in lo until hi) s += y[i]
            return s / max(1, hi - lo)
        }
        val candidates = ArrayList<Pair<Int, Double>>()
        for (cue in max(start + 87, end - 1379)..end - 151 step 11) {
            val before = avg(cue - 87, cue)
            val variation = abs(avg(cue - 87, cue - 44) - avg(cue - 44, cue))
            val fall = before - avg(max(cue + 1, end - 33), end)
            val n = end - cue
            val early = before - avg(cue, max(cue + 1, cue + (n * .3).roundToInt()))
            if (variation > 2.8 || fall < 9 || early < 1.4) continue
            var sx = 0.0
            var sy = 0.0
            var xx = 0.0
            var xy = 0.0
            for (i in cue until end) {
                val x = (i - cue) / FPS
                sx += x
                sy += y[i]
                xx += x * x
                xy += x * y[i]
            }
            val denominator = n * xx - sx * sx
            if (abs(denominator) <= 1e-12) continue
            val slope = (n * xy - sx * sy) / denominator
            val intercept = (sy - sx * slope) / n
            val mean = sy / n
            var total = 0.0
            var residual = 0.0
            for (i in cue until end) {
                total += (y[i] - mean).pow(2)
                residual += (y[i] - (intercept + slope * (i - cue) / FPS)).pow(2)
            }
            val fit = if (total <= 1e-12) 0.0 else unit(1 - residual / total)
            var comparisons = 0
            var descending = 0
            var previous = cue
            for (i in cue + 22 until end step 22) {
                if (y[i] <= y[previous] + .85) descending++
                comparisons++
                previous = i
            }
            val consistency = if (comparisons == 0) 0.0 else descending.toDouble() / comparisons
            if (slope <= -.38 && fit >= .56 && consistency >= .68) {
                val density = (cue until end).count { onset[it] >= .35f }.toDouble() / n
                val score =
                    min(n / FPS, 32.0) / 50 + min(fall, 30.0) / 12 + consistency * 2 + fit * 4 -
                        variation * .25 -
                        min(density, 1.0) * .45
                candidates.add(cue to score)
            }
        }
        val best = candidates.maxOfOrNull { it.second } ?: return null
        return candidates.firstOrNull { it.second >= best - .35 }?.first
    }

    companion object {
        private const val FPS = 43.06640625
    }
}
