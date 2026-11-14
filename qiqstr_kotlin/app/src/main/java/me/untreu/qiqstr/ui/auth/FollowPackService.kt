package me.untreu.qiqstr.ui.auth

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.DirectionsRun
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.CameraAlt
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.CurrencyBitcoin
import androidx.compose.material.icons.outlined.Flight
import androidx.compose.material.icons.outlined.Memory
import androidx.compose.material.icons.outlined.MusicNote
import androidx.compose.material.icons.outlined.Newspaper
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.Restaurant
import androidx.compose.material.icons.outlined.Science
import androidx.compose.material.icons.outlined.Security
import androidx.compose.material.icons.outlined.SentimentSatisfied
import androidx.compose.material.icons.outlined.SportsEsports
import com.qiqstr.core.fetchEventsFromRelays
import java.text.Normalizer
import kotlin.math.log2
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.bridge.isHex
import org.json.JSONObject

enum class FollowInterest(val raw: String, val icon: ImageVector, val keywords: List<String>) {
    BITCOIN("bitcoin", Icons.Outlined.CurrencyBitcoin, listOf("bitcoin", "bitcoiners", "btc", "sats", "satoshi", "lightning", "stacker", "stackers", "stacking", "hodl", "hodlers", "plebs", "zap", "einundzwanzig", "coretards", "cashu")),
    NOSTR("nostr", Icons.Outlined.Bolt, listOf("nostr", "nostrich", "nostriches", "napplet", "relay", "relays", "newbie", "starter", "welcome", "jumpstart", "recommended", "nip")),
    ART("art", Icons.Outlined.Palette, listOf("art", "arts", "artist", "artists", "artwork", "creative", "creatives", "aesthete", "aesthetes", "design", "designer", "designers", "illustration", "illustrator", "drawing", "painting", "painter", "anime")),
    PHOTOGRAPHY("photography", Icons.Outlined.CameraAlt, listOf("photo", "photos", "photography", "photographer", "photographers", "camera", "olas", "film")),
    MUSIC("music", Icons.Outlined.MusicNote, listOf("music", "musician", "musicians", "wavlake", "band", "bands", "song", "songs", "dj", "musik", "muzik")),
    TECH("tech", Icons.Outlined.Memory, listOf("tech", "technology", "software", "ai", "llm", "agi", "hardware", "computing", "engineering", "teknoloji", "technik")),
    SCIENCE("science", Icons.Outlined.Science, listOf("science", "scientist", "scientists", "research", "researcher", "physics", "biology", "chemistry", "math", "space", "astronomy", "medicine", "health", "bilim", "wissenschaft")),
    NEWS("news", Icons.Outlined.Newspaper, listOf("news", "journalist", "journalists", "journalism", "media", "press", "reporter", "reporters", "noticias", "nachrichten", "haber", "новости")),
    SPORTS("sports", Icons.AutoMirrored.Outlined.DirectionsRun, listOf("sport", "sports", "football", "soccer", "basketball", "fitness", "running", "cycling", "spor")),
    BOOKS("books", Icons.AutoMirrored.Outlined.MenuBook, listOf("book", "books", "reading", "reader", "readers", "read", "writer", "writers", "author", "authors", "literature", "poetry", "poet", "poets", "kitap", "bücher")),
    GAMING("gaming", Icons.Outlined.SportsEsports, listOf("game", "games", "gamer", "gamers", "gaming", "esports", "chess", "nintendo")),
    FOOD("food", Icons.Outlined.Restaurant, listOf("food", "foodie", "cook", "cooking", "chef", "chefs", "recipe", "recipes", "farm", "farmer", "farmers", "growers", "garden", "gardening", "homestead", "coffee", "bbq")),
    TRAVEL("travel", Icons.Outlined.Flight, listOf("travel", "traveler", "travelers", "traveller", "nomad", "nomads", "adventure", "hiking", "outdoors", "seyahat", "reisen")),
    MEMES("memes", Icons.Outlined.SentimentSatisfied, listOf("meme", "memes", "humor", "humour", "funny", "comedy", "shitpost", "shitposters", "jokes")),
    PRIVACY("privacy", Icons.Outlined.Security, listOf("privacy", "cypherpunk", "cypherpunks", "monero", "xmr", "encryption", "freedom", "rights", "surveillance", "sovereign", "opsec", "tor")),
    DEV("dev", Icons.Outlined.Code, listOf("dev", "devs", "developer", "developers", "desenvolvedores", "programming", "programmer", "programmers", "coder", "coders", "code", "opensource", "engineer", "engineers", "github", "rust", "napplet"));

