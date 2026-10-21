package com.cyshine.music

import android.graphics.Bitmap
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

/** Keeps the player's existing Dart colour rules on a decoded software bitmap. */
internal object ArtworkColorExtractor {
    private const val black = -0x1000000
    private val fallbackAccents = listOf(
        0xFF5B6B8C.toInt(), 0xFF8C5B72.toInt(),
        0xFF5B8C6B.toInt(), 0xFF8C7F5B.toInt(),
    )

    fun extract(bitmap: Bitmap): Map<String, Any?> {
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

        // getPixels returns straight ARGB, while Flutter rawRgba was premultiplied.
        // Recreate those bytes before applying the existing alpha weighting.
        for (index in pixels.indices) {
            val pixel = pixels[index]
            val alpha = pixel ushr 24
            if (alpha == 255) continue
            fun premultiply(channel: Int) = (channel * alpha + 127) / 255
            pixels[index] = (alpha shl 24) or
                (premultiply(red(pixel)) shl 16) or
                (premultiply(green(pixel)) shl 8) or premultiply(blue(pixel))
        }

        val palette = extractPalette(pixels, width, height)
        return mapOf(
            "baseArgb" to sampleBase(pixels, width, height),
            "paletteBaseArgb" to (palette?.baseArgb ?: 0xFF3A3A3C.toInt()),
            "accentsArgb" to (palette?.accentsArgb ?: fallbackAccents),
            "lyricInkArgb" to extractLyricInk(pixels),
            "hasPalette" to (palette != null),
        )
    }

    private fun sampleBase(pixels: IntArray, width: Int, height: Int): Int {
        if (width <= 0 || height <= 0) return black
        var red = 0
        var green = 0
        var blue = 0
        var count = 0
        for (row in 0 until 5) {
            val y = floor((row + 0.5) * height / 5).toInt().coerceIn(0, height - 1)
            for (column in 0 until 5) {
                val x = floor((column + 0.5) * width / 5).toInt().coerceIn(0, width - 1)
                val pixel = pixels[y * width + x]
                val alpha = pixel ushr 24
                red += red(pixel) * alpha / 255
                green += green(pixel) * alpha / 255
                blue += blue(pixel) * alpha / 255
                count++
            }
        }
        return pack(red / count, green / count, blue / count)
    }

    private fun extractPalette(pixels: IntArray, width: Int, height: Int): Palette? {
        val blocks = ArrayList<Hsl>(16)
        var totalRed = 0.0
        var totalGreen = 0.0
        var totalBlue = 0.0
        var totalWeight = 0.0
        for (blockY in 0 until 4) {
            for (blockX in 0 until 4) {
                val startX = blockX * width / 4
                val endX = max(startX + 1, (blockX + 1) * width / 4)
                val startY = blockY * height / 4
                val endY = max(startY + 1, (blockY + 1) * height / 4)
                val stepX = max(1, (endX - startX) / 6)
                val stepY = max(1, (endY - startY) / 6)
                var red = 0.0
                var green = 0.0
                var blue = 0.0
                var weight = 0.0
                var y = startY
                while (y < endY && y < height) {
                    var x = startX
                    while (x < endX && x < width) {
                        val pixel = pixels[y * width + x]
                        val alpha = (pixel ushr 24) / 255.0
                        if (alpha > 0) {
                            red += red(pixel) * alpha
                            green += green(pixel) * alpha
                            blue += blue(pixel) * alpha
                            weight += alpha
                        }
                        x += stepX
                    }
                    y += stepY
                }
                if (weight <= 0) continue
                totalRed += red
                totalGreen += green
                totalBlue += blue
                totalWeight += weight
                blocks.add(flowHsl(red / weight, green / weight, blue / weight))
            }
        }
        if (totalWeight <= 0 || blocks.isEmpty()) return null

        // Kotlin's list sort preserves the original block order for equal scores.
        val ranked = blocks.sortedByDescending(::flowScore)
        val picked = ArrayList<Hsl>(4)
        for (candidate in ranked) {
            if (picked.size >= 4) break
            if (picked.any {
                    hueDistance(it.hue, candidate.hue) < 25 &&
                        abs(it.lightness - candidate.lightness) < 0.14
                }
            ) continue
            picked.add(candidate)
        }
        if (picked.isEmpty()) picked.add(ranked.first())
        val seeds = picked.toList()
        var spin = 0
        while (picked.size < 4) {
            val seed = seeds[spin % seeds.size]
            val turn = 30.0 * (spin / seeds.size + 1)
            val signed = if (spin % 2 == 0) turn else -turn
            picked.add(
                Hsl(
                    positiveModulo(seed.hue + signed, 360.0),
                    seed.saturation,
                    (seed.lightness + if (spin % 2 == 0) 0.05 else -0.05).coerceIn(0.0, 1.0),
                ),
            )
            spin++
        }
        val accents = picked.map { hsl ->
            val saturation = if (hsl.saturation < 0.18) {
                0.18 + hsl.saturation * 0.9
            } else {
                min(1.0, hsl.saturation * 1.15)
            }
            flowArgb(Hsl(hsl.hue, saturation.coerceIn(0.0, 1.0), hsl.lightness.coerceIn(0.32, 0.68)))
        }
        return Palette(pack(totalRed / totalWeight, totalGreen / totalWeight, totalBlue / totalWeight), accents)
    }

