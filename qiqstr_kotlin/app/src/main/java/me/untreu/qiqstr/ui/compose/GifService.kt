package me.untreu.qiqstr.ui.compose

import android.net.Uri
import androidx.compose.runtime.Immutable
import com.qiqstr.core.fetchEventsFromRelays
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Note
import org.json.JSONObject

@Immutable
data class GifItem(
    val url: String,
    val preview: String,
    val title: String,
    val width: Int?,
    val height: Int?,
    val blurhash: String?,
    val sha256: String?,
) {
    val id: String get() = url

    companion object {
        fun from(event: JSONObject): GifItem? {
            val tags = event.tags()
            val value: (String) -> String? = { name -> tags.firstOrNull { it.size > 1 && it[0] == name && it[1].isNotEmpty() }?.get(1) }
            val url = value("url")?.takeIf { it.startsWith("https://") } ?: return null
            val isGifPath = runCatching { Uri.parse(url).path }.getOrNull()?.lowercase()?.endsWith(".gif") == true
            if (value("m")?.lowercase() != "image/gif" && !isGifPath) return null
            if (Note.contentWarning("", tags) != null) return null
            val preview = tags.firstOrNull { it.size > 1 && it[0] == "thumb" && it[1].lowercase().endsWith(".gif") }?.get(1) ?: url
            val content = event.text("content")
            val described = value("summary") ?: value("alt") ?: Json.obj(content)?.str("title") ?: if (content.startsWith("{")) "" else content
            val size = value("dim")?.lowercase()?.split("x")?.mapNotNull { it.toDoubleOrNull() }?.takeIf { it.size == 2 && it[0] > 0 && it[1] > 0 }
            return GifItem(
                url = url,
                preview = preview,
                title = described.lines().firstOrNull()?.take(120) ?: "",
                width = size?.get(0)?.toInt(),
                height = size?.get(1)?.toInt(),
                blurhash = value("blurhash") ?: value("bh"),
                sha256 = value("x"),
            )
        }
    }
}

object GifService {
    val searchRelays = listOf("wss://relay.ditto.pub")
    val browseRelays = listOf("wss://relay.ditto.pub", "wss://relay.primal.net")

    private val cache = HashMap<String, List<GifItem>>()

    suspend fun recent(): List<GifItem> =
        load("", mapOf("kinds" to listOf(1063), "#m" to listOf("image/gif"), "limit" to 60), browseRelays)

    suspend fun search(query: String): List<GifItem> {
        val term = query.trim().lowercase()
        if (term.isEmpty()) return recent()
        return coroutineScope {
            val searched = async { load("s:$term", mapOf("kinds" to listOf(1063), "#m" to listOf("image/gif"), "search" to term, "limit" to 60), searchRelays) }
            val tagged = async { load("t:$term", mapOf("kinds" to listOf(1063), "#m" to listOf("image/gif"), "#t" to listOf(term), "limit" to 60), browseRelays) }
            (searched.await() + tagged.await()).distinctBy { it.url }
        }
    }

    private suspend fun load(key: String, filter: Map<String, Any?>, relays: List<String>): List<GifItem> {
        cache[key]?.let { return it }
        val muted = Session.mutedPubkeys.toSet()
        val raw = runCatching { fetchEventsFromRelays(Json.string(filter), relays, 8u) }.getOrNull()
        val items = Json.array(raw)
            .filter { (it.str("pubkey") ?: "") !in muted }
            .sortedByDescending { it.long("created_at") }
            .mapNotNull(GifItem::from)
            .distinctBy { it.url }
        if (items.isNotEmpty()) cache[key] = items
        return items
    }
}