    val title: String get() = L("authInterest" + raw.replaceFirstChar { it.uppercase() })

    fun relevance(pack: FollowPack): Int {
        if (matches(pack.titleTokens)) return 2
        if (this == NOSTR) return 0
        return if (matches(pack.tokens)) 1 else 0
    }

    fun matches(tokens: Set<String>): Boolean = keywords.any { keyword ->
        if (keyword in tokens) return@any true
        if (keyword.length < 5) return@any false
        tokens.any { it.startsWith(keyword) }
    }

    companion object {
        fun from(raw: String) = entries.firstOrNull { it.raw == raw }

        var saved: Set<FollowInterest>
            get() = Prefs.stringList("onboarding_interests").orEmpty().mapNotNull(::from).toSet()
            set(value) = Prefs.setStringList("onboarding_interests", value.map { it.raw }.sorted())
    }
}

@Immutable
data class FollowPack(
    val id: String,
    val kind: Int,
    val author: String,
    val title: String,
    val summary: String,
    val image: String,
    val members: List<String>,
    val topics: List<String>,
    val createdAt: Long,
) {
    val tokens: Set<String> = tokenize(listOf(title, summary) + topics)
    val titleTokens: Set<String> = tokenize(listOf(title) + topics)

    val isAcceptable: Boolean
        get() {
            if (members.size !in MINIMUM_MEMBERS..MAXIMUM_MEMBERS) return false
            if (tokens.any { it in blockedWords }) return false
            return tokens.none { token -> blockedPrefixes.any { token.startsWith(it) } }
        }

    companion object {
        const val MINIMUM_MEMBERS = 5
        const val MAXIMUM_MEMBERS = 300
        private val blockedWords = setOf("bot", "bots", "mute", "muted", "mutes", "nsfw", "porn", "xxx", "test", "chuds")
        private val blockedPrefixes = listOf("scam", "spam", "blacklist", "blocklist", "blocked")
        private val diacritics = Regex("\\p{Mn}+")
        private val separators = Regex("[^\\p{L}\\p{N}]+")

        fun tokenize(values: List<String>): Set<String> {
            val folded = Normalizer.normalize(values.joinToString(" "), Normalizer.Form.NFD).replace(diacritics, "").lowercase()
            return folded.split(separators).filter { it.isNotEmpty() }.toSet()
        }

        fun from(event: JSONObject): FollowPack? {
            val kind = event.int("kind")
            if (kind != 39089 && kind != 30000) return null
            val author = event.str("pubkey") ?: return null
            val tags = event.tags()
            fun value(name: String) = (tags.firstOrNull { it.size > 1 && it[0] == name }?.get(1) ?: "").trim()
            fun first(vararg names: String) = names.asSequence().map(::value).firstOrNull { it.isNotEmpty() } ?: ""
            val title = first("title", "name")
            if (title.isEmpty()) return null
            val seen = HashSet<String>()
            val members = tags.mapNotNull { tag ->
                if (tag.size <= 1 || tag[0] != "p") return@mapNotNull null
                val key = tag[1].lowercase()
                if (key.length != 64 || !key.all { it.isHex() } || !seen.add(key)) null else key
            }
            val content = event.text("content").trim()
            val usableContent = if (kind == 39089 && content.length < 400 && !content.contains("?iv=")) content else ""
            val described = first("description", "summary")
            return FollowPack(
                id = "$kind:$author:${value("d")}",
                kind = kind,
                author = author,
                title = title,
                summary = described.ifEmpty { usableContent },
                image = value("image"),
                members = members,
                topics = tags.filter { it.size > 1 && it[0] == "t" }.map { it[1].lowercase() },
                createdAt = event.int("created_at").toLong(),
            )
        }
    }
}

