package com.cyshine.bass_player

import kotlin.math.*

/** Pure envelopes and structural events; all positions use normalized mixer time. */
internal object GrooveShiftArrangement {
    private fun g(vararg x: Double) = x.toList().chunked(3).map { GainNode(it[0], it[1], it[2]) }

    private fun e(incoming: Boolean, name: String, vararg x: Double) =
        MixEffect(incoming, name, x.toList().chunked(2).map { EffectNode(it[0], it[1]) })

    private fun echo(name: String, value: Double) = e(false, name, 0.0, value, 1.0, value)

    private fun blend(d: Double) =
        g(
            0.0,
            1.0,
            0.0,
            d * .42,
            .92,
            .08,
            d - .06,
            .78,
            .22,
            d,
            .5,
            .5,
            d + .06,
            .22,
            .78,
            (1 - d - .06) * .55 + d + .06,
            .08,
            .92,
            1.0,
            0.0,
            1.0,
        )

    fun fade(p: MixPlan, delta: Double, density: Double, spectral: Boolean) {
        p.style = if (spectral) "SPECTRAL_HANDOFF" else "TRANSPARENT_BLEND"
        val d = .64 + delta * .1
        val width =
            ((6000 - density * 2500 + delta * 500).coerceIn(3000.0, 6000.0) / p.duration).coerceIn(
                .12,
                d - .08,
            )
        val start = d - width
        val restart = d - (900.0 / p.duration).coerceIn(.025, width * .28)
        val middle = start + (restart - start) * .62
        val after = d + (1 - d) * .18
        val end = d + (1 - d) * .52
        p.gain =
            g(
                0.0,
                1.0,
                0.0,
                start,
                1.0,
                0.0,
                middle,
                .82,
                .18,
                restart,
                .92,
                .08,
                d,
                .24,
                .76,
                after,
                .08,
                .92,
                end,
                0.0,
                1.0,
                1.0,
                0.0,
                1.0,
            )
        if (spectral) {
            val cutoff = 3200 + delta * 1600
            val low = -8 + delta * 2.5
            p.effects =
                listOf(
                    e(
                        true,
                        "low_pass_cutoff_hz",
                        0.0,
                        cutoff,
                        start,
                        cutoff,
                        middle,
                        4200 + delta * 2500,
                        restart,
                        cutoff,
                        d,
                        18000.0,
                        1.0,
                        18000.0,
                    ),
                    e(
                        true,
                        "low_shelf_gain_db",
                        0.0,
                        low,
                        restart,
                        low,
                        d,
                        0.0,
                        after,
                        0.0,
                        end,
                        0.0,
                        1.0,
                        0.0,
                    ),
                    e(
                        false,
                        "low_shelf_gain_db",
                        0.0,
                        0.0,
                        restart,
                        0.0,
                        d,
                        -4.0,
                        end,
                        -8.0,
                        1.0,
                        -8.0,
                    ),
                )
            p.events = listOf(MixEvent("musical_handoff", d))
        }
    }

