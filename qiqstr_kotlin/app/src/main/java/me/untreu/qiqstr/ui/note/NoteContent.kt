package me.untreu.qiqstr.ui.note

import androidx.compose.foundation.text.appendInlineContent
import me.untreu.qiqstr.data.services.CustomEmoji
import android.net.Uri
import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withLink
import kotlinx.coroutines.yield
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.domain.ContentPart
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile

sealed interface NoteContentSegment {
    data class Text(val text: String) : NoteContentSegment
    data class Link(val url: String) : NoteContentSegment
    data class Hashtag(val tag: String) : NoteContentSegment
    data class Mention(val bech: String) : NoteContentSegment
    data class Emoji(val shortcode: String, val url: String) : NoteContentSegment
}

@Immutable
data class NoteMediaItem(
    val url: String,
    val isVideo: Boolean,
    val aspectRatio: Float? = null,
    val blurhash: String? = null,
    val alt: String? = null,
    val poster: String? = null,
) {
    val id: String get() = url
}

data class NoteImeta(
    val url: String,
    val mimeType: String?,
    val width: Double?,
    val height: Double?,
    val blurhash: String?,
    val alt: String?,
    val poster: String?,
    val duration: Double? = null,
    val waveform: List<Int> = emptyList(),
) {
    val aspectRatio: Float? get() = if (width != null && height != null) (width / height).toFloat() else null

    companion object {
        fun from(tag: List<String>): NoteImeta? {
            if (tag.firstOrNull() != "imeta") return null
            val fields = HashMap<String, String>()
            for (entry in tag.drop(1)) {
                val space = entry.indexOf(' ')
                if (space < 0) continue
                val key = entry.substring(0, space)
                if (!fields.containsKey(key)) fields[key] = entry.substring(space + 1).trim()
            }
            val url = fields["url"]?.takeIf { it.isNotEmpty() } ?: return null
            var width: Double? = null
            var height: Double? = null
            fields["dim"]?.let { dim ->
                val parts = dim.lowercase().split("x").mapNotNull { it.toDoubleOrNull() }
                if (parts.size == 2 && parts[0] > 0 && parts[1] > 0) { width = parts[0]; height = parts[1] }
            }
            return NoteImeta(
                url = url,
                mimeType = fields["m"]?.lowercase(),
                width = width,
                height = height,
                blurhash = fields["blurhash"]?.ifEmpty { null },
                alt = fields["alt"]?.ifEmpty { null },
                poster = fields["image"]?.ifEmpty { null } ?: fields["thumb"]?.ifEmpty { null },
                duration = fields["duration"]?.toDoubleOrNull(),
                waveform = fields["waveform"].orEmpty().split(" ").mapNotNull { it.toIntOrNull() },
            )
        }

        fun map(tags: List<List<String>>): Map<String, NoteImeta> {
            val result = HashMap<String, NoteImeta>()
            for (tag in tags) from(tag)?.let { if (!result.containsKey(it.url)) result[it.url] = it }
            return result
        }
    }
}

class NoteContent(content: String, tags: List<List<String>>) {
    val segments: List<NoteContentSegment>
    val truncatedSegments: List<NoteContentSegment>?
    val media: List<NoteMediaItem>
    val audio: List<NoteAudioItem>
    val linkUrls: List<String>
    val quoteIds: List<String>
    val articleIds: List<String>
    val mentionPubkeys: List<String>
    val isEmptyText: Boolean
    val contentWarning: String? = Note.contentWarning(content, tags)

