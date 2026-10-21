package com.cyshine.music

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** Decodes and samples covers without routing raw pixels through Flutter. */
class ArtworkColorsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var worker: ThreadPoolExecutor? = null
    private val requests = mutableSetOf<Extraction>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        worker = ThreadPoolExecutor(1, 1, 30, TimeUnit.SECONDS, LinkedBlockingQueue()) { task ->
            Thread({
                Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
                task.run()
            }, "ArtworkColors")
        }.apply { allowCoreThreadTimeOut(true) }
        channel = MethodChannel(binding.binaryMessenger, "cy_shine_music/artwork_colors")
            .also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        requests.toList().forEach { it.complete(mapOf("cancelled" to true)) }
        worker?.shutdownNow()
        worker = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "extract") {
            result.notImplemented()
            return
        }
        val path = call.argument<String>("path")
        val bytes = call.argument<ByteArray>("bytes")
        if (path.isNullOrEmpty() && (bytes == null || bytes.isEmpty())) {
            result.success(null)
            return
        }
        val executor = worker
        if (executor == null) {
            result.success(null)
            return
        }
        // This channel serves the current player cover. Let an active job
        // finish, but replace work which has not started with the latest one.
        requests.toList().forEach { old ->
            if (executor.remove(old)) old.complete(mapOf("cancelled" to true))
        }
        val request = Extraction(path, bytes, result)
        requests.add(request)
        executor.execute(request)
    }

    private inner class Extraction(
        private val path: String?,
        private val bytes: ByteArray?,
        private val result: MethodChannel.Result,
    ) : Runnable {
        private var completed = false

        override fun run() {
            var bitmap: Bitmap? = null
            val started = SystemClock.elapsedRealtimeNanos()
            val colors = try {
                bitmap = decode(path, bytes)
                val decoded = SystemClock.elapsedRealtimeNanos()
                bitmap?.let { image ->
                    ArtworkColorExtractor.extract(image).also {
                        val finished = SystemClock.elapsedRealtimeNanos()
                        Log.d("ArtworkColors", "Bitmap ${image.width}x${image.height}; " +
                            "decode=${(decoded - started) / 1_000_000}ms; " +
                            "extract=${(finished - decoded) / 1_000_000}ms; " +
                            "thread=${Thread.currentThread().name}")
                    }
                }
            } catch (error: Exception) {
                Log.w("ArtworkColors", "Could not sample cover", error)
                null
            } finally {
                bitmap?.recycle()
            }
            main.post { complete(colors) }
        }

        // All completions, including engine detach and queued cancellations,
        // run on the main thread so a channel reply is sent exactly once.
        fun complete(colors: Map<String, Any?>?) {
            if (completed) return
            completed = true
            requests.remove(this)
            result.success(colors)
        }
    }

    private fun decode(path: String?, bytes: ByteArray?): Bitmap? {
        fun read(options: BitmapFactory.Options): Bitmap? = if (bytes != null) {
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        } else {
            BitmapFactory.decodeFile(path, options)
        }
        val options = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
            inSampleSize = 1
        }
        read(options)
        if (options.outWidth <= 0 || options.outHeight <= 0) return null
        val width = minOf(192, options.outWidth)
        val height = minOf(192, options.outHeight)
        // Sample while decoding, then match Flutter's existing 192x192 cover
        // input. Only this bounded software bitmap is read by the extractor.
        while (maxOf(options.outWidth, options.outHeight) / options.inSampleSize > 384) {
            options.inSampleSize *= 2
        }
        options.inJustDecodeBounds = false
        options.inPreferredConfig = Bitmap.Config.ARGB_8888
        options.inScaled = false
        val decoded = read(options) ?: return null
        if (decoded.width == width && decoded.height == height) return decoded
        return try {
            Bitmap.createScaledBitmap(decoded, width, height, true).also {
                if (it !== decoded) decoded.recycle()
            }
        } catch (error: Exception) {
            decoded.recycle()
            throw error
        }
    }
}
