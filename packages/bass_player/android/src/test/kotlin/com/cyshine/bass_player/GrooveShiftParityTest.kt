package com.cyshine.bass_player

import java.util.zip.GZIPInputStream
import kotlin.math.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/** Compares production code against original-DEX outputs, including complete envelopes. */
class GrooveShiftParityTest {
    private val corpus by lazy {
        JSONObject(
            GZIPInputStream(javaClass.getResourceAsStream("/groove-shift-reference.json.gz")!!)
                .bufferedReader()
                .readText()
        )
    }

    private fun range(x: JSONObject) = MixRange(x.getLong("startMs"), x.getLong("endMs"))

    private fun region(x: JSONObject) =
        MixRegion(
            range(x.getJSONObject("range")),
            x.getDouble("averageEnergyDbfs"),
            x.getDouble("onsetDensity"),
            x.getDouble("boundaryConfidence"),
        )

    private fun spectrum(x: JSONObject) =
        MixSpectrum(
            x.getDouble("lowEnergyDbfs"),
            x.getDouble("midEnergyDbfs"),
            x.getDouble("highEnergyDbfs"),
            x.getDouble("lowEnergyShare"),
        )

    private fun profile(x: JSONObject): MixProfile {
        val t = x.getJSONObject("track")
        val arr = x.getJSONObject("arrangement")
        val tempo =
            if (t.isNull("tempo")) null
            else
                t.getJSONObject("tempo").let { q ->
                    MixTempo(
                        q.getDouble("bpm"),
                        q.getJSONArray("beatTimesMs").let { v ->
                            (0 until v.length()).map { v.getLong(it) }
                        },
                        q.getInt("downbeatOffset"),
                        q.getDouble("beatConfidence"),
                        q.getDouble("downbeatConfidence"),
                        q.getDouble("stability"),
                    )
                }
        return MixProfile(
            t.getLong("durationMs"),
            range(t.getJSONObject("audibleRange")),
            t.getDouble("integratedRmsDbfs"),
            t.getDouble("peakDbfs"),
            tempo,
            region(t.getJSONObject("entrance")),
            region(t.getJSONObject("exit")),
            spectrum(arr.getJSONObject("entrance")),
            spectrum(arr.getJSONObject("exit")),
        )
    }

    private fun near(label: String, a: Double, b: Double, tolerance: Double = 1e-10) {
        assertEquals(label, a, b, tolerance)
    }

    private fun gain(label: String, expected: JSONObject, actual: List<GainNode>) {
        val ps = expected.getJSONArray("points")
        assertEquals("$label gain count", ps.length(), actual.size)
        for (i in actual.indices) {
            val e = ps.getJSONObject(i)
            val a = actual[i]
            near("$label gain[$i].p", e.getDouble("progress"), a.p)
            near("$label gain[$i].out", e.getDouble("outgoingGain"), a.outgoing)
            near("$label gain[$i].in", e.getDouble("incomingGain"), a.incoming)
        }
    }

    @Test
    fun fullPlannerAndExecutionCorpus() {
        val cases = corpus.getJSONArray("cases")
        val failures = ArrayList<String>()
        for (i in 0 until cases.length()) {
            val c = cases.getJSONObject(i)
            val name = c.getString("name")
            try {
                val input = c.getJSONObject("input")
                val a = profile(input.getJSONObject("outgoing"))
                val b = profile(input.getJSONObject("incoming"))
                val output = c.getJSONObject("output")
                val expected = output.getJSONObject("plan")
                val plan =
                    GrooveShiftPlanner.plan(
                        a,
                        b,
                        input.getLong("currentPositionMs"),
                        input.getInt("capabilityMask"),
                        input.getBoolean("gaplessForcedForExperiment"),
                    )
                assertEquals(name, expected.getString("mode"), plan.mode)
                assertEquals(name, output.getString("style"), plan.style)
                near(name, expected.getJSONObject("confidence").getDouble("score"), plan.confidence)
                assertEquals(name, expected.getLong("outgoingCueMs"), plan.outgoingCue)
                assertEquals(name, expected.getLong("incomingCueMs"), plan.incomingCue)
                assertEquals(name, expected.getLong("durationMs"), plan.duration)
                near(name, expected.getDouble("outgoingPlaybackRate"), plan.outgoingRate)
                near(name, expected.getDouble("incomingPlaybackRate"), plan.incomingRate)
                gain(name, expected.getJSONObject("gainCurve"), plan.gain)
                val envelopes = output.getJSONArray("parameterEnvelopes")
                assertEquals("$name effects count", envelopes.length(), plan.effects.size)
                for (j in plan.effects.indices) {
                    val e = envelopes.getJSONObject(j)
                    val actual = plan.effects[j]
                    assertEquals(name, e.getString("target") == "INCOMING", actual.incoming)
                    assertEquals(name, e.getString("parameterCode"), actual.parameter)
                    val ps = e.getJSONArray("points")
                    assertEquals(name, ps.length(), actual.nodes.size)
                    for (k in actual.nodes.indices) {
                        near(
                            "$name effect[$j][$k].p",
                            ps.getJSONObject(k).getDouble("progress"),
                            actual.nodes[k].p,
                        )
                        near(
                            "$name effect[$j][$k].v",
                            ps.getJSONObject(k).getDouble("value"),
                            actual.nodes[k].value,
                        )
                    }
                }
                val events = output.getJSONArray("events")
                assertEquals("$name events count", events.length(), plan.events.size)
                for (j in plan.events.indices) {
                    assertEquals(
                        name,
                        events.getJSONObject(j).getString("code"),
                        plan.events[j].name,
                    )
                    near(name, events.getJSONObject(j).getDouble("progress"), plan.events[j].p)
                }
                if (!c.isNull("executionGain"))
                    gain(
                        name,
                        c.getJSONObject("executionGain"),
                        GrooveShiftPlanner.executionGain(plan, a, b),
                    )
            } catch (e: Throwable) {
                failures.add("$name: ${e.message}")
            }
        }
        assertTrue(
            "${failures.size}/${cases.length()} failures:\n" + failures.take(30).joinToString("\n"),
            failures.isEmpty(),
        )
    }