    private fun extractLyricInk(pixels: IntArray): Int? {
        // Insertion order also preserves Dart's first-swatch tie behaviour.
        val buckets = LinkedHashMap<Int, Bucket>()
        for (pixel in pixels) {
            if ((pixel ushr 24) < 125) continue
            val red = red(pixel)
            val green = green(pixel)
            val blue = blue(pixel)
            val key = ((red shr 4) shl 8) or ((green shr 4) shl 4) or (blue shr 4)
            val bucket = buckets.getOrPut(key) { Bucket() }
            bucket.count++
            bucket.red += red
            bucket.green += green
            bucket.blue += blue
        }
        if (buckets.isEmpty()) return null
        val swatches = buckets.values.map { bucket ->
            Swatch(
                pack(
                    (bucket.red.toDouble() / bucket.count).roundToInt(),
                    (bucket.green.toDouble() / bucket.count).roundToInt(),
                    (bucket.blue.toDouble() / bucket.count).roundToInt(),
                ),
                bucket.count,
            )
        }
        val base = swatches.reduce { a, b -> if (a.count >= b.count) a else b }
        val maxCount = base.count
        var background = base
        val useful = swatches.filter { !it.extreme }
        if (background.extreme) {
            for (swatch in useful.filter { it.count >= maxCount / 2.5 }) {
                if (background.extreme || swatch.hsl.saturation > background.hsl.saturation) {
                    background = swatch
                }
            }
        }
        val luminance = luminance(background.color)
        if (luminance <= 0.5) return null
        val prominent = if (useful.isEmpty()) base else useful.reduce { a, b ->
            if (a.count >= b.count) a else b
        }

        fun pick(dark: Boolean, vibrant: Boolean): Swatch? {
            var result: Swatch? = null
            var best = -1.0
            val targetL = if (dark) 0.26 else 0.5
            val targetS = if (vibrant) 1.0 else 0.3
            for (swatch in swatches) {
                val hsl = swatch.hsl
                if (if (dark) hsl.lightness > 0.45 else hsl.lightness < 0.3 || hsl.lightness > 0.7) continue
                if (if (vibrant) hsl.saturation < 0.35 else hsl.saturation > 0.4) continue
                val score = 0.24 * swatch.count / maxCount +
                    0.52 * (1 - abs(hsl.lightness - targetL)) +
                    0.24 * (1 - abs(hsl.saturation - targetS))
                if (score > best) {
                    best = score
                    result = swatch
                }
            }
            return result
        }

        var selected = morePopulated(pick(true, true), pick(false, true))
            ?: morePopulated(pick(true, false), pick(false, false))
        if (selected == null) {
            val total = swatches.sumOf { it.count }
            selected = if (prominent.count.toDouble() / total >= 0.01) prominent else Swatch(black, 0)
        } else if (selected.count.toDouble() / prominent.count < 0.01 && prominent.hsl.saturation > 0.19) {
            selected = prominent
        }
        val chosen = selected.hsl
        val dominant = background.hsl
        val main = prominent.hsl
        val hue = when {
            chosen.saturation >= 0.18 -> chosen.hue
            main.saturation >= 0.15 -> main.hue
            dominant.saturation >= 0.1 -> dominant.hue
            else -> 225.0
        }
        val saturation = when {
            chosen.saturation >= 0.3 -> chosen.saturation
            main.saturation >= 0.3 -> main.saturation * 0.85
            dominant.saturation >= 0.15 -> dominant.saturation * 0.75
            else -> 0.3
        }.coerceIn(0.3, 0.6)
        for (step in 0..12) {
            val ink = lyricArgb(Hsl(hue, saturation, 0.3 - step * 0.015))
            val inkLuminance = luminance(ink)
            val contrast = (max(luminance, inkLuminance) + 0.05) /
                (min(luminance, inkLuminance) + 0.05)
            if (contrast >= 4.5 || step == 12) return ink
        }
        return null
    }

    private fun morePopulated(a: Swatch?, b: Swatch?): Swatch? = when {
        a == null -> b
        b == null || a.count >= b.count -> a
        else -> b
    }

    private fun flowHsl(red: Double, green: Double, blue: Double): Hsl {
        val r = red / 255
        val g = green / 255
        val b = blue / 255
        val maximum = max(r, max(g, b))
        val minimum = min(r, min(g, b))
        val lightness = (maximum + minimum) / 2
        val delta = maximum - minimum
        if (delta <= 0) return Hsl(0.0, 0.0, lightness)
        val saturation = if (lightness > 0.5) delta / (2 - maximum - minimum) else delta / (maximum + minimum)
        val hue = when (maximum) {
            r -> (g - b) / delta + if (g < b) 6 else 0
            g -> (b - r) / delta + 2
            else -> (r - g) / delta + 4
        }
        return Hsl(hue * 60, saturation, lightness)
    }

