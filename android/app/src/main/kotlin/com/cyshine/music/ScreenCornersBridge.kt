package com.cyshine.music

import android.app.Activity
import android.graphics.Path
import android.graphics.Point
import android.graphics.RectF
import android.os.Build
import android.view.View
import android.view.ViewTreeObserver
import androidx.annotation.DoNotInline
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlin.math.*

/** Window pixels, not dp. Never queried by the animation's frame loop. */
class ScreenCornersBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "cy_shine_music/screen_corners")
    private val view get() = activity.window.decorView
    private var lastKey: List<Any?>? = null
    private var listening = false
    private val layoutListener = ViewTreeObserver.OnGlobalLayoutListener { refresh() }

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "get") {
                result.notImplemented()
            } else {
                listening = true
                result.success(read())
            }
        }
        view.viewTreeObserver.addOnGlobalLayoutListener(layoutListener)
    }

    fun refresh() {
        if (!listening) return
        val display = view.display ?: return
        val key = listOf(
            view.width, view.height, display.displayId, display.rotation,
            display.mode.modeId, activity.resources.configuration.toString(),
            Build.VERSION.SDK_INT >= 24 && activity.isInMultiWindowMode,
            *Array(4) { cornerRadius(it) },
        )
        if (key == lastKey) return
        lastKey = key
        channel.invokeMethod("changed", null)
    }

    fun dispose() {
        view.viewTreeObserver.removeOnGlobalLayoutListener(layoutListener)
        channel.setMethodCallHandler(null)
    }

    private fun cornerRadius(index: Int): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        Api31Impl.cornerRadius(view, index)
    } else 0

    // Keep RoundedCorner out of the bridge's signatures and arrays: resolving
    // that type on Android 11 or earlier can fail before the SDK check runs.
    @RequiresApi(Build.VERSION_CODES.S)
    private object Api31Impl {
        @DoNotInline
        fun cornerRadius(view: View, index: Int): Int =
            view.rootWindowInsets?.getRoundedCorner(index)?.radius ?: 0
    }

    @Suppress("DEPRECATION")
    private fun read(): Map<String, Any> {
        val display = view.display
        val size = Point().also { display?.getRealSize(it) }
        val fullScreen = display != null && view.width == size.x && view.height == size.y &&
            !(Build.VERSION.SDK_INT >= 24 && activity.isInMultiWindowMode)
        val radii = FloatArray(4)
        val sources = Array(4) { "none" }
        if (fullScreen) {
            val fallback = if (display!!.displayId == 0) fallbackRadii() else FloatArray(4)
            for (i in 0..3) {
                val radius = cornerRadius(i).toFloat()
                radii[i] = if (radius > 0) radius else fallback[i]
                sources[i] = if (radius > 0) "insets" else if (fallback[i] > 0) "fallback" else "none"
                // Reject malformed OEM metadata, rather than cutting out half the screen.
                if (!radii[i].isFinite() || radii[i] !in 0f..(min(size.x, size.y) / 2f)) radii[i] = 0f
            }
        }
        val profile = if (display?.displayId == 0 && radii.any { it > 0 }) curve else null
        return mapOf(
            "width" to view.width, "height" to view.height,
            "radii" to radii.toList(), "sources" to sources.toList(),
            "curve" to (profile?.points ?: emptyList<Float>()),
            "scale" to (profile?.scale ?: 1f), "profile" to (profile?.name ?: "circular"),
        )
    }

    private fun fallbackRadii(): FloatArray {
        val display = view.display ?: return FloatArray(4)
        val stable = display.supportedModes.maxOf { min(it.physicalWidth, it.physicalHeight) }
        val size = Point().also { @Suppress("DEPRECATION") display.getRealSize(it) }
        val scale = if (stable > 0) min(size.x, size.y).toFloat() / stable else 1f
        if (isBrand("oppo", "oneplus", "realme")) {
            val secondary = property("ro.oplus.display.secondary.rc.size")
            val folded = activity.resources.configuration.smallestScreenWidthDp < 600
            val raw = if (secondary.isNotBlank() &&
                property("ro.oplus.fold.type").isNotBlank() && folded
            ) secondary else property("ro.oplus.display.rc.size")
            val radius = raw.split(',').mapNotNull { it.trim().toFloatOrNull() }
                .filter { it.isFinite() && it > 0 }.minOrNull()
            if (radius != null) {
                // Map physical panel pixels into the current logical display (also handles wm size).
                return FloatArray(4) { radius * scale }
            }
        }
        fun dimension(name: String): Float? = runCatching {
            val resources = activity.resources
            val id = resources.getIdentifier(name, "dimen", "android")
            if (id == 0) null else resources.getDimensionPixelSize(id).toFloat()
        }.getOrNull()
        val common = dimension("rounded_corner_radius") ?: 0f
        val top = dimension("rounded_corner_radius_top") ?: common
        val bottom = dimension("rounded_corner_radius_bottom") ?: common
        val natural = floatArrayOf(top, top, bottom, bottom)
        // Resource names refer to the natural display orientation; Insets are already rotated.
        return FloatArray(4) { natural[(it + display.rotation) % 4] * scale }
    }

    private data class Curve(val name: String, val points: List<Float>, val scale: Float = 1f)

    // Templates use a 100 px corner, converted to radius units once per Activity.
    // Path.approximate's error is <= 0.025 px at this reference size.
    private val curve: Curve? by lazy {
        runCatching {
            when {
                isBrand("oppo", "oneplus", "realme") -> oplusCurve()
                isBrand("xiaomi", "redmi", "poco") -> hyperOsCurve()
                else -> null
            }
        }.getOrNull()
    }

    private fun sample(name: String, path: Path, scale: Float = 1f): Curve? {
        if (Build.VERSION.SDK_INT < 26 || path.isEmpty) return null
        val points = path.approximate(0.025f).asList().chunked(3)
            .map { PointFPair(it[1], it[2]) }
            // Top-right corner of the 1000 x 1000 reference rectangle.
            .filter { it.x >= 500f && it.y <= 500f }
            .distinct().sortedBy { it.x + it.y }
        val first = points.indexOfFirst { it.y > 0.001f }
        val last = points.indexOfLast { it.x < 999.999f }
        if (first < 1 || last < first || last + 1 >= points.size) return null
        val trimmed = points.subList(first - 1, last + 2)
        val normalized = trimmed.flatMap { listOf((1000f - it.x) / 100f, it.y / 100f) }
        if (normalized.any { !it.isFinite() || it < 0f || it > 4f }) return null
        return Curve(name, normalized, scale)
    }

    private data class PointFPair(val x: Float, val y: Float)

    private fun oplusCurve(): Curve? {
        val manager = Class.forName("com.oplus.view.OplusSmoothRoundedManager")
        if (manager.getMethod("isSmoothRadiusOn").invoke(null) != true) return null
        val sdk = Class.forName("com.oplus.os.OplusBuild\$VERSION").getField("SDK_VERSION").getInt(null)
        if (sdk < 35) return null
        if (sdk >= 38) runCatching {
            // Confirm the new platform capability before using its G2 contour.
            Class.forName("com.oplus.graphics.OplusPathAdapter")
            sample("oplus-v2", g2Path(), 1.25f)
        }.getOrNull()?.let { return it }
        val weight = runCatching {
            (manager.getMethod("getNonWight").invoke(null) as Number).toFloat() - 0.001f
        }.getOrDefault(1.999f)
        val path = Path()
        val type = Class.forName("com.oplus.graphics.OplusPath")
        val wrapper = type.getConstructor(Path::class.java).newInstance(path)
        type.getMethod("addSmoothRoundRect", RectF::class.java, FloatArray::class.java,
            Path.Direction::class.java, Float::class.javaPrimitiveType)
            .invoke(wrapper, RectF(0f, 0f, 1000f, 1000f), FloatArray(8) { 100f }, Path.Direction.CW, weight)
        return sample("oplus-v1", path)
    }

    private fun hyperOsCurve(): Curve? {
        val enabled = property("persist.sys.support_view_smoothcorner").lowercase()
        if (enabled in listOf("0", "false", "no", "n", "off")) return null
        if (enabled !in listOf("1", "true", "yes", "y", "on") && Build.VERSION.SDK_INT < 31) {
            View::class.java.getDeclaredMethod("setSmoothCornerEnabled", Boolean::class.javaPrimitiveType)
        }
        val angle = 0.8 * PI / 4
        val tangent = tan(angle / 2)
        val a = 1 - tangent
        val b = 1.5 * tangent / (cos(angle) + 1)
        val c = (((cos(angle) + 1) * (0.8 * 0.46 * 0.46 + tangent) * 2 / (tangent * 3)) - 1) * b
        fun x(v: Double) = (1000 - v * 100).toFloat()
        fun y(v: Double) = (v * 100).toFloat()
        val path = Path().apply {
            moveTo(500f, 0f)
            lineTo(x(a + b + c), 0f)
            cubicTo(x(a + b), 0f, x(a), 0f, x(1 - sin(angle)), y(1 - cos(angle)))
            arcTo(RectF(800f, 0f, 1000f, 200f), (-90 + angle * 180 / PI).toFloat(),
                (90 - 2 * angle * 180 / PI).toFloat())
            cubicTo(1000f, y(a), 1000f, y(a + b), 1000f, y(a + b + c))
            lineTo(1000f, 500f)
        }
        return sample("hyperos", path)
    }

    private fun g2Path(): Path {
        // Half a quadrant, reflected about x=y to retain tangent continuity.
        val half = doubleArrayOf(
            .027057233033, 1.0, .060904480594, 1.0, .096697984928, .999324675426,
            .128137266906, .998731503003, .160475113513, .997628693112, .193395969855, .995597790810,
            .225176535438, .993637233553, .257499829589, .990811800280, .290093954783, .986744492391,
            .322014182488, .982761277834, .354356111961, .977566800687, .386791939710, .970780536387,
            .418772061073, .964089615546, .451152244071, .955786716884, .483489924638, .945445165510,
            .515483185544, .935213759129, .547931267536, .922828139554, .580187909565, .907757304632,
            .612244340247, .892780011752, .644807093392, .874825834175, .676885894493, .853182554598,
            .712968952723, .828837638627, .745067242961, .802100515880, .773583879421, .773583879421,
        )
        return Path().apply {
            moveTo(500f, 0f)
            lineTo(900f, 0f)
            fun segment(x1: Double, y1: Double, x2: Double, y2: Double, x3: Double, y3: Double) {
                cubicTo((900 + x1 * 100).toFloat(), (100 - y1 * 100).toFloat(),
                    (900 + x2 * 100).toFloat(), (100 - y2 * 100).toFloat(),
                    (900 + x3 * 100).toFloat(), (100 - y3 * 100).toFloat())
            }
            for (i in half.indices step 6) segment(half[i], half[i+1], half[i+2], half[i+3], half[i+4], half[i+5])
            for (i in half.size - 6 downTo 0 step 6) {
                segment(half[i+3], half[i+2], half[i+1], half[i],
                    if (i == 0) 1.0 else half[i-1], if (i == 0) 0.0 else half[i-2])
            }
            lineTo(1000f, 500f)
        }
    }

    private fun isBrand(vararg brands: String) = brands.any {
        it.equals(Build.BRAND, true) || it.equals(Build.MANUFACTURER, true)
    }

    private fun property(name: String): String = runCatching {
        Class.forName("android.os.SystemProperties").getMethod("get", String::class.java)
            .invoke(null, name) as String
    }.getOrDefault("")
}