object FollowPackService {
    var packs by mutableStateOf<List<FollowPack>>(emptyList())
        private set
    var isLoading by mutableStateOf(false)
        private set
    var hasLoaded by mutableStateOf(false)
        private set
    private var lastLoad: Long? = null
    private var job: Job? = null

    private val packRelays = listOf("wss://relay.damus.io", "wss://nos.lol", "wss://nostr.wine", "wss://relay.nostr.band")
    private val listRelays = listOf("wss://nos.lol", "wss://nostr.wine")
    private const val FRESHNESS = 1_800_000L

    fun prefetch() {
        if (job != null) return
        val last = lastLoad
        if (last != null && System.currentTimeMillis() - last < FRESHNESS && packs.isNotEmpty()) return
        isLoading = true
        job = App.scope.launch {
            try {
                fetchAll()
            } finally {
                isLoading = false
                hasLoaded = true
                lastLoad = System.currentTimeMillis()
                job = null
            }
        }
    }

    suspend fun reload() {
        lastLoad = null
        prefetch()
        job?.join()
    }

    suspend fun waitUntilLoaded() {
        prefetch()
        job?.join()
    }

    fun pack(id: String): FollowPack? = packs.firstOrNull { it.id == id }

    fun ranked(interests: Set<FollowInterest>): List<FollowPack> {
        val primary = scored(interests, requireMatch = interests.isNotEmpty())
        if (primary.size >= 4 || interests.isEmpty()) return primary
        val ids = primary.map { it.id }.toSet()
        val general = scored(setOf(FollowInterest.NOSTR), requireMatch = true).filter { it.id !in ids }
        return primary + general.take(4 - primary.size)
    }

    private fun scored(interests: Set<FollowInterest>, requireMatch: Boolean): List<FollowPack> =
        packs.mapNotNull { pack ->
            val relevance = interests.sumOf { it.relevance(pack) }
            if (requireMatch && relevance == 0) null else pack to (relevance * 5.0 + quality(pack))
        }.sortedByDescending { it.second }.map { it.first }

    private fun quality(pack: FollowPack): Double {
        var score = log2(maxOf(pack.members.size, 1).toDouble())
        if (pack.image.isNotEmpty()) score += 1
        if (pack.summary.isNotEmpty()) score += 1.5
        if (pack.kind == 39089) score += 1
        if (pack.members.size > 150) score -= 2.5
        return score
    }

    private suspend fun fetchAll() = coroutineScope {
        val requests = packRelays.map { Triple(it, 39089, 300) } + listRelays.map { Triple(it, 30000, 250) }
        requests.map { (relay, kind, limit) ->
            async {
                val batch = fetch(relay, kind, limit)
                if (batch.isNotEmpty()) merge(batch)
            }
        }.awaitAll()
    }

    private fun merge(batch: List<FollowPack>) {
        val byId = LinkedHashMap<String, FollowPack>()
        packs.forEach { byId.putIfAbsent(it.id, it) }
        for (pack in batch) if ((byId[pack.id]?.createdAt ?: -1) < pack.createdAt) byId[pack.id] = pack
        val byTitle = HashMap<String, FollowPack>()
        for (pack in byId.values) {
            val key = pack.title.lowercase().trim()
            val existing = byTitle[key]
            if (existing != null && existing.createdAt >= pack.createdAt) continue
            byTitle[key] = pack
        }
        packs = byTitle.values.sortedByDescending { it.createdAt }
    }

    private suspend fun fetch(relay: String, kind: Int, limit: Int): List<FollowPack> {
        val filter = Json.string(mapOf("kinds" to listOf(kind), "limit" to limit))
        val raw = runCatching { fetchEventsFromRelays(filter, listOf(relay), 6u) }.getOrNull() ?: return emptyList()
        return Json.array(raw).mapNotNull(FollowPack::from).filter { it.isAcceptable }
    }
}
