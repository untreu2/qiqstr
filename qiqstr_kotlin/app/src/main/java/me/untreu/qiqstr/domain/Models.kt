package me.untreu.qiqstr.domain

import androidx.compose.runtime.Immutable
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.bool
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.objects
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.strings
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.bridge.Nip19
import org.json.JSONObject

@Immutable
data class Note(
    val id: String,
    val pubkey: String,
    val content: String,
    val createdAt: Long,
    val tags: List<List<String>>,
    val isRepost: Boolean = false,
    val repostEventId: String? = null,
    val repostedBy: String? = null,
    val repostedByName: String? = null,
    val repostCreatedAt: Long? = null,
    val isReply: Boolean = false,
    val isQuote: Boolean = false,
    val quotedNoteId: String? = null,
    val rootId: String? = null,
    val parentId: String? = null,
    val authorName: String? = null,
    val authorImage: String? = null,
    val authorNip05: String? = null,
    val reactionCount: Int = 0,
    val repostCount: Int = 0,
    val replyCount: Int = 0,
    val zapCount: Int = 0,
    val hasReacted: Boolean = false,
    val hasReposted: Boolean = false,
    val hasZapped: Boolean = false,
    val kind: Int = 1,
) {
    val displayTimestamp: Long get() = repostCreatedAt ?: createdAt
    val listId: String get() = repostEventId ?: id
    val hashtags: List<String> get() = tags.filter { it.firstOrNull() == "t" && it.size > 1 }.map { it[1] }
    val contentWarning: String? get() = contentWarning(content, tags)

    companion object {
        fun from(j: JSONObject): Note = Note(
            id = j.str("id") ?: "",
            pubkey = j.str("pubkey") ?: j.str("author") ?: "",
            content = j.text("content"),
            createdAt = j.long("created_at").takeIf { it != 0L } ?: j.long("createdAt"),
            tags = j.tags(),
            isRepost = j.bool("isRepost"),
            repostEventId = j.str("repostEventId"),
            repostedBy = j.str("repostedBy"),
            repostedByName = j.str("repostedByName"),
            repostCreatedAt = if (j.opt("repostCreatedAt") is Number) j.long("repostCreatedAt") else null,
            isReply = j.bool("isReply"),
            isQuote = j.bool("isQuote"),
            quotedNoteId = j.str("quotedNoteId"),
            rootId = j.str("rootId"),
            parentId = j.str("parentId"),
            authorName = j.str("authorName"),
            authorImage = j.str("authorImage"),
            authorNip05 = j.str("authorNip05"),
            reactionCount = j.long("reactionCount").toInt(),
            repostCount = j.long("repostCount").toInt(),
            replyCount = j.long("replyCount").toInt(),
            zapCount = j.long("zapCount").toInt(),
            hasReacted = j.bool("hasReacted"),
            hasReposted = j.bool("hasReposted"),
            hasZapped = j.bool("hasZapped"),
            kind = j.long("kind").toInt().takeIf { it != 0 } ?: 1,
        )

        fun list(json: String?): List<Note> = Json.array(json).map(::from).filter { it.id.isNotEmpty() }

        suspend fun parsed(json: String?): List<Note> {
            if (json.isNullOrEmpty()) return emptyList()
            return withContext(Dispatchers.Default) { list(json) }
        }

        private val nsfw = Regex("""(^|\s)#nsfw(?![\p{L}\p{N}_])""", RegexOption.IGNORE_CASE)

        fun contentWarning(content: String, tags: List<List<String>>): String? {
            tags.firstOrNull { it.firstOrNull() == "content-warning" }?.let { return if (it.size > 1) it[1].trim() else "" }
            val namespaced = tags.any { it.size > 1 && it[0] == "L" && it[1].lowercase() == "content-warning" }
            for (tag in tags) {
                if (tag.size <= 1 || tag[0] != "l") continue
                if (tag[1].lowercase() == "content-warning") return ""
                if (tag.size > 2 && tag[2].lowercase() == "content-warning") return tag[1]
                if (namespaced && tag.size == 2) return tag[1]
            }
            if (namespaced) return ""
            val tagged = tags.any { it.size > 1 && it[0] == "t" && it[1].lowercase() == "nsfw" }
            if (tagged || nsfw.containsMatchIn(content)) return "NSFW"
            return null
        }
    }
}