    fun arrange(p: MixPlan, a: MixProfile, b: MixProfile, mask: Int, qualified: Boolean) {
        val beat = 60000 / (b.tempo?.bpm ?: 120.0)
        val d = if (b.intro.density >= .24) .5 else .56
        val share = min(a.outroSpectrum.lowShare, b.introSpectrum.lowShare)
        val boost = 3.5 + unit((share - .08) / .37) * 2.5
        when (p.style) {
            "STRUCTURAL_RECOMPOSITION" -> {
                val n = floor(p.duration / beat + .02).toInt()
                val long = n >= 32
                val repeats =
                    if (long) listOf(4.0, 2.0, 1.0, .5, .25) else listOf(2.0, 1.0, .5, .25)
                val volumes =
                    if (long) listOf(1.0, 1.0, 1.0, .98, .94) else listOf(1.0, 1.0, .98, .94)
                val dropBeat = min(if (long) 24.0 else 12.0, (n - if (long) 8 else 4).toDouble())
                val startBeat = dropBeat - repeats.sum()
                val bp = beat / p.duration
                val drop = dropBeat * bp
                val restart = drop - (18.0 / p.duration).coerceIn(.001, bp * .08)
                val after = drop + .1 * bp
                val end = drop + .72 * bp
                val events = mutableListOf<MixEvent>()
                val gain = mutableListOf(GainNode(0.0, 1.0, 0.0))
                if (startBeat >= 2) {
                    gain.add(GainNode(min(.75, .3 * startBeat) * bp, .8, .2))
                    gain.add(GainNode(startBeat * .55 * bp, .64, .36))
                    gain.add(GainNode(startBeat * .85 * bp, .84, .16))
                }
                var cursor = startBeat
                for ((i, r) in repeats.withIndex()) {
                    val name =
                        when (r) {
                            4.0 -> "four_beat"
                            2.0 -> "two_beat"
                            1.0 -> "beat"
                            .5 -> "half_beat"
                            else -> "quarter_beat"
                        }
                    events.add(MixEvent("outgoing_" + name + "_repeat", cursor * bp))
                    gain.add(GainNode(cursor * bp, volumes[i], 0.0))
                    cursor += r
                }
                gain.addAll(
                    g(
                        restart,
                        .98,
                        0.0,
                        drop,
                        .04,
                        .92,
                        after,
                        .02,
                        .98,
                        end,
                        0.0,
                        1.0,
                        1.0,
                        0.0,
                        1.0,
                    )
                )
                p.gain = gain
                val first = events.first().p
                val last = events.last().p
                p.effects =
                    listOf(
                        e(
                            false,
                            "low_shelf_gain_db",
                            0.0,
                            0.0,
                            first,
                            0.0,
                            last,
                            boost * .72,
                            drop,
                            -15.0,
                            1.0,
                            -15.0,
                        ),
                        e(
                            true,
                            "low_shelf_gain_db",
                            0.0,
                            -12.9,
                            restart,
                            -12.9,
                            drop,
                            boost,
                            after,
                            boost,
                            end,
                            0.0,
                            1.0,
                            0.0,
                        ),
                        e(
                            false,
                            "low_pass_cutoff_hz",
                            0.0,
                            18000.0,
                            first,
                            18000.0,
                            last,
                            4200.0,
                            drop,
                            900.0,
                            1.0,
                            900.0,
                        ),
                        e(
                            true,
                            "low_pass_cutoff_hz",
                            0.0,
                            1800.0,
                            restart,
                            1800.0,
                            drop,
                            18000.0,
                            1.0,
                            18000.0,
                        ),
                        e(false, "echo_wet", 0.0, 0.0, restart, 0.0, drop, .36, end, 0.0, 1.0, 0.0),
                        echo("echo_feedback", .34),
                        echo("echo_delay_ms", beat * .25),
                    )
                p.events =
                    events +
                        listOf(
                            MixEvent("incoming_cue_restart", restart),
                            MixEvent("performance_drop", drop),
                        )
            }
            "PERFORMANCE_HANDOFF" -> {
                val drop = if (b.intro.density >= .24) .5 else .56
                val bp = (beat / p.duration).coerceIn(.035, .1)
                val start = max(.12, drop - 2 * bp)
                val before = max(start + .01, drop - bp * .22)
                val after = min(.82, drop + bp * .24)
                val end = min(.9, drop + bp * .72)
                val echoEnd = min(.94, drop + bp)
                p.gain =
                    g(
                        0.0,
                        1.0,
                        0.0,
                        start,
                        .96,
                        .04,
                        before,
                        .58,
                        .16,
                        drop,
                        .08,
                        .48,
                        after,
                        .04,
                        .68,
                        end,
                        .02,
                        .98,
                        1.0,
                        0.0,
                        1.0,
                    )
                p.effects =
                    listOf(
                        e(
                            false,
                            "low_shelf_gain_db",
                            0.0,
                            0.0,
                            start,
                            0.0,
                            before,
                            boost * .72,
                            drop,
                            -12.9,
                            1.0,
                            -12.9,
                        ),
                        e(
                            true,
                            "low_shelf_gain_db",
                            0.0,
                            -12.9,
                            before,
                            -12.9,
                            drop,
                            boost,
                            after,
                            boost * .58,
                            end,
                            0.0,
                            1.0,
                            0.0,
                        ),
                        e(
                            false,
                            "low_pass_cutoff_hz",
                            0.0,
                            18000.0,
                            start,
                            18000.0,
                            before,
                            4800.0,
                            drop,
                            850.0,
                            1.0,
                            850.0,
                        ),
                        e(
                            true,
                            "low_pass_cutoff_hz",
                            0.0,
                            1600.0,
                            before,
                            1600.0,
                            drop,
                            18000.0,
                            1.0,
                            18000.0,
                        ),
                        e(
                            false,
                            "echo_wet",
                            0.0,
                            0.0,
                            before,
                            0.0,
                            drop,
                            min(.34, .22 + unit((share - .08) / .37) * .12),
                            echoEnd,
                            0.0,
                            1.0,
                            0.0,
                        ),
                        echo("echo_feedback", .32),
                        echo("echo_delay_ms", beat * .5),
                    )
                p.events = listOf(MixEvent("performance_drop", drop))
            }
            "SPECTRAL_HANDOFF" -> {
                if (!qualified && mask and 4 != 0) {
                    val handoff = if (b.intro.density >= .24) .56 else .64
                    val low = -(unit(share) * 4 + 10)
                    val outLow = max(-15.0, low - 2)
                    val before = handoff * .64
                    val end = handoff + .12
                    p.gain = blend(handoff)
                    p.effects =
                        listOf(
                            e(
                                true,
                                "low_pass_cutoff_hz",
                                0.0,
                                2400.0,
                                .18,
                                2400.0,
                                before,
                                7200.0,
                                handoff,
                                18000.0,
                                1.0,
                                18000.0,
                            ),
                            e(
                                true,
                                "low_shelf_gain_db",
                                0.0,
                                low,
                                before,
                                low,
                                handoff,
                                0.0,
                                1.0,
                                0.0,
                            ),
                            e(
                                false,
                                "low_shelf_gain_db",
                                0.0,
                                0.0,
                                handoff,
                                0.0,
                                min(end, .82),
                                outLow,
                                1.0,
                                outLow,
                            ),
                            e(
                                false,
                                "low_pass_cutoff_hz",
                                0.0,
                                18000.0,
                                max(handoff, .58),
                                18000.0,
                                .82,
                                5200.0,
                                1.0,
                                1600.0,
                            ),
                        )
                    p.events = listOf(MixEvent("musical_handoff", handoff))
                } else {
                    val low = -(6 * unit((share - .08) / .92) + 9)
                    val width = (60.0 / p.duration).coerceIn(.006, .035)
                    p.gain = blend(d)
                    p.effects =
                        listOf(
                            e(
                                false,
                                "low_shelf_gain_db",
                                0.0,
                                0.0,
                                d,
                                0.0,
                                d + width,
                                low,
                                1.0,
                                low,
                            ),
                            e(true, "low_shelf_gain_db", 0.0, low, d - width, low, d, 0.0, 1.0, 0.0),
                        )
                    p.events = listOf(MixEvent("musical_handoff", d))
                }
            }
            "BREATH_DROP" -> {
                val width = (beat * .25 / p.duration).coerceIn(.035, .1)
                val before = .5 - width
                val after = .5 + width
                p.gain =
                    g(
                        0.0,
                        1.0,
                        0.0,
                        before * .7,
                        .82,
                        .08,
                        before,
                        .42,
                        .04,
                        .5,
                        .04,
                        .04,
                        after,
                        .04,
                        .42,
                        (1 - after) * .35 + after,
                        .08,
                        .82,
                        1.0,
                        0.0,
                        1.0,
                    )
                p.events = listOf(MixEvent("breath_drop", .5))
            }
            "ECHO_RELEASE" -> {
                p.gain = blend(.56)
                p.effects =
                    listOf(
                        e(
                            false,
                            "echo_wet",
                            0.0,
                            0.0,
                            .55,
                            0.0,
                            .56,
                            .12,
                            (beat / p.duration + .56).coerceIn(.5700000000000001, .92),
                            0.0,
                            1.0,
                            0.0,
                        ),
                        echo("echo_feedback", .24),
                        echo("echo_delay_ms", beat * .5),
                    )
                p.events = listOf(MixEvent("echo_release", .56))
            }
        }
    }
}
