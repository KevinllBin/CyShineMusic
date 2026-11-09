package com.cyshine.music

import android.content.Context
import android.os.Build
import android.os.Process
import java.io.File
import java.io.FileOutputStream
import java.io.PrintWriter
import java.io.StringWriter
import java.util.Date
import kotlin.system.exitProcess

/**
 * Synchronously saves uncaught Java/Kotlin exceptions before Android tears
 * down the process. This is needed on Android 9, where ApplicationExitInfo is
 * unavailable and a Dart logger cannot observe a native process death.
 */
internal object AndroidCrashHandler {
    private const val FILE_NAME = "cyshine-java-crash.txt"
    private const val MAX_BYTES = 64 * 1024
    private var installed = false

    fun install(context: Context) {
        if (installed) return
        installed = true
        val appContext = context.applicationContext
        val appVersion = runCatching {
            @Suppress("DEPRECATION")
            appContext.packageManager.getPackageInfo(appContext.packageName, 0).let {
                "${it.versionName}+${it.versionCode}"
            }
        }.getOrDefault("unknown")
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            write(appContext, appVersion, thread, throwable)
            if (previous != null) {
                previous.uncaughtException(thread, throwable)
            } else {
                Process.killProcess(Process.myPid())
                exitProcess(10)
            }
        }
    }

    fun read(context: Context): String? {
        val file = File(context.filesDir, FILE_NAME)
        if (!file.isFile || file.length() > MAX_BYTES) return null
        return runCatching { file.readText(Charsets.UTF_8) }.getOrNull()
    }

    fun clear(context: Context) {
        File(context.filesDir, FILE_NAME).delete()
    }

    private fun write(context: Context, appVersion: String, thread: Thread, throwable: Throwable) {
        runCatching {
            val file = File(context.filesDir, FILE_NAME)
            val stack = StringWriter()
            throwable.printStackTrace(PrintWriter(stack))
            FileOutputStream(file, false).use { output ->
                val text = buildString {
                    append("timestampMs=").append(System.currentTimeMillis())
                        .append(" date=").append(Date()).append('\n')
                    append("package=").append(context.packageName)
                        .append(" version=").append(appVersion)
                        .append(" device=").append(Build.MANUFACTURER)
                        .append('/').append(Build.MODEL)
                        .append(" sdk=").append(Build.VERSION.SDK_INT).append('\n')
                    append("pid=").append(Process.myPid()).append('\n')
                    append("thread=").append(thread.name)
                        .append("#").append(thread.id).append('\n')
                    append(stack)
                }
                val bytes = text.toByteArray(Charsets.UTF_8)
                output.write(bytes, 0, minOf(bytes.size, MAX_BYTES))
                output.fd.sync()
            }
        }
    }
}
