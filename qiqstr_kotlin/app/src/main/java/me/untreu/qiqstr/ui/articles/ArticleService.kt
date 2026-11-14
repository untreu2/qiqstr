package me.untreu.qiqstr.ui.articles

import com.qiqstr.core.dbGetHydratedArticle
import com.qiqstr.core.dbGetHydratedArticleByNaddr
import com.qiqstr.core.dbGetHydratedArticles
import com.qiqstr.core.dbGetHydratedNotesByIds
import com.qiqstr.core.dbSaveEvents
import com.qiqstr.core.fetchEventById
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Article
import me.untreu.qiqstr.domain.Note
import org.json.JSONArray

data class ArticleAddress(val pubkey: String, val identifier: String, val kind: Int = 30023) {
    val naddr: String? get() = Nip19.naddr(kind, pubkey, identifier)
    val coordinate: String get() = "$kind:$pubkey:$identifier"

    companion object {
        fun from(naddr: String): ArticleAddress? {
            val tlv = Nip19.decodeTLV(naddr.trim()) ?: return null
            if (tlv.str("type") != "naddr") return null
            val pubkey = tlv.str("pubkey") ?: return null
            val kind = tlv.int("kind")
            return ArticleAddress(pubkey, tlv.optString("identifier", ""), if (kind == 0) 30023 else kind)
        }
    }
}

val Article.address: ArticleAddress get() = ArticleAddress(pubkey, dTag)
val Article.naddr: String? get() = address.naddr
val Article.shareURL: String? get() = naddr?.let { "https://njump.me/$it" }
val Article.displayTitle: String get() = title.ifEmpty { L("untitledArticle") }
val Article.readingMinutes: Int get() = maxOf(1, content.split(Regex("\\s+")).count { it.isNotEmpty() } / 220)
val Article.progressKey: String get() = "$pubkey:${dTag.ifEmpty { id }}"

object ArticleService {
    const val PAGE_SIZE = 50

    suspend fun articles(authors: List<String>?, limit: Int): List<Article> {
        val raw = runCatching { dbGetHydratedArticles(authors, limit.toUInt(), Session.mutedPubkeys, Session.mutedWords) }.getOrNull()
        val seen = HashSet<String>()
        return Json.array(raw).map(Article::from).filter { it.id.isNotEmpty() && seen.add("${it.pubkey}:${it.dTag}") }
    }

    suspend fun sync(authors: List<String>?, force: Boolean) {
        SyncService.syncArticles(authors, force)
    }

    suspend fun fetchOlder(authors: List<String>?, until: Long): Int {
        val filter = mutableMapOf<String, Any?>("kinds" to listOf(30023), "until" to maxOf(0, until - 1), "limit" to PAGE_SIZE)
        if (authors != null) filter["authors"] = authors
        val events = SyncService.fetchEvents(filter, timeout = 10)
        if (events.isEmpty()) return 0
        runCatching { dbSaveEvents(JSONArray(events).toString()) }
        SyncService.fetchMissingProfiles(events.mapNotNull { it.str("pubkey") }.distinct())
        return events.size
    }

    suspend fun article(id: String): Article? {
        val json = Json.obj(runCatching { dbGetHydratedArticle(id) }.getOrNull()) ?: return null
        return Article.from(json).takeIf { it.id.isNotEmpty() }
    }

    suspend fun article(address: ArticleAddress): Article? {
        val json = Json.obj(runCatching { dbGetHydratedArticleByNaddr(address.pubkey, address.identifier) }.getOrNull()) ?: return null
        return Article.from(json).takeIf { it.id.isNotEmpty() }
    }

    suspend fun fetch(id: String): Article? {
        val raw = runCatching { fetchEventById(id, 8u) }.getOrNull()
        if (Json.obj(raw) != null) runCatching { dbSaveEvents("[$raw]") }
        return article(id)
    }

    suspend fun fetch(address: ArticleAddress): Article? {
        val events = SyncService.fetchEvents(
            mapOf("kinds" to listOf(address.kind), "authors" to listOf(address.pubkey), "#d" to listOf(address.identifier), "limit" to 1),
            timeout = 10,
        )
        if (events.isNotEmpty()) {
            runCatching { dbSaveEvents(JSONArray(events).toString()) }
            DataBus.feedChanged()
        }
        return article(address)
    }

    suspend fun note(id: String): Note? {
        suspend fun local(): Note? =
            Note.list(runCatching { dbGetHydratedNotesByIds(listOf(id), emptyList(), emptyList(), Session.pubkey) }.getOrNull()).firstOrNull()
        local()?.let { return it }
        val raw = runCatching { fetchEventById(id, 8u) }.getOrNull()
        val event = Json.obj(raw)
        if (event != null) {
            runCatching { dbSaveEvents("[$raw]") }
            SyncService.backgroundFollowUps(listOf(event))
        }
        return local()
    }
}
