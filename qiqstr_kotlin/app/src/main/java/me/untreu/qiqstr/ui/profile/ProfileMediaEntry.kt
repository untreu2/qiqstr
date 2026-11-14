package me.untreu.qiqstr.ui.profile

import androidx.compose.runtime.Immutable
import com.qiqstr.core.parseNoteContent
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.strings
import me.untreu.qiqstr.domain.Note

@Immutable
data class ProfileMediaEntry(
    val url: String,
    val isVideo: Boolean,
    val noteId: String,
    val blurhash: String? = null,
    val alt: String? = null,
    val poster: String? = null,
) {
    val id: String get() = "$noteId|$url"

    companion object {
        private val videoExtensions = listOf(".mp4", ".mov", ".m4v", ".webm")

        fun extract(note: Note): List<ProfileMediaEntry> {
            val parsed = Json.obj(runCatching { parseNoteContent(note.content) }.getOrNull()) ?: return emptyList()
            val imeta = imeta(note.tags)
            return parsed.strings("mediaUrls").map { url ->
                val meta = imeta[url]
                val path = (runCatching { android.net.Uri.parse(url).path }.getOrNull() ?: url).lowercase()
                val isVideo = meta?.get("m")?.lowercase()?.startsWith("video/") ?: videoExtensions.any { path.endsWith(it) }
                ProfileMediaEntry(
                    url = url,
                    isVideo = isVideo,
                    noteId = note.id,
                    blurhash = meta?.get("blurhash")?.ifEmpty { null },
                    alt = meta?.get("alt")?.ifEmpty { null },
                    poster = meta?.get("image")?.ifEmpty { null } ?: meta?.get("thumb")?.ifEmpty { null },
                )
            }
        }

        private fun imeta(tags: List<List<String>>): Map<String, Map<String, String>> {
            val result = HashMap<String, Map<String, String>>()
            for (tag in tags) {
                if (tag.firstOrNull() != "imeta") continue
                val fields = HashMap<String, String>()
                for (entry in tag.drop(1)) {
                    val space = entry.indexOf(' ')
                    if (space < 0) continue
                    val key = entry.substring(0, space)
                    if (!fields.containsKey(key)) fields[key] = entry.substring(space + 1).trim()
                }
                val url = fields["url"]?.ifEmpty { null } ?: continue
                if (!result.containsKey(url)) result[url] = fields
            }
            return result
        }
    }
}
