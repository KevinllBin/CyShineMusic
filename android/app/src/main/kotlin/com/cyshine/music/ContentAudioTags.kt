package com.cyshine.music

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.File
import org.jaudiotagger.audio.AudioFileIO
import org.jaudiotagger.tag.FieldKey
import org.jaudiotagger.tag.Tag

object ContentAudioTags {
    fun read(context: Context, path: String, lyrics: Boolean, artwork: Boolean): Map<String, Any?> {
        val uri = Uri.parse(path)
        if (uri.scheme != "content") return payload(AudioFileIO.read(File(path)).tag, lyrics, artwork)
        val resolver = context.contentResolver
        val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }.orEmpty()
        val extension = name.substringAfterLast('.', "").lowercase().ifEmpty {
            MimeTypeMap.getSingleton().getExtensionFromMimeType(resolver.getType(uri)) ?: "mp3"
        }.let { if (it.matches(Regex("[a-z0-9]{1,10}"))) it else "mp3" }
        // readAs supplies the format explicitly because /proc/self/fd has no suffix.
        // Keep the grant descriptor open until all requested metadata has been read.
        val descriptor = resolver.openFileDescriptor(uri, "r") ?: error("无法读取音乐文件")
        descriptor.use {
            try {
                return payload(AudioFileIO.readAs(File("/proc/self/fd/${it.fd}"), extension).tag, lyrics, artwork)
            } catch (_: Exception) {
                // Some providers expose pipes instead of seekable files. Stage only
                // those providers and remove the temporary copy after this read.
            }
        }
        val temporary = File.createTempFile("saf-tags-", ".$extension", context.cacheDir)
        try {
            val input = resolver.openInputStream(uri) ?: error("无法读取音乐文件")
            input.use { source -> temporary.outputStream().use { source.copyTo(it) } }
            return payload(AudioFileIO.read(temporary).tag, lyrics, artwork)
        } finally {
            temporary.delete()
        }
    }

    private fun payload(tag: Tag?, lyrics: Boolean, artwork: Boolean): Map<String, Any?> = mapOf(
        "title" to tag?.getFirst(FieldKey.TITLE),
        "artist" to tag?.getFirst(FieldKey.ARTIST),
        "album" to tag?.getFirst(FieldKey.ALBUM),
        "lyrics" to if (lyrics) tag?.getFirst(FieldKey.LYRICS) else null,
        "artwork" to if (artwork) runCatching { tag?.firstArtwork?.binaryData }.getOrNull() else null,
    )
}
