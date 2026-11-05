package com.cyshine.music

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.util.Size
import android.webkit.MimeTypeMap
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/** Query the indexed audio collection; scanning never opens individual songs. */
class MediaLibraryPlugin : FlutterPlugin {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private val worker = Executors.newFixedThreadPool(2)
    private val resolver get() = context.contentResolver

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "cy_shine_music/media_library")
        channel.setMethodCallHandler { call, result ->
            if (call.method == "sdk") {
                result.success(Build.VERSION.SDK_INT)
                return@setMethodCallHandler
            }
            worker.execute {
                try {
                    val value: Any? = when (call.method) {
                        "query" -> queryAudio(call.argument<List<String>>("directories").orEmpty())
                        "folders" -> folderPaths()
                        "find" -> findAudio(requireNotNull(call.argument<String>("path")))
                        "artwork" -> artwork(Uri.parse(requireNotNull(call.argument<String>("uri"))))
                        "canSave" -> saveLocation(call.argument<String>("directory").orEmpty()) != null
                        "save" -> saveAudio(
                            requireNotNull(call.argument<String>("directory")),
                            requireNotNull(call.argument<String>("source")),
                            requireNotNull(call.argument<String>("name")),
                        )
                        else -> { result.notImplemented(); return@execute }
                    }
                    result.success(value)
                } catch (error: Exception) {
                    result.error(if (error is SecurityException) "AUDIO_PERMISSION" else "MEDIA_LIBRARY_FAILED",
                        error.message ?: "无法读取系统音乐库", null)
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }

    private fun requireAudioPermission() {
        if (Build.VERSION.SDK_INT < 23) return
        val permission = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO
            else Manifest.permission.READ_EXTERNAL_STORAGE
        val wide = Build.VERSION.SDK_INT >= 30 && Environment.isExternalStorageManager()
        if (!wide && context.checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
            throw SecurityException("请在「权限与目录」授予音乐和音频读取权限")
        }
    }

    private val projection: Array<String> get() = arrayOf(
        MediaStore.Audio.Media._ID, MediaStore.MediaColumns.DATA,
        MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.SIZE,
        MediaStore.MediaColumns.DATE_MODIFIED, MediaStore.MediaColumns.DATE_ADDED,
        MediaStore.Audio.Media.TITLE, MediaStore.Audio.Media.ARTIST, MediaStore.Audio.Media.ALBUM,
        *if (Build.VERSION.SDK_INT >= 29) arrayOf(MediaStore.MediaColumns.VOLUME_NAME,
            MediaStore.MediaColumns.RELATIVE_PATH) else emptyArray(),
    )

    private fun text(cursor: Cursor, column: String): String? {
        val index = cursor.getColumnIndex(column)
        return if (index < 0 || cursor.isNull(index)) null else cursor.getString(index)
    }

    private fun number(cursor: Cursor, column: String): Long =
        text(cursor, column)?.toLongOrNull() ?: 0L

    private fun volumeRoot(volume: String): File? {
        if (volume == "external" || volume == "external_primary") return Environment.getExternalStorageDirectory()
        if (Build.VERSION.SDK_INT < 24) return null
        val found = context.getSystemService(StorageManager::class.java).storageVolumes
            .firstOrNull { it.uuid.equals(volume, ignoreCase = true) } ?: return null
        return if (Build.VERSION.SDK_INT >= 30) found.directory else File("/storage/${found.uuid}")
    }

    private fun rowPath(cursor: Cursor): String? {
        text(cursor, MediaStore.MediaColumns.DATA)?.takeIf { it.startsWith('/') }?.let { return it }
        if (Build.VERSION.SDK_INT < 29) return null
        val volume = text(cursor, MediaStore.MediaColumns.VOLUME_NAME) ?: return null
        val relative = text(cursor, MediaStore.MediaColumns.RELATIVE_PATH) ?: return null
        val name = text(cursor, MediaStore.MediaColumns.DISPLAY_NAME) ?: return null
        val root = volumeRoot(volume) ?: return null
        return File(File(root, relative), name).path
    }

    private fun row(cursor: Cursor): Map<String, Any?>? {
        val path = rowPath(cursor) ?: return null
        val volume = if (Build.VERSION.SDK_INT >= 29)
            text(cursor, MediaStore.MediaColumns.VOLUME_NAME) ?: "external" else "external"
        val uri = ContentUris.withAppendedId(MediaStore.Audio.Media.getContentUri(volume),
            number(cursor, MediaStore.Audio.Media._ID)).toString()
        fun tag(column: String) = text(cursor, column)?.trim()?.takeUnless { it.isEmpty() || it == "<unknown>" }
        return mapOf(
            "path" to path, "contentUri" to uri, "aliases" to listOf(uri),
            "fileName" to (text(cursor, MediaStore.MediaColumns.DISPLAY_NAME) ?: File(path).name),
            "sizeBytes" to number(cursor, MediaStore.MediaColumns.SIZE),
            "modifiedMs" to number(cursor, MediaStore.MediaColumns.DATE_MODIFIED) * 1000,
            "createdMs" to number(cursor, MediaStore.MediaColumns.DATE_ADDED) * 1000,
            "title" to tag(MediaStore.Audio.Media.TITLE), "artist" to tag(MediaStore.Audio.Media.ARTIST),
            "album" to tag(MediaStore.Audio.Media.ALBUM),
        )
    }

    private fun escapedLike(value: String) = value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")

    private fun queryAudio(directories: List<String>): Map<String, Any?> {
        requireAudioPermission()
        val roots = directories.filter { it.startsWith('/') }.map { it.trimEnd('/') + "/" }.distinct()
        if (roots.isEmpty()) return mapOf("files" to emptyList<Any>(), "unavailable" to emptyList<String>())
        val unavailable = if (Build.VERSION.SDK_INT >= 29)
            roots.filter { it.startsWith("/storage/") && storageLocation(it) == null }.map { it.trimEnd('/') }
            else emptyList()
        val clauses = mutableListOf<String>()
        val args = mutableListOf<String>()
        for (root in roots) {
            clauses.add("${MediaStore.MediaColumns.DATA} LIKE ? ESCAPE '\\'")
            args.add(escapedLike(root) + "%")
            if (Build.VERSION.SDK_INT >= 29) {
                storageLocation(root)?.let { location ->
                    clauses.add("(${MediaStore.MediaColumns.VOLUME_NAME} = ? AND ${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ? ESCAPE '\\')")
                    args.add(location.first)
                    args.add(escapedLike(location.second) + "%")
                }
            }
        }
        val rows = mutableListOf<Map<String, Any?>>()
        val published = if (Build.VERSION.SDK_INT >= 29) " AND ${MediaStore.MediaColumns.IS_PENDING} = 0" else ""
        val cursor = resolver.query(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, projection,
            "(" + clauses.joinToString(" OR ") + ")" + published, args.toTypedArray(), null)
            ?: error("系统音乐库未返回结果，请稍后重试")
        cursor.use {
            while (it.moveToNext()) {
                val value = row(it) ?: continue
                val path = value["path"] as String
                if (roots.any { root -> path.startsWith(root) }) rows.add(value)
            }
        }
        return mapOf("files" to rows, "unavailable" to unavailable)
    }

    private fun folderPaths(): List<String> {
        requireAudioPermission()
        val columns = arrayOf(MediaStore.MediaColumns.DATA, MediaStore.MediaColumns.DISPLAY_NAME,
            *if (Build.VERSION.SDK_INT >= 29) arrayOf(MediaStore.MediaColumns.VOLUME_NAME,
                MediaStore.MediaColumns.RELATIVE_PATH) else emptyArray())
        val folders = sortedSetOf<String>()
        val cursor = resolver.query(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, columns, null, null, null)
            ?: error("无法读取音乐文件夹")
        cursor.use { while (it.moveToNext()) rowPath(it)?.let { path -> File(path).parent?.let(folders::add) } }
        return folders.toList()
    }

    private fun findAudio(path: String): Map<String, Any?>? {
        var uri = Uri.parse(path)
        if (uri.scheme == "content" && uri.authority != MediaStore.AUTHORITY) {
            if (Build.VERSION.SDK_INT < 29 || !DocumentsContract.isDocumentUri(context, uri)) return null
            uri = runCatching { MediaStore.getMediaUri(context, uri) }.getOrNull() ?: return null
        }
        val content = uri.scheme == "content"
        return resolver.query(if (content) uri else MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection, if (content) null else "${MediaStore.MediaColumns.DATA} = ?",
            if (content) null else arrayOf(path), null)?.use { if (it.moveToFirst()) row(it) else null }
    }

    private fun artwork(uri: Uri): ByteArray? {
        if (uri.authority != MediaStore.AUTHORITY) return null
        var bitmap: Bitmap? = null
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                bitmap = runCatching { resolver.loadThumbnail(uri, Size(192, 192), null) }.getOrNull()
            }
            if (bitmap == null) {
                val album = resolver.query(uri, arrayOf(MediaStore.Audio.Media.ALBUM_ID), null, null, null)
                    ?.use { if (it.moveToFirst()) it.getLong(0) else null } ?: return null
                val volume = uri.pathSegments.firstOrNull() ?: "external"
                val albumUri = ContentUris.withAppendedId(Uri.parse("content://media/$volume/audio/albumart"), album)
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                resolver.openInputStream(albumUri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
                var sample = 1
                while (bounds.outWidth / sample > 384 || bounds.outHeight / sample > 384) sample *= 2
                bitmap = resolver.openInputStream(albumUri)?.use {
                    BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
                }
            }
            val image = bitmap ?: return null
            return ByteArrayOutputStream().use {
                check(image.compress(Bitmap.CompressFormat.PNG, 100, it))
                it.toByteArray()
            }
        } catch (_: Exception) {
            return null
        } finally { bitmap?.recycle() }
    }

    private fun storageLocation(directory: String): Pair<String, String>? {
        if (Build.VERSION.SDK_INT < 29 || !directory.startsWith('/')) return null
        for (volume in MediaStore.getExternalVolumeNames(context)) {
            val root = volumeRoot(volume)?.path?.trimEnd('/') ?: continue
            if (directory.trimEnd('/') == root) return volume to ""
            if (directory.startsWith("$root/")) return volume to (directory.substring(root.length + 1).trimEnd('/') + "/")
        }
        return null
    }

    private fun saveLocation(directory: String): Pair<String, String>? {
        val location = storageLocation(directory) ?: return null
        val top = location.second.substringBefore('/')
        val allowed = setOf("Music", "Podcasts", "Audiobooks", "Alarms", "Notifications", "Ringtones", "Recordings", "Download")
        return location.takeIf { top in allowed && location.second.split('/').none { it == ".." || it == "." } }
    }

    private fun saveAudio(directory: String, source: String, name: String): String {
        check(Build.VERSION.SDK_INT >= 29)
        val location = saveLocation(directory) ?: error("该位置请通过系统目录选择器授权后保存")
        require(name.isNotBlank() && '/' !in name && '\\' !in name && name != "." && name != "..")
        val inputFile = File(source)
        check(inputFile.isFile && inputFile.length() > 0) { "下载临时文件不存在或为空" }
        val collection = if (location.second.substringBefore('/') == "Download")
            MediaStore.Downloads.getContentUri(location.first) else MediaStore.Audio.Media.getContentUri(location.first)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(name.substringAfterLast('.', "mp3").lowercase()) ?: "audio/mpeg")
            put(MediaStore.MediaColumns.RELATIVE_PATH, location.second)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val target = resolver.insert(collection, values) ?: error("无法创建音乐文件")
        try {
            val output = resolver.openOutputStream(target, "w") ?: error("无法写入音乐文件")
            inputFile.inputStream().use { input -> output.use { input.copyTo(it) } }
            val size = resolver.openFileDescriptor(target, "r")?.use { it.statSize } ?: -1L
            check(size == inputFile.length()) { "音乐文件保存不完整" }
            check(resolver.update(target, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null) > 0)
            return ContentUris.withAppendedId(MediaStore.Audio.Media.getContentUri(location.first), ContentUris.parseId(target)).toString()
        } catch (error: Exception) {
            runCatching { resolver.delete(target, null, null) }
            throw error
        }
    }
}
