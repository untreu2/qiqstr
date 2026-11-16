package me.untreu.qiqstr.ui.articles

import androidx.compose.runtime.*
import com.qiqstr.core.createSignedEvent
import com.qiqstr.core.dbDeleteEventsByIds
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import me.untreu.qiqstr.core.CoreError
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Article
import java.util.UUID

@Serializable
data class ArticleDraft(
    val id: String = UUID.randomUUID().toString(), val dTag: String = "", val title: String = "", val summary: String = "",
    val image: String = "", val hashtags: List<String> = emptyList(), val content: String = "",
    val publishedAt: Long? = null, val updatedAt: Long = TimeFormat.now,
) {
    val isBlank: Boolean get() = listOf(title, summary, image, content).all { it.isBlank() } && hashtags.isEmpty()
    val canPublish: Boolean get() = title.isNotBlank() && content.isNotBlank()
    val isEditingPublished: Boolean get() = publishedAt != null
    val displayTitle: String get() = title.trim().ifEmpty { L("untitledArticle") }
    val wordCount: Int get() = content.split(Regex("\\s+")).count { it.isNotEmpty() }
    companion object {
        fun from(article: Article) = ArticleDraft(dTag = article.dTag, title = article.title, summary = article.summary.orEmpty(), image = article.image.orEmpty(), hashtags = article.hashtags, content = article.content, publishedAt = article.publishedAt)
    }
}

object ArticleDraftStore {
    var drafts by mutableStateOf<List<ArticleDraft>>(emptyList())
        private set
    private var owner: String? = null
    private val json = Json { ignoreUnknownKeys = true }
    fun all(): List<ArticleDraft> { ensureLoaded(); return drafts }
    fun draft(id: String): ArticleDraft? = all().firstOrNull { it.id == id }
    fun editing(dTag: String): ArticleDraft? = all().firstOrNull { it.dTag == dTag && it.isEditingPublished }
    fun save(draft: ArticleDraft, account: String? = Session.pubkey) {
        if (account == null || account != Session.pubkey) return
        ensureLoaded()
        if (draft.isBlank) { delete(draft.id); return }
        drafts = listOf(draft.copy(updatedAt = TimeFormat.now)) + drafts.filterNot { it.id == draft.id }
        persist()
    }
    fun delete(id: String) { ensureLoaded(); drafts = drafts.filterNot { it.id == id }; persist() }
    fun reset() { owner = null; drafts = emptyList() }
    private fun ensureLoaded() {
        val account = Session.pubkey
        if (owner == account) return
        owner = account
        drafts = account?.let { runCatching { json.decodeFromString<List<ArticleDraft>>(Prefs.string("article_drafts_$it") ?: "[]") }.getOrDefault(emptyList()) }.orEmpty().sortedByDescending { it.updatedAt }
    }
    private fun persist() { owner?.let { Prefs.set("article_drafts_$it", json.encodeToString(drafts)) } }
}

object ArticlePublisher {
    suspend fun publish(draft: ArticleDraft): ArticleAddress {
        val owner = Session.pubkey ?: throw CoreError(L("noRelayConnection"))
        val key = Session.requireSigner()
        if (!draft.canPublish) throw CoreError(L("articleNeedsTitleAndText"))
        val identifier = draft.dTag.ifEmpty { ArticleIdentifier.make(draft.title) }
        val content = draft.content.trim()
        val tags = mutableListOf(listOf("d", identifier), listOf("title", draft.title.trim()), listOf("published_at", (draft.publishedAt ?: TimeFormat.now).toString()))
        if (draft.summary.isNotBlank()) tags.add(listOf("summary", draft.summary.trim()))
        if (draft.image.isNotBlank()) tags.add(listOf("image", draft.image.trim()))
        tags.addAll(draft.hashtags.map { listOf("t", it) })
        tags.addAll(MarkdownParser.pubkeys(content).filter { it != owner }.map { listOf("p", it) })
        SyncService.publish(createSignedEvent(30023u, content, tags, key))
        if (owner == Session.pubkey) ArticleDraftStore.delete(draft.id)
        DataBus.feedChanged()
        return ArticleAddress(owner, identifier)
    }
    suspend fun delete(article: Article) {
        if (article.pubkey != Session.pubkey) throw CoreError(L("readOnlyMessage"))
        val owner = Session.pubkey
        val event = createSignedEvent(5u, "", listOf(listOf("e", article.id), listOf("a", "30023:${article.pubkey}:${article.dTag}"), listOf("k", "30023")), Session.requireSigner())
        SyncService.publish(event)
        runCatching { dbDeleteEventsByIds(listOf(article.id)) }
        if (owner == Session.pubkey) ArticleDraftStore.editing(article.dTag)?.let { ArticleDraftStore.delete(it.id) }
        DataBus.feedChanged()
    }
}
