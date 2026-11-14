package me.untreu.qiqstr.data.services

import android.net.Uri
import com.qiqstr.core.dbGetHydratedArticle
import com.qiqstr.core.dbGetHydratedArticles
import com.qiqstr.core.dbGetHydratedNotesByIds
import com.qiqstr.core.dbSaveEvents
import com.qiqstr.core.dbSearchNotes
import com.qiqstr.core.dbSearchProfiles
import com.qiqstr.core.fetchEventsFromRelays
import com.qiqstr.core.validateMnemonic
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Article
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile
import org.json.JSONObject

enum class SearchKind(val eventKind: Int) {
    PEOPLE(0), NOTES(1), ARTICLES(30023);

    val relays: List<String>
        get() = when (this) {
            PEOPLE -> listOf(RelayConfig.vertexRelayUrl, "wss://search.nos.today", "wss://nostr.wine")
            NOTES, ARTICLES -> listOf("wss://search.nos.today", "wss://nostr.wine", "wss://relay.ditto.pub")
        }
}

data class SearchContext(val pubkey: String?, val mutedPubkeys: List<String>, val mutedWords: List<String>) {
    companion object {
        val current: SearchContext get() = SearchContext(Session.pubkey, Session.mutedPubkeys, Session.mutedWords)
    }
}

data class SearchBatch(val events: List<JSONObject>, val failed: Boolean)

object SearchService {
    const val REMOTE_TIMEOUT = 6
    private val entityPrefixes = listOf("npub1", "nprofile1", "note1", "nevent1", "naddr1")
    private val tokenSeparator = Regex("""[\s"'()]+""")

    fun containsSecret(text: String): Boolean {
        val tokens = text.lowercase().split(tokenSeparator).filter { it.isNotEmpty() }
        if (tokens.any { token ->
                val value = Nip19.stripScheme(token)
                value.startsWith("nsec1") || value.startsWith("ncryptsec1") || (value.contains("walletconnect://") && value.contains("secret="))
            }) return true
        val words = tokens.filter { it.isNotEmpty() && it.all(Char::isLetter) }
        for (size in listOf(24, 12)) {
            if (words.size < size) continue
            for (start in 0..(words.size - size)) {
                if (runCatching { validateMnemonic(words.subList(start, start + size).joinToString(" ")) }.getOrDefault(false)) return true
            }
        }
        return false
    }

    fun looksSecret(text: String): Boolean {
        val value = Nip19.stripScheme(text.trim()).lowercase()
        if (value.startsWith("nsec1") || value.startsWith("ncryptsec1") || value.contains("walletconnect://")) return true
        val words = value.split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (words.size !in setOf(12, 15, 18, 21, 24)) return false
        return runCatching { validateMnemonic(words.joinToString(" ")) }.getOrDefault(false)
    }

    fun entityURL(input: String): String? {
        var text = input.trim()
        if (text.isEmpty() || text.contains(" ")) return null
        val uri = runCatching { Uri.parse(text) }.getOrNull()
        val last = uri?.lastPathSegment
        if (!uri?.host.isNullOrEmpty() && last != null) text = last
        text = Nip19.stripScheme(text).lowercase()
        if (entityPrefixes.none { text.startsWith(it) }) return null
        return if (Nip19.decode(text) == null) null else "nostr:$text"
    }

    fun hexId(input: String): String? {
        val text = input.trim()
        if (text.length != 64 || !text.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) return null
        return text.lowercase()
    }

    fun hashtag(input: String): String? {
        val text = input.trim()
        val tag = if (text.startsWith("#")) text.drop(1) else text
        if (tag.isEmpty() || tag.length > 40 || !tag.all { it.isLetterOrDigit() || it == '_' || it == '-' }) return null
        return tag.lowercase()
    }

    suspend fun localProfiles(query: String, limit: Int, context: SearchContext): List<Profile> {
        val muted = context.mutedPubkeys.toSet()
        return Json.array(runCatching { dbSearchProfiles(query, limit.toUInt()) }.getOrNull())
            .map { Profile.from(it) }
            .filter { it.pubkey.isNotEmpty() && it.pubkey !in muted }
    }

