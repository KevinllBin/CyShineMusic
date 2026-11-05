package com.cyshine.music

import android.app.Activity
import android.app.AlertDialog
import android.app.RecoverableSecurityException
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor

/** One user request may contain a system media batch and a provider-only batch. */
internal class NativeFileDeletion(
    context: Context,
    private val worker: Executor,
    private val activity: () -> Activity?,
) {
    private val resolver = context.contentResolver
    private val targets = MediaDeleteTargets(context)
    private val main = Handler(Looper.getMainLooper())
    private var pending: Operation? = null
    private var dialog: AlertDialog? = null

    private class Operation(val reply: MethodChannel.Result) {
        val deleted = linkedSetOf<String>()
        val failed = linkedMapOf<String, String>()
        val media = java.util.ArrayDeque<List<MediaDeleteTarget>>()
        val direct = mutableListOf<MediaDeleteTarget>()
        var activeMedia: List<MediaDeleteTarget>? = null
        var directIndex = 0
        var prepared = false
        var directApproved = false
        var directRunning = false
        var recovering = false
        var recoveryGranted = false
        var checkingMedia = false
        var stopRequested = false
    }

    fun request(paths: List<String>, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("DELETE_BUSY", "请先完成当前删除确认", null)
            return
        }
        val operation = Operation(result)
        pending = operation
        worker.execute {
            val resolved = mutableListOf<MediaDeleteTarget>()
            val failed = linkedMapOf<String, String>()
            for (path in paths.distinct()) {
                try { resolved.add(targets.resolve(path)) }
                catch (error: Exception) { failed[path] = errorMessage(error) }
            }
            main.post {
                if (pending !== operation) return@post
                operation.failed.putAll(failed)
                if (Build.VERSION.SDK_INT >= 30) {
                    // Group aliases of the same media item together, including
                    // overlapping SAF grants. Each system batch stays <= 2000 URIs.
                    val groups = resolved.filter { it.mediaUri != null }.groupBy { it.mediaUri }.values.toList()
                    groups.chunked(2000).forEach { operation.media.add(it.flatten()) }
                    operation.direct.addAll(resolved.filter { it.mediaUri == null })
                } else operation.direct.addAll(resolved)
                operation.prepared = true
                next(operation)
            }
        }
    }

    private fun next(operation: Operation) {
        if (pending !== operation || !operation.prepared || operation.directRunning) return
        if (operation.stopRequested) { finish(operation, cancelled = true); return }
        val host = activity() ?: return // Continue when an Activity reattaches.
        if (operation.activeMedia != null || operation.recovering) return
        if (operation.media.isNotEmpty() && Build.VERSION.SDK_INT >= 30) {
            val batch = operation.media.removeFirst()
            operation.activeMedia = batch
            worker.execute {
                try {
                    val request = MediaStore.createDeleteRequest(resolver, batch.mapNotNull { it.mediaUri }.distinct())
                    main.post {
                        if (pending !== operation) return@post
                        val current = activity()
                        if (current == null) {
                            operation.activeMedia = null
                            operation.media.addFirst(batch)
                        } else try {
                            current.startIntentSenderForResult(request.intentSender, REQUEST_MEDIA, null, 0, 0, 0)
                        } catch (error: Exception) {
                            fallbackBatch(operation, batch)
                        }
                    }
                } catch (error: Exception) {
                    // No system result exists when request creation fails. This
                    // is the safe point to use the existing app-confirmed path.
                    main.post { fallbackBatch(operation, batch) }
                }
            }
            return
        }
        if (operation.directIndex >= operation.direct.size) {
            finish(operation)
            return
        }
        if (operation.directApproved) { deleteDirect(operation); return }
        if (dialog != null) return
        val remaining = operation.direct.drop(operation.directIndex)
        val names = remaining.take(5).joinToString("\n") { it.name }
        dialog = AlertDialog.Builder(host)
            .setTitle("永久删除 ${remaining.size} 个音乐文件？")
            .setMessage("将删除所选音乐文件，并清理对应下载记录。此操作无法撤销。\n\n" +
                names + if (remaining.size > 5) "\n…" else "")
            .setNegativeButton("取消") { _, _ -> finish(operation, cancelled = true) }
            .setPositiveButton("删除") { _, _ ->
                dialog = null
                operation.directApproved = true
                deleteDirect(operation)
            }
            .setOnCancelListener { finish(operation, cancelled = true) }
            .show()
    }

    /**
     * A failure before the system request is launched is a capability failure,
     * so these items may use the app's explicit fallback confirmation. Once the
     * system request has been launched, onActivityResult owns the decision and
     * cancellation must finish the operation without deleting anything else.
     */
    private fun fallbackBatch(operation: Operation, batch: List<MediaDeleteTarget>) {
        if (pending !== operation) return
        operation.direct.addAll(batch)
        operation.activeMedia = null
        next(operation)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_MEDIA && requestCode != REQUEST_RECOVER) return false
        val operation = pending ?: return true
        if (resultCode != Activity.RESULT_OK) {
            finish(operation, cancelled = true)
            return true
        }
        if (requestCode == REQUEST_RECOVER) {
            operation.recovering = false
            operation.recoveryGranted = true
            deleteDirect(operation)
            return true
        }
        val batch = operation.activeMedia ?: return true
        operation.checkingMedia = true
        worker.execute {
            val removed = mutableListOf<String>()
            val failed = linkedMapOf<String, String>()
            for (target in batch) {
                try {
                    // RESULT_OK means the system operation finished. Check the
                    // original grant/path as well so partial provider failures
                    // never remove an undeleted song's local record.
                    check(targets.isMissing(target.path)) { "系统确认后文件仍存在" }
                    removed.add(target.path)
                } catch (error: Exception) { failed[target.path] = errorMessage(error) }
            }
            main.post {
                if (pending !== operation) return@post
                operation.checkingMedia = false
                operation.deleted.addAll(removed)
                operation.failed.putAll(failed)
                operation.activeMedia = null
                next(operation)
            }
        }
        return true
    }

    private fun deleteDirect(operation: Operation) {
        if (pending !== operation) return
        if (operation.stopRequested) { finish(operation, cancelled = true); return }
        if (operation.directIndex >= operation.direct.size) { finish(operation); return }
        val target = operation.direct[operation.directIndex]
        operation.directRunning = true
        worker.execute {
            try {
                targets.deleteDirect(target)
                main.post {
                    if (pending !== operation) return@post
                    operation.directRunning = false
                    operation.deleted.add(target.path)
                    operation.directIndex++
                    operation.recoveryGranted = false
                    deleteDirect(operation)
                }
            } catch (error: Exception) {
                main.post {
                    if (pending !== operation) return@post
                    operation.directRunning = false
                    if (Build.VERSION.SDK_INT >= 29 && error is RecoverableSecurityException &&
                        !operation.recoveryGranted) {
                        try {
                            val host = checkNotNull(activity()) { "删除确认已中断，请重试" }
                            operation.recovering = true
                            host.startIntentSenderForResult(error.userAction.actionIntent.intentSender,
                                REQUEST_RECOVER, null, 0, 0, 0)
                            return@post
                        } catch (launchError: Exception) {
                            operation.recovering = false
                            operation.failed[target.path] = errorMessage(launchError)
                        }
                    } else operation.failed[target.path] = errorMessage(error)
                    operation.directIndex++
                    operation.recoveryGranted = false
                    deleteDirect(operation)
                }
            }
        }
    }

    fun attached() {
        pending?.let(::next)
    }

    fun detached(permanent: Boolean) {
        dialog?.setOnCancelListener(null)
        dialog?.dismiss()
        dialog = null
        if (permanent) pending?.let {
            it.stopRequested = true
            if (!it.directRunning && !it.checkingMedia) finish(it, cancelled = true)
        }
    }

    private fun finish(operation: Operation, cancelled: Boolean = false) {
        if (pending !== operation) return
        pending = null
        dialog?.setOnCancelListener(null)
        dialog?.dismiss()
        dialog = null
        operation.reply.success(mapOf("deletedPaths" to operation.deleted.toList(),
            "failed" to operation.failed, "cancelled" to cancelled))
    }

    private fun errorMessage(error: Exception): String =
        if (error is SecurityException) "文件访问授权不足，请重新选择文件夹或授予存储权限"
        else error.message ?: "删除失败，请重试"

    companion object {
        private const val REQUEST_MEDIA = 42620
        private const val REQUEST_RECOVER = 42621
    }
}
