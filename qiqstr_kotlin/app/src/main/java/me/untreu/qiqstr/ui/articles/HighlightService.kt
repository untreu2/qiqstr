package me.untreu.qiqstr.ui.articles

import com.qiqstr.core.signEvent
import com.qiqstr.core.dbQueryEvents
import com.qiqstr.core.dbSaveEvents
import me.untreu.qiqstr.core.CoreError
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Article
import org.json.JSONArray
import org.json.JSONObject

data class ArticleHighlight(
    val id: String,
    val pubkey: String,
    val content: String,
    val comment: String?,
    val createdAt: Long,
) {
    companion object {
        fun from(j: JSONObject): ArticleHighlight? {
            if (j.int("kind") != 9802) return null
            val id = j.str("id") ?: return null
            val pubkey = j.str("pubkey") ?: return null
            val content = j.optString("content", "").trim()
            if (content.isEmpty()) return null
            val comment = j.tags().firstOrNull { it.firstOrNull() == "comment" && it.size > 1 }?.get(1)?.trim()?.ifEmpty { null }
            return ArticleHighlight(id, pubkey, content, comment, j.long("created_at"))
        }
    }
}

object HighlightService {
    suspend fun local(address: ArticleAddress): List<ArticleHighlight> {
        val filter = Json.string(mapOf("kinds" to listOf(9802), "#a" to listOf(address.coordinate), "limit" to 300))
        return parse(Json.array(runCatching { dbQueryEvents(filter, 300u) }.getOrNull()))
    }

    suspend fun fetch(address: ArticleAddress): List<ArticleHighlight> {
        val events = SyncService.fetchEvents(mapOf("kinds" to listOf(9802), "#a" to listOf(address.coordinate), "limit" to 300), timeout = 8)
        if (events.isNotEmpty()) {
            runCatching { dbSaveEvents(JSONArray(events).toString()) }
            SyncService.fetchMissingProfiles(events.mapNotNull { it.str("pubkey") }.distinct())
        }
        return local(address)
    }

    suspend fun publish(text: String, context: String, comment: String, article: Article): ArticleHighlight {
        Session.requireSigner()
        val content = text.trim()
        if (content.isEmpty()) throw CoreError(L("highlightEmpty"))
        val tags = mutableListOf(
            listOf("a", article.address.coordinate),
            listOf("p", article.pubkey, "", "author"),
            listOf("alt", "Highlight: ${content.take(80)}"),
        )
        val trimmedContext = context.trim()
        if (trimmedContext.isNotEmpty() && trimmedContext != content) tags.add(listOf("context", trimmedContext))
        val trimmedComment = comment.trim()
        if (trimmedComment.isNotEmpty()) tags.add(listOf("comment", trimmedComment))
        val json = signEvent(9802.toUShort(), content, tags)
        val event = SyncService.publish(json)
        return ArticleHighlight.from(event) ?: throw CoreError(L("highlightFailed"))
    }

    private fun parse(events: List<JSONObject>): List<ArticleHighlight> {
        val muted = Session.mutedPubkeys.toSet()
        val seen = HashSet<String>()
        return events.mapNotNull(ArticleHighlight::from)
            .filter { it.pubkey !in muted && seen.add(it.id) }
            .sortedByDescending { it.createdAt }
    }
}