    init {
        val parsed = NoteRepository.parse(content)
        val imeta = NoteImeta.map(tags)
        val emojis = CustomEmoji.map(tags)
        val segments = mutableListOf<NoteContentSegment>()
        val mentions = mutableListOf<String>()
        for (part in parsed.parts) {
            when (part) {
                is ContentPart.Text -> segments.addAll(split(part.text, emojis))
                is ContentPart.Mention -> {
                    segments.add(NoteContentSegment.Mention(part.id))
                    Nip19.pubkeyHex(part.id)?.let { if (it !in mentions) mentions.add(it) }
                }
            }
        }
        val audioItems = mutableListOf<NoteAudioItem>()
        for (url in parsed.linkUrls) {
            if (!NoteAudioItem.isAudio(url, imeta[url]?.mimeType) || audioItems.any { it.url == url }) continue
            audioItems.add(NoteAudioItem(url, imeta[url]?.duration, imeta[url]?.waveform ?: emptyList()))
        }
        audio = audioItems
        if (audioItems.isNotEmpty()) {
            val urls = audioItems.map { it.url }.toSet()
            segments.removeAll { it is NoteContentSegment.Link && it.url in urls }
            while ((segments.lastOrNull() as? NoteContentSegment.Text)?.text?.isBlank() == true) segments.removeAt(segments.lastIndex)
            (segments.lastOrNull() as? NoteContentSegment.Text)?.let { segments[segments.lastIndex] = NoteContentSegment.Text(it.text.trimEnd()) }
        }
        this.segments = segments
        truncatedSegments = truncate(segments, TRUNCATION_LIMIT)
        media = parsed.mediaUrls.map { url ->
            val lower = (runCatching { Uri.parse(url).path }.getOrNull() ?: url).lowercase()
            val meta = imeta[url]
            val isVideo = meta?.mimeType?.startsWith("video/")
                ?: (lower.endsWith(".mp4") || lower.endsWith(".mov") || lower.endsWith(".m4v") || lower.endsWith(".webm"))
            NoteMediaItem(url, isVideo, meta?.aspectRatio, meta?.blurhash, meta?.alt, meta?.poster)
        }
        linkUrls = parsed.linkUrls.filter { url -> audioItems.none { it.url == url } }
        quoteIds = parsed.quoteIds.mapNotNull { Nip19.decode(it) }.distinct()
        articleIds = parsed.articleIds.distinct()
        mentionPubkeys = mentions
        isEmptyText = segments.all { it is NoteContentSegment.Text && it.text.isBlank() }
    }

    fun inlineEmojis(segments: List<NoteContentSegment>) = segments.filterIsInstance<NoteContentSegment.Emoji>().associate { it.url to it.shortcode }

    val images: List<NoteMediaItem> get() = media.filter { !it.isVideo }
    val videos: List<NoteMediaItem> get() = media.filter { it.isVideo }

    val translatableText: String
        get() = segments.mapNotNull {
            when (it) {
                is NoteContentSegment.Text -> it.text
                is NoteContentSegment.Hashtag -> "#${it.tag}"
                else -> null
            }
        }.joinToString("").trim()

    val previewLink: String? get() = if (linkUrls.size == 1 && media.isEmpty()) linkUrls.first() else null

    fun annotated(
        segments: List<NoteContentSegment>,
        linkColor: Color,
        profiles: Map<String, Profile>,
        mentionWeight: FontWeight = FontWeight.Medium,
    ): AnnotatedString = buildAnnotatedString {
        val linkStyle = TextLinkStyles(SpanStyle(color = linkColor))
        for (segment in segments) {
            when (segment) {
                is NoteContentSegment.Text -> append(segment.text)
                is NoteContentSegment.Emoji -> appendInlineContent(segment.url, ":${segment.shortcode}:")
                is NoteContentSegment.Link -> withLink(LinkAnnotation.Clickable(segment.url, linkStyle) { Router.openUrl(segment.url) }) {
                    append(displayUrl(segment.url))
                }
                is NoteContentSegment.Hashtag -> withLink(LinkAnnotation.Clickable("#${segment.tag}", linkStyle) { Router.push(Route.Hashtag(segment.tag)) }) {
                    append("#${segment.tag}")
                }
                is NoteContentSegment.Mention -> {
                    val hex = Nip19.pubkeyHex(segment.bech)
                    val name = hex?.let { profiles[it]?.bestName } ?: hex?.let(Profile::shortNpub) ?: segment.bech
                    if (hex != null) {
                        val style = TextLinkStyles(SpanStyle(color = linkColor, fontWeight = mentionWeight))
                        withLink(LinkAnnotation.Clickable("@$hex", style) { Router.push(Route.Profile(hex)) }) { append("@$name") }
                    } else {
                        pushStyle(SpanStyle(color = linkColor, fontWeight = mentionWeight))
                        append("@$name")
                        pop()
                    }
                }
            }
        }
    }