    suspend fun localNotes(query: String, limit: Int, context: SearchContext): List<Note> {
        val ids = Json.array(runCatching { dbSearchNotes(query, limit.toUInt()) }.getOrNull()).mapNotNull { it.str("id") }
        return notes(ids, context).sortedByDescending { it.createdAt }
    }

    suspend fun localArticles(query: String, limit: Int, context: SearchContext): List<Article> {
        val needle = query.lowercase()
        val raw = runCatching { dbGetHydratedArticles(null, 250u, context.mutedPubkeys, context.mutedWords) }.getOrNull()
        val seen = HashSet<String>()
        return Json.array(raw).map(Article::from).filter { article ->
            if (article.id.isEmpty() || !seen.add("${article.pubkey}:${article.dTag}")) return@filter false
            article.title.lowercase().contains(needle) ||
                (article.summary ?: "").lowercase().contains(needle) ||
                (article.authorName ?: "").lowercase().contains(needle) ||
                article.hashtags.any { it.lowercase().contains(needle) }
        }.take(limit)
    }

    fun remote(kind: SearchKind, query: String, limit: Int): Flow<SearchBatch> = channelFlow {
        for (relay in kind.relays) launch { send(fetch(kind, query, limit, relay)) }
    }

    private suspend fun fetch(kind: SearchKind, query: String, limit: Int, relay: String): SearchBatch {
        val filter = mapOf("kinds" to listOf(kind.eventKind), "search" to query, "limit" to limit)
        return try {
            val raw = fetchEventsFromRelays(Json.string(filter), listOf(relay), REMOTE_TIMEOUT.toUInt())
            val events = Json.array(raw).filter { it.int("kind") == kind.eventKind && it.str("id") != null && !isLikelySpam(it) }
            SearchBatch(events, false)
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            SearchBatch(emptyList(), true)
        }
    }

    private fun isLikelySpam(event: JSONObject): Boolean {
        if (event.int("kind") != 1) return false
        val words = event.text("content").split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (words.size < 4) return false
        val tags = words.count { it.startsWith("#") }
        return tags.toDouble() / words.size > 0.6
    }

    suspend fun store(events: List<JSONObject>) {
        if (events.isEmpty()) return
        runCatching { dbSaveEvents(Json.string(events)) }
    }

    suspend fun notes(ids: List<String>, context: SearchContext = SearchContext.current): List<Note> {
        if (ids.isEmpty()) return emptyList()
        val raw = runCatching { dbGetHydratedNotesByIds(ids, context.mutedPubkeys, context.mutedWords, context.pubkey) }.getOrNull()
        val byId = Note.parsed(raw).associateBy { it.id }
        return ids.mapNotNull { byId[it] }
    }

    fun profiles(events: List<JSONObject>, context: SearchContext): List<Profile> {
        val muted = context.mutedPubkeys.toSet()
        val seen = HashSet<String>()
        return events.mapNotNull { event ->
            val pubkey = event.str("pubkey") ?: return@mapNotNull null
            if (pubkey in muted || !seen.add(pubkey)) return@mapNotNull null
            val metadata = Json.obj(event.text("content")) ?: return@mapNotNull null
            Profile.from(metadata, pubkey).copy(pubkey = pubkey)
        }
    }

    suspend fun articles(events: List<JSONObject>): List<Article> {
        val result = mutableListOf<Article>()
        val seen = HashSet<String>()
        for (id in events.mapNotNull { it.str("id") }) {
            val json = Json.obj(runCatching { dbGetHydratedArticle(id) }.getOrNull()) ?: continue
            val article = Article.from(json)
            if (article.id.isEmpty() || article.title.isEmpty() || !seen.add("${article.pubkey}:${article.dTag}")) continue
            result.add(article)
        }
        return result
    }

    fun pubkeys(events: List<JSONObject>): List<String> = events.mapNotNull { it.str("pubkey") }.distinct()
}
