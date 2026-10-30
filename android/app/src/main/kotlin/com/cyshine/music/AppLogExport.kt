package com.cyshine.music

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Export an immutable log snapshot to public Downloads, readable with adb pull. */
internal object AppLogExport {
    fun save(context: Context, sourcePath: String): Map<String, String> {
        val source = File(sourcePath).canonicalFile
        val dataRoot = File(context.applicationInfo.dataDir).canonicalFile
        require(source.toPath().startsWith(dataRoot.toPath()) && source.isFile) {
            "日志快照不存在"
        }
        val name =
            "cyshine-${context.packageName.substringAfterLast('.')}-" +
                SimpleDateFormat("yyyyMMdd-HHmmss-SSS", Locale.US).format(Date()) +
                ".txt"
        val relative = "${Environment.DIRECTORY_DOWNLOADS}/CyShineMusic/logs"
        val folder =
            File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "CyShineMusic/logs",
            )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = context.contentResolver
            val values =
                ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, name)
                    put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                    put(MediaStore.Downloads.RELATIVE_PATH, relative)
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
            val uri =
                checkNotNull(resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values))
            try {
                checkNotNull(resolver.openOutputStream(uri)).use { output ->
                    source.inputStream().use { it.copyTo(output) }
                }
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                check(resolver.update(uri, values, null, null) > 0)
                return mapOf("path" to File(folder, name).absolutePath, "uri" to uri.toString())
            } catch (failure: Throwable) {
                resolver.delete(uri, null, null)
                throw failure
            }
        }
        check(folder.isDirectory || folder.mkdirs()) { "无法创建日志目录" }
        val file = File(folder, name)
        source.copyTo(file)
        return mapOf("path" to file.absolutePath)
    }
}