    private fun lyricHsl(color: Int): Hsl {
        val r = red(color) / 255.0
        val g = green(color) / 255.0
        val b = blue(color) / 255.0
        val maximum = max(r, max(g, b))
        val minimum = min(r, min(g, b))
        val delta = maximum - minimum
        val lightness = (maximum + minimum) / 2
        if (delta == 0.0) return Hsl(0.0, 0.0, lightness)
        val hue = when (maximum) {
            r -> 60 * positiveModulo((g - b) / delta, 6.0)
            g -> 60 * ((b - r) / delta + 2)
            else -> 60 * ((r - g) / delta + 4)
        }
        return Hsl(hue, (delta / (1 - abs(2 * lightness - 1))).coerceIn(0.0, 1.0), lightness)
    }

    private fun flowArgb(hsl: Hsl): Int {
        if (hsl.saturation <= 0) return pack(hsl.lightness * 255, hsl.lightness * 255, hsl.lightness * 255)
        val hue = positiveModulo(hsl.hue, 360.0) / 360
        val q = if (hsl.lightness < 0.5) hsl.lightness * (1 + hsl.saturation)
            else hsl.lightness + hsl.saturation - hsl.lightness * hsl.saturation
        val p = 2 * hsl.lightness - q
        return pack(hueToChannel(p, q, hue + 1.0 / 3) * 255, hueToChannel(p, q, hue) * 255, hueToChannel(p, q, hue - 1.0 / 3) * 255)
    }

    private fun lyricArgb(hsl: Hsl): Int {
        val chroma = (1 - abs(2 * hsl.lightness - 1)) * hsl.saturation
        val secondary = chroma * (1 - abs(positiveModulo(hsl.hue / 60, 2.0) - 1))
        val match = hsl.lightness - chroma / 2
        val (r, g, b) = when {
            hsl.hue < 60 -> Triple(chroma, secondary, 0.0)
            hsl.hue < 120 -> Triple(secondary, chroma, 0.0)
            hsl.hue < 180 -> Triple(0.0, chroma, secondary)
            hsl.hue < 240 -> Triple(0.0, secondary, chroma)
            hsl.hue < 300 -> Triple(secondary, 0.0, chroma)
            else -> Triple(chroma, 0.0, secondary)
        }
        return pack((r + match) * 255, (g + match) * 255, (b + match) * 255)
    }

    private fun hueToChannel(p: Double, q: Double, t: Double): Double {
        val offset = positiveModulo(t, 1.0)
        return when {
            offset < 1.0 / 6 -> p + (q - p) * 6 * offset
            offset < 1.0 / 2 -> q
            offset < 2.0 / 3 -> p + (q - p) * (2.0 / 3 - offset) * 6
            else -> p
        }
    }

    private fun flowScore(hsl: Hsl) = hsl.saturation * (1 - abs(hsl.lightness - 0.5) * 1.1) + hsl.saturation * 0.12
    private fun hueDistance(a: Double, b: Double): Double {
        val delta = abs(a - b) % 360
        return if (delta > 180) 360 - delta else delta
    }

    private fun luminance(color: Int): Double {
        fun linear(channel: Int): Double {
            val component = channel / 255.0
            return if (component <= 0.03928) component / 12.92 else ((component + 0.055) / 1.055).pow(2.4)
        }
        return 0.2126 * linear(red(color)) + 0.7152 * linear(green(color)) + 0.0722 * linear(blue(color))
    }

    private fun positiveModulo(value: Double, modulus: Double): Double {
        val result = value % modulus
        return if (result < 0) result + modulus else result
    }

    private fun red(color: Int) = (color ushr 16) and 255
    private fun green(color: Int) = (color ushr 8) and 255
    private fun blue(color: Int) = color and 255
    private fun pack(red: Double, green: Double, blue: Double) = pack(red.roundToInt(), green.roundToInt(), blue.roundToInt())
    private fun pack(red: Int, green: Int, blue: Int) = black or
        (red.coerceIn(0, 255) shl 16) or (green.coerceIn(0, 255) shl 8) or blue.coerceIn(0, 255)

    private data class Hsl(val hue: Double, val saturation: Double, val lightness: Double)
    private data class Palette(val baseArgb: Int, val accentsArgb: List<Int>)
    private data class Swatch(val color: Int, val count: Int) {
        val hsl = lyricHsl(color)
        val extreme get() = hsl.lightness < 0.08 || hsl.lightness > 0.9
    }
    private class Bucket {
        var count = 0
        var red = 0
        var green = 0
        var blue = 0
    }
}