    companion object {
        const val TRUNCATION_LIMIT = 280
        private val linkRegex = Regex("""https?://[^\s<>"']+""", RegexOption.IGNORE_CASE)
        private val hashtagRegex = Regex("""(?<![\p{L}\p{N}_/#&])#[\p{L}\p{N}_]+""")

        private fun split(text: String, emojis: Map<String, String> = emptyMap()): List<NoteContentSegment> {
            val tokens = mutableListOf<Pair<IntRange, NoteContentSegment>>()
            for (match in linkRegex.findAll(text)) {
                var url = match.value
                while (url.isNotEmpty() && url.last() in ".,;:!?)]}") url = url.dropLast(1)
                if (url.isEmpty()) continue
                tokens.add(match.range.first until match.range.first + url.length to NoteContentSegment.Link(url))
            }
            for (match in hashtagRegex.findAll(text)) {
                if (tokens.any { it.first.first <= match.range.last && match.range.first <= it.first.last }) continue
                tokens.add(match.range to NoteContentSegment.Hashtag(match.value.drop(1)))
            }
            for (match in Regex(":([A-Za-z0-9_-]{1,64}):").findAll(text)) {
                if (tokens.any { it.first.first <= match.range.last && match.range.first <= it.first.last }) continue
                val code = match.groupValues[1]
                emojis[code]?.let { tokens.add(match.range to NoteContentSegment.Emoji(code, it)) }
            }
            tokens.sortBy { it.first.first }
            val result = mutableListOf<NoteContentSegment>()
            var cursor = 0
            for ((range, segment) in tokens) {
                if (range.first > cursor) result.add(NoteContentSegment.Text(text.substring(cursor, range.first)))
                result.add(segment)
                cursor = range.last + 1
            }
            if (cursor < text.length) result.add(NoteContentSegment.Text(text.substring(cursor)))
            return result
        }

        private fun truncate(segments: List<NoteContentSegment>, limit: Int): List<NoteContentSegment>? {
            var length = 0
            val result = mutableListOf<NoteContentSegment>()
            for (segment in segments) {
                val cost = when (segment) {
                    is NoteContentSegment.Text -> segment.text.length
                    is NoteContentSegment.Link -> minOf(segment.url.length, 34)
                    is NoteContentSegment.Hashtag -> segment.tag.length + 1
                    is NoteContentSegment.Mention -> 8
                    is NoteContentSegment.Emoji -> 2
                }
                if (length + cost <= limit) {
                    result.add(segment)
                    length += cost
                    continue
                }
                if (segment is NoteContentSegment.Text && limit - length > 0) {
                    var cut = segment.text.take(limit - length)
                    val space = cut.indexOfLast { it == ' ' || it == '\n' }
                    if (space >= 0 && cut.length - space < 24) cut = cut.substring(0, space)
                    cut = cut.trimEnd()
                    result.add(NoteContentSegment.Text("$cut…"))
                } else {
                    result.add(NoteContentSegment.Text("…"))
                }
                return result
            }
            val newlineCount = segments.sumOf { if (it is NoteContentSegment.Text) it.text.count { c -> c == '\n' } else 0 }
            if (newlineCount > 12) {
                var lines = 0
                val cut = mutableListOf<NoteContentSegment>()
                for (segment in segments) {
                    if (segment is NoteContentSegment.Text) {
                        val kept = StringBuilder()
                        for (ch in segment.text) {
                            if (ch == '\n') lines++
                            if (lines >= 12) break
                            kept.append(ch)
                        }
                        cut.add(NoteContentSegment.Text(kept.toString()))
                        if (lines >= 12) {
                            cut.add(NoteContentSegment.Text("…"))
                            return cut
                        }
                    } else {
                        cut.add(segment)
                    }
                }
            }
            return null
        }

        fun displayUrl(url: String): String {
            var s = url.replace(Regex("^https?://(www\\.)?"), "")
            if (s.endsWith("/")) s = s.dropLast(1)
            return if (s.length > 36) "${s.take(34)}…" else s
        }
    }
}

object NoteContentCache {
    private const val CAPACITY = 1500
    private val store = LinkedHashMap<String, NoteContent>()

    fun content(note: Note): NoteContent {
        synchronized(store) { store[note.id] }?.let { return it }
        val content = NoteContent(note.content, note.tags)
        insert(note.id, content)
        return content
    }

    fun cached(id: String): NoteContent? = synchronized(store) { store[id] }

    suspend fun warm(notes: List<Note>) {
        var built = 0
        for (note in notes) {
            if (cached(note.id) != null) continue
            insert(note.id, NoteContent(note.content, note.tags))
            built += 1
            if (built % 12 == 0) yield()
        }
    }

    private fun insert(id: String, content: NoteContent) = synchronized(store) {
        store[id] = content
        while (store.size > CAPACITY) store.remove(store.keys.first())
    }
}
