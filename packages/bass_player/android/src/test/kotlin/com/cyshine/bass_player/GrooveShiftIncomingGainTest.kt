package com.cyshine.bass_player

import kotlin.math.log10
import org.junit.Assert.*
import org.junit.Test

class GrooveShiftIncomingGainTest {
    @Test
    fun preservesSilenceAndFullVolume() {
        assertEquals(0.0, incomingMixGain(0.0), 0.0)
        assertEquals(1.0, incomingMixGain(1.0), 0.0)
    }

    @Test
    fun gentlyLiftsQuietEntryAndTapersTowardFullVolume() {
        val quietBoostDb = 20 * log10(incomingMixGain(.1) / .1)
        val middleBoostDb = 20 * log10(incomingMixGain(.5) / .5)
        val lateBoostDb = 20 * log10(incomingMixGain(.9) / .9)
        assertEquals(1.944, quietBoostDb, 1e-10)
        assertEquals(1.0, middleBoostDb, 1e-10)
        assertTrue(lateBoostDb < .1)
        var previous = 0.0
        for (i in 1..1000) {
            val input = i / 1000.0
            val output = incomingMixGain(input)
            assertTrue(output >= input && output <= 1.0)
            assertTrue(output >= previous)
            previous = output
        }
    }
}
