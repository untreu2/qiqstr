package me.untreu.qiqstr.ui.articles

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import kotlin.math.abs
import kotlin.math.ceil
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Article
import org.json.JSONArray
import org.json.JSONObject

data class ReadingProgressEntry(
    val key: String,
    val articleId: String,
    val naddr: String?,
    val title: String,
    val image: String?,
    val authorPubkey: String,
    val authorName: String?,
    val minutes: Int,
    val progress: Double,
    val updatedAt: Long,
) {
    val id: String get() = key
    val minutesLeft: Int get() = maxOf(1, ceil(minutes * (1 - progress)).toInt())
    val isInProgress: Boolean get() = progress >= ReadingProgressStore.START_THRESHOLD && progress < ReadingProgressStore.FINISH_THRESHOLD

    fun toJson(): JSONObject = JSONObject().apply {
        put("key", key)
        put("articleId", articleId)
        naddr?.let { put("naddr", it) }
        put("title", title)
        image?.let { put("image", it) }
        put("authorPubkey", authorPubkey)
        authorName?.let { put("authorName", it) }
        put("minutes", minutes)
        put("progress", progress)
        put("updatedAt", updatedAt)
    }

    companion object {
        fun from(j: JSONObject): ReadingProgressEntry? {
            val key = j.str("key") ?: return null
            return ReadingProgressEntry(
                key = key,
                articleId = j.str("articleId") ?: return null,
                naddr = j.str("naddr"),
                title = j.optString("title", ""),
                image = j.str("image"),
                authorPubkey = j.str("authorPubkey") ?: return null,
                authorName = j.str("authorName"),
                minutes = j.long("minutes").toInt(),
                progress = j.optDouble("progress", 0.0),
                updatedAt = j.long("updatedAt"),
            )
        }
    }
}

object ReadingProgressStore {
    const val START_THRESHOLD = 0.03
    const val FINISH_THRESHOLD = 0.97
    private const val MAX_ENTRIES = 40

    var version by mutableIntStateOf(0)
        private set
    private var account: String? = null
    private var entries: Map<String, ReadingProgressEntry> = emptyMap()
    private var dirty = false
    private var lastPersist = 0L

    fun continueReading(limit: Int = 3): List<ReadingProgressEntry> {
        version
        return current().values.filter { it.isInProgress }.sortedByDescending { it.updatedAt }.take(limit)
    }

    fun progress(article: Article): Double? = current()[article.progressKey]?.progress

    fun record(article: Article, progress: Double) {
        if (Session.pubkey == null) return
        val all = current().toMutableMap()
        val clamped = progress.coerceIn(0.0, 1.0)
        val existing = all[article.progressKey]
        if (existing != null && abs(existing.progress - clamped) < 0.005) return
        all[article.progressKey] = ReadingProgressEntry(
            key = article.progressKey,
            articleId = article.id,
            naddr = article.naddr,
            title = article.displayTitle,
            image = article.image?.ifEmpty { null },
            authorPubkey = article.pubkey,
            authorName = article.authorName?.ifEmpty { null },
            minutes = article.readingMinutes,
            progress = clamped,
            updatedAt = System.currentTimeMillis(),
        )
        entries = all
        dirty = true
        if (System.currentTimeMillis() - lastPersist > 4000) persist()
    }

    fun remove(entry: ReadingProgressEntry) {
        entries = current() - entry.key
        dirty = true
        persist()
    }

    fun persist() {
        if (!dirty) return
        write()
        version++
    }

    private fun write() {
        val account = account ?: return
        val trimmed = entries.values.sortedByDescending { it.updatedAt }.take(MAX_ENTRIES)
        entries = trimmed.associateBy { it.key }
        Prefs.set(storageKey(account), JSONArray(trimmed.map { it.toJson() }).toString())
        dirty = false
        lastPersist = System.currentTimeMillis()
    }

    private fun current(): Map<String, ReadingProgressEntry> {
        val active = Session.pubkey
        if (active == account) return entries
        if (dirty) write()
        account = active
        dirty = false
        if (active == null) {
            entries = emptyMap()
            return entries
        }
        val list = Json.array(Prefs.string(storageKey(active))).mapNotNull(ReadingProgressEntry::from)
        entries = list.groupBy { it.key }.mapValues { (_, values) -> values.maxBy { it.updatedAt } }
        return entries
    }

    private fun storageKey(account: String) = "reading_progress_$account"
}