@Immutable
data class Profile(
    val pubkey: String,
    val name: String = "",
    val displayName: String = "",
    val about: String = "",
    val picture: String = "",
    val banner: String = "",
    val nip05: String = "",
    val lud16: String = "",
    val website: String = "",
    val location: String = "",
) {
    val id: String get() = pubkey
    val givenName: String? get() = displayName.ifEmpty { null } ?: name.ifEmpty { null }
    val bestName: String get() = displayName.ifEmpty { null } ?: name.ifEmpty { null } ?: shortNpub(pubkey)

    val metadataJSON: String
        get() {
            val m = JSONObject()
            if (name.isNotEmpty()) m.put("name", name)
            if (displayName.isNotEmpty()) m.put("display_name", displayName)
            if (about.isNotEmpty()) m.put("about", about)
            if (picture.isNotEmpty()) m.put("picture", picture)
            if (banner.isNotEmpty()) m.put("banner", banner)
            if (nip05.isNotEmpty()) m.put("nip05", nip05)
            if (lud16.isNotEmpty()) m.put("lud16", lud16)
            if (website.isNotEmpty()) m.put("website", website)
            if (location.isNotEmpty()) m.put("location", location)
            return m.toString()
        }

    companion object {
        fun from(j: JSONObject, fallbackPubkey: String = "") = Profile(
            pubkey = j.str("pubkeyHex") ?: j.str("pubkey") ?: fallbackPubkey,
            name = j.str("name") ?: "",
            displayName = j.str("display_name") ?: j.str("displayName") ?: "",
            about = j.str("about") ?: "",
            picture = j.str("picture") ?: j.str("profileImage") ?: "",
            banner = j.str("banner") ?: "",
            nip05 = j.str("nip05") ?: "",
            lud16 = j.str("lud16") ?: "",
            website = j.str("website") ?: "",
            location = j.str("location") ?: "",
        )

        fun shortNpub(hex: String): String {
            val npub = Nip19.npub(hex) ?: hex
            if (npub.length <= 16) return npub
            return "${npub.take(10)}…${npub.takeLast(6)}"
        }
    }
}

@Immutable
data class Article(
    val id: String,
    val pubkey: String,
    val title: String,
    val content: String,
    val image: String?,
    val summary: String?,
    val dTag: String,
    val publishedAt: Long,
    val createdAt: Long,
    val hashtags: List<String>,
    val authorName: String?,
    val authorImage: String?,
) {
    companion object {
        fun from(j: JSONObject): Article {
            val createdAt = j.long("created_at")
            val published = j.long("publishedAt")
            val now = System.currentTimeMillis() / 1000
            return Article(
                id = j.str("id") ?: "",
                pubkey = j.str("pubkey") ?: "",
                title = j.str("title") ?: "",
                content = j.text("content"),
                image = j.str("image"),
                summary = j.str("summary"),
                dTag = j.str("dTag") ?: "",
                publishedAt = if (published in 1..(now + 86400 * 365)) published else createdAt,
                createdAt = createdAt,
                hashtags = j.strings("hashtags"),
                authorName = j.str("authorName"),
                authorImage = j.str("authorImage"),
            )
        }
    }
}

enum class NotificationKind(val raw: String) {
    REACTION("reaction"), REPOST("repost"), REPLY("reply"), MENTION("mention"), ZAP("zap"), QUOTE("quote"), UNKNOWN("unknown");

    companion object {
        fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: UNKNOWN
    }
}

@Immutable
data class NotificationItem(
    val id: String,
    val kind: NotificationKind,
    val fromPubkey: String,
    val targetNoteId: String?,
    val content: String,
    val createdAt: Long,
    val fromName: String?,
    val fromImage: String?,
    val zapAmount: Long,
) {
    companion object {
        const val MAX_SATS = 2_100_000_000_000_000L

        fun from(j: JSONObject) = NotificationItem(
            id = j.str("id") ?: java.util.UUID.randomUUID().toString(),
            kind = NotificationKind.from(j.str("type")),
            fromPubkey = j.str("fromPubkey") ?: "",
            targetNoteId = j.str("targetNoteId"),
            content = j.text("content"),
            createdAt = j.long("createdAt"),
            fromName = j.str("fromName"),
            fromImage = j.str("fromImage"),
            zapAmount = j.long("zapAmount").coerceIn(0, MAX_SATS),
        )
    }
}

sealed interface ContentPart {
    data class Text(val text: String) : ContentPart
    data class Mention(val id: String) : ContentPart
}

@Immutable
data class ParsedContent(
    val parts: List<ContentPart>,
    val mediaUrls: List<String>,
    val linkUrls: List<String>,
    val quoteIds: List<String>,
    val articleIds: List<String>,
) {
    companion object {
        fun from(j: JSONObject) = ParsedContent(
            parts = j.objects("textParts").mapNotNull { p ->
                when (p.str("type")) {
                    "text" -> ContentPart.Text(p.text("text"))
                    "mention" -> p.str("id")?.let { ContentPart.Mention(it) }
                    else -> null
                }
            },
            mediaUrls = j.strings("mediaUrls"),
            linkUrls = j.strings("linkUrls"),
            quoteIds = j.strings("quoteIds"),
            articleIds = j.strings("articleIds"),
        )
    }
}