    @Test
    fun scaledExecutionGains() {
        val cases = corpus.getJSONArray("cases")
        val reference =
            (0 until cases.length())
                .map { cases.getJSONObject(it) }
                .first { it.getString("name") == "strong_caps_63" }
        val input = reference.getJSONObject("input")
        val a = profile(input.getJSONObject("outgoing"))
        val b = profile(input.getJSONObject("incoming"))
        val plan = GrooveShiftPlanner.plan(a, b, 0)
        val scaled = corpus.getJSONArray("scaledGains")
        for (i in 0 until scaled.length()) {
            val expected = scaled.getJSONObject(i)
            val scale = expected.getDouble("scale")
            gain("scale=$scale", expected, GrooveShiftPlanner.executionGain(plan, a, b, 1.0, scale))
        }
        assertEquals(7, scaled.length())
    }

    @Test
    fun originalSyntheticAnalysisCorpus() {
        val analyses = corpus.getJSONArray("analyses")
        val failures = ArrayList<String>()
        for (i in 0 until analyses.length()) {
            val entry = analyses.getJSONObject(i)
            val name = entry.getString("name")
            val expected = profile(entry.getJSONObject("output"))
            val sr =
                if (name.startsWith("sr")) name.substring(2).toInt()
                else if (name == "stereo" || name == "antiphase") 44100 else 11025
            val channels = if (name == "stereo" || name == "antiphase") 2 else 1
            val seconds =
                if (name.startsWith("bpm")) 36
                else if (name.startsWith("sr") || channels == 2) 18 else 60
            val bpm = if (name.startsWith("bpm")) name.substring(3).toDouble() else 120.0
            val analyzer = GrooveShiftAnalyzer(sr, channels)
            val pcm = FloatArray(16384 - 16384 % channels)
            val total = sr * seconds * channels
            var pos = 0
            while (pos < total) {
                val count = min(pcm.size, total - pos)
                for (j in 0 until count) {
                    val t = ((pos + j) / channels).toDouble() / sr
                    val audible = t - 2
                    val phase = audible % (60 / bpm)
                    var sample = 0.0
                    if (t >= 2 && t < seconds - 2 && name != "silence") {
                        sample =
                            if (name == "tone") .15 * sin(2 * PI * 440 * t)
                            else
                                .012 * sin(2 * PI * 440 * t) +
                                    .55 * sin(2 * PI * 75 * phase) * exp(-phase * 55)
                        if (name == "fade" && t > seconds - 16)
                            sample *= 10.0.pow(-(t - (seconds - 16)) * 2 / 20)
                    }
                    pcm[j] =
                        (sample * if (name == "antiphase" && (pos + j) % channels == 1) -1 else 1)
                            .toFloat()
                }
                analyzer.accept(pcm, count)
                pos += count
            }
            val actual = analyzer.finish()
            try {
                assertEquals(name, expected.duration, actual.duration)
                assertEquals(name, expected.audible, actual.audible)
                near(name, expected.rms, actual.rms, 1e-7)
                near(name, expected.peak, actual.peak, 1e-7)
                if (expected.tempo == null) assertNull(name, actual.tempo)
                else {
                    val at = actual.tempo!!
                    val et = expected.tempo
                    near("$name bpm", et.bpm, at.bpm)
                    near("$name confidence", et.confidence, at.confidence, 1e-6)
                    near("$name downbeat", et.downbeat, at.downbeat, 1e-6)
                    near("$name stability", et.stability, at.stability, 1e-6)
                    assertEquals(name, et.beats, at.beats)
                    assertEquals(name, et.offset, at.offset)
                }
                for ((e, a) in
                    listOf(expected.intro to actual.intro, expected.outro to actual.outro)) {
                    assertEquals(name, e.range, a.range)
                    near("$name rms", e.rms, a.rms, 1e-6)
                    near("$name density", e.density, a.density, 1e-6)
                    near("$name boundary", e.confidence, a.confidence, 1e-6)
                }
                for ((e, a) in
                    listOf(
                        expected.introSpectrum to actual.introSpectrum,
                        expected.outroSpectrum to actual.outroSpectrum,
                    )) {
                    near(name, e.low, a.low, 1e-6)
                    near(name, e.mid, a.mid, 1e-6)
                    near(name, e.high, a.high, 1e-6)
                    near(name, e.lowShare, a.lowShare, 1e-6)
                }
            } catch (e: Throwable) {
                failures.add("$name: ${e.message}")
            }
        }
        assertTrue(
            "${failures.size}/${analyses.length()} failures:\n" + failures.joinToString("\n"),
            failures.isEmpty(),
        )
    }
}
