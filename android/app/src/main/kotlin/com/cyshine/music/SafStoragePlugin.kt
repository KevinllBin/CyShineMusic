package com.cyshine.music

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.provider.MediaStore
import android.provider.Settings
import android.webkit.MimeTypeMap
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** SAF I/O uses provider grants; local migration only recognizes ExternalStorageProvider. */
class SafStoragePlugin : FlutterPlugin, ActivityAware, PluginRegistry.ActivityResultListener {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private val worker = Executors.newSingleThreadExecutor()
    private var binding: ActivityPluginBinding? = null
    private var pendingPicker: MethodChannel.Result? = null
    private var pickWritable = false
    private lateinit var deletion: NativeFileDeletion
    private val resolver get() = context.contentResolver

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        deletion = NativeFileDeletion(context, worker) { this.binding?.activity }
        channel = MethodChannel(binding.binaryMessenger, "cy_shine_music/saf_storage")
        channel.setMethodCallHandler(::handle)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        deletion.detached(permanent = true)
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addActivityResultListener(this)
        deletion.attached()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        deletion.detached(permanent = false)
        binding?.removeActivityResultListener(this)
        binding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        deletion.detached(permanent = true)
        onDetachedFromActivityForConfigChanges()
        pendingPicker?.error("PICKER_CLOSED", "目录选择已中断，请重试", null)
        pendingPicker = null
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "openAllFilesAccessSettings") {
            try {
                check(Build.VERSION.SDK_INT >= 30) { "当前系统不支持所有文件访问权限" }
                val activity = binding?.activity ?: error("无法打开存储权限设置")
                try {
                    activity.startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:${context.packageName}")))
                } catch (_: Exception) {
                    // Some OEM systems expose only the list of all-files apps.
                    activity.startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                }
                result.success(null)
            } catch (error: Exception) {
                fail(result, error)
            }
            return
        }
        if (call.method == "deleteFiles") {
            deletion.request(call.argument<List<String>>("paths").orEmpty(), result)
            return
        }
        if (call.method == "pickDirectory") {
            if (pendingPicker != null) {
                result.error("PICKER_BUSY", "请先完成当前目录选择", null)
                return
            }
            try {
                val activity = binding?.activity ?: error("无法打开系统目录选择器")
                pickWritable = call.argument<Boolean>("writable") == true
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                    val initial = call.argument<String>("initialUri")
                    if (Build.VERSION.SDK_INT >= 26 && initial?.startsWith("content://") == true) {
                        putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(initial))
                    }
                }
                pendingPicker = result
                activity.startActivityForResult(intent, REQUEST_TREE)
            } catch (error: Exception) {
                pendingPicker = null
                fail(result, error)
            }
            return
        }
        worker.execute {
            try {
                val uri = Uri.parse(requireNotNull(call.argument<String>("uri")))
                val value: Any? = when (call.method) {
                    "validateDirectory" -> {
                        validate(uri, call.argument<Boolean>("writable") == true)
                        null
                    }
                    "scan" -> scan(uri)
                    "resolveLocalPath" -> resolveLocalPath(uri, call.argument<Boolean>("requireReadable") != false)
                    "metadata" -> metadata(uri)
                    "saveFile" -> saveFile(uri,
                        requireNotNull(call.argument<String>("source")),
                        requireNotNull(call.argument<String>("name")))
                    "exists" -> {
                        if (metadata(uri) == null) false else {
                            resolver.openFileDescriptor(uri, "r")?.use { true } ?: false
                        }
                    }
                    "size" -> metadata(uri)?.get("sizeBytes") ?: 0L
                    else -> { result.notImplemented(); return@execute }
                }
                result.success(value)
            } catch (error: Exception) {
                fail(result, error)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (deletion.onActivityResult(requestCode, resultCode)) return true
        if (requestCode != REQUEST_TREE) return false
        val result = pendingPicker ?: return true
        pendingPicker = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        val writable = pickWritable
        worker.execute {
            try {
                val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                check(flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0) { "未获得文件夹读取授权" }
                if (writable) check(flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION != 0) {
                    "未获得文件夹写入授权，请选择可写的文件夹"
                }
                resolver.takePersistableUriPermission(uri, flags)
                val name = metadata(rootDocument(uri))?.get("fileName") as? String ?: "已授权文件夹"
                result.success(mapOf("uri" to uri.toString(), "name" to name))
            } catch (error: Exception) {
                fail(result, error)
            }
        }
        return true
    }

    private fun rootDocument(tree: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))

    // Provider-specific migration for local library folders. Never interpret
    // IDs belonging to downloads, cloud drives or third-party providers.
    private fun resolveLocalPath(uri: Uri, requireReadable: Boolean): String? {
        if (uri.authority == MediaStore.AUTHORITY) {
            val path = resolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)
                ?.use { if (it.moveToFirst()) it.getString(0) else null } ?: return null
            return path.takeIf { !requireReadable || File(it).canRead() }
        }
        if (uri.authority != "com.android.externalstorage.documents") return null
        val id = if (DocumentsContract.isDocumentUri(context, uri))
            DocumentsContract.getDocumentId(uri) else DocumentsContract.getTreeDocumentId(uri)
        val parts = id.split(':', limit = 2)
        if (parts.size != 2) return null
        val volumeId = parts[0]
        val root = if (volumeId == "primary") Environment.getExternalStorageDirectory()
            else if (Build.VERSION.SDK_INT >= 30) {
                context.getSystemService(StorageManager::class.java).storageVolumes
                    .firstOrNull { it.uuid.equals(volumeId, ignoreCase = true) }?.directory
            } else File("/storage/$volumeId")
        if (root == null) return null
        val base = root.canonicalFile
        val local = File(base, parts[1]).canonicalFile
        if (local != base && !local.path.startsWith(base.path + File.separator)) return null
        return local.path.takeIf { !requireReadable || (local.exists() && local.canRead()) }
    }

    private fun validate(tree: Uri, writable: Boolean) {
        val root = rootDocument(tree)
        val info = metadata(root) ?: error("文件夹已不存在，请重新选择")
        check(info["mimeType"] == Document.MIME_TYPE_DIR) { "请选择文件夹" }
        children(tree, DocumentsContract.getTreeDocumentId(tree))
        if (!writable) return
        val probe = DocumentsContract.createDocument(resolver, root, "application/octet-stream",
            ".cyshine-probe-${UUID.randomUUID()}") ?: error("文件夹不可写，请重新选择")
        try {
            val output = resolver.openOutputStream(probe, "wt") ?: error("文件夹不可写，请重新选择")
            output.use { it.write(byteArrayOf(1)) }
        } finally {
            check(DocumentsContract.deleteDocument(resolver, probe)) { "无法清理写入检查文件" }
        }
    }

    private val projection = arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME,
        Document.COLUMN_MIME_TYPE, Document.COLUMN_SIZE, Document.COLUMN_LAST_MODIFIED)

    private fun query(uri: Uri, tree: Uri? = null): List<Map<String, Any?>> {
        val rows = mutableListOf<Map<String, Any?>>()
        val cursor = resolver.query(uri, projection, null, null, null)
            ?: error("无法读取文件夹，请重新选择授权")
        cursor.use {
            while (it.moveToNext()) {
                val id = it.getString(0)
                val document = if (tree == null) uri else DocumentsContract.buildDocumentUriUsingTree(tree, id)
                rows.add(mapOf("id" to id, "path" to document.toString(),
                    "fileName" to it.getString(1), "mimeType" to it.getString(2),
                    "sizeBytes" to if (it.isNull(3)) 0L else it.getLong(3),
                    "modifiedMs" to if (it.isNull(4)) 0L else it.getLong(4)))
            }
        }
        return rows
    }

    private fun metadata(uri: Uri): Map<String, Any?>? {
        if (uri.authority != MediaStore.AUTHORITY) return query(uri).firstOrNull()
        return resolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE, MediaStore.MediaColumns.DATE_MODIFIED), null, null, null)?.use {
            if (!it.moveToFirst()) null else mapOf("path" to uri.toString(),
                "fileName" to it.getString(0), "sizeBytes" to it.getLong(1),
                "modifiedMs" to it.getLong(2) * 1000)
        }
    }

    private fun children(tree: Uri, id: String) = query(
        DocumentsContract.buildChildDocumentsUriUsingTree(tree, id), tree)

    private fun scan(tree: Uri): List<Map<String, Any?>> {
        val roots = java.util.ArrayDeque<String>()
        roots.add(DocumentsContract.getTreeDocumentId(tree))
        val visited = mutableSetOf<String>()
        val files = mutableListOf<Map<String, Any?>>()
        while (roots.isNotEmpty()) {
            val id = roots.removeFirst()
            if (!visited.add(id)) continue
            for (row in children(tree, id)) {
                if (row["mimeType"] == Document.MIME_TYPE_DIR) roots.add(row["id"] as String)
                else if ((row["fileName"] as String).substringAfterLast('.', "").lowercase() in AUDIO_EXTENSIONS) {
                    files.add(row)
                }
            }
        }
        return files
    }

    // A single worker serializes name selection and creation for concurrent downloads.
    private fun saveFile(tree: Uri, source: String, name: String): String {
        require(name.isNotBlank() && name != "." && name != ".." && '/' !in name && '\\' !in name)
        val sourceFile = File(source)
        check(sourceFile.isFile && sourceFile.length() > 0) { "下载临时文件不存在或为空" }
        val names = children(tree, DocumentsContract.getTreeDocumentId(tree)).map { it["fileName"] }.toSet()
        val extension = name.substringAfterLast('.', "")
        val suffix = if (extension.isEmpty()) "" else ".$extension"
        val base = name.removeSuffix(suffix)
        var candidate = name
        var index = 1
        while (candidate in names) candidate = "$base (${index++})$suffix"
        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension.lowercase()) ?: "application/octet-stream"
        val document = DocumentsContract.createDocument(resolver, rootDocument(tree), mime, candidate)
            ?: error("无法创建音乐文件，请重新选择下载目录")
        try {
            val output = resolver.openOutputStream(document, "wt") ?: error("无法写入音乐文件")
            sourceFile.inputStream().use { input -> output.use { input.copyTo(it) } }
            // Reopen and count the bytes so a truncated provider write is not recorded as completed.
            val input = resolver.openInputStream(document) ?: error("无法校验保存的音乐文件")
            val written = input.use {
                val buffer = ByteArray(64 * 1024)
                var total = 0L
                while (true) {
                    val count = it.read(buffer)
                    if (count < 0) break
                    total += count
                }
                total
            }
            check(written == sourceFile.length()) { "音乐文件保存不完整，请重试" }
            return document.toString()
        } catch (error: Exception) {
            runCatching { DocumentsContract.deleteDocument(resolver, document) }
            throw error
        }
    }

    private fun fail(result: MethodChannel.Result, error: Exception) {
        val message = if (error is SecurityException) "文件夹授权已失效，请在「权限与目录」中重新选择文件夹"
            else error.message ?: "文件操作失败，请重新选择文件夹"
        result.error("SAF_FAILED", message, error.toString())
    }

    companion object {
        private const val REQUEST_TREE = 42619
        private val AUDIO_EXTENSIONS = setOf("mp3", "flac", "m4a", "aac", "ogg", "wav", "ape", "wma")
    }
}
