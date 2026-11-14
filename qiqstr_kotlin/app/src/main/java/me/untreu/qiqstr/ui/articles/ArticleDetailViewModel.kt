package me.untreu.qiqstr.ui.articles

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Article

enum class ArticlePhase { LOADING, FETCHING, LOADED, MISSING }

class ArticleDetailViewModel : ViewModel() {
    var phase by mutableStateOf(ArticlePhase.LOADING)
        private set
    var article by mutableStateOf<Article?>(null)
        private set
    var blocks by mutableStateOf<List<MarkdownBlock>>(emptyList())
        private set
    var highlights by mutableStateOf<List<ArticleHighlight>>(emptyList())
        private set
    var isLoadingHighlights by mutableStateOf(false)
        private set
    private var blockTexts: List<String> = emptyList()
    private var highlightsAddress: ArticleAddress? = null

    suspend fun load(articleId: String?, naddr: String?) {
        if (article == null) phase = ArticlePhase.LOADING
        val address = naddr ?: articleId?.takeIf { Nip19.stripScheme(it).startsWith("naddr1") }
        when {
            address != null -> loadAddress(ArticleAddress.from(address))
            articleId != null -> loadId(articleId)
            else -> phase = ArticlePhase.MISSING
        }
    }

    private suspend fun loadId(id: String) {
        val local = ArticleService.article(id)
        if (local != null) {
            apply(local)
            refreshLatest(local.address)
            return
        }
        phase = ArticlePhase.FETCHING
        val remote = ArticleService.fetch(id)
        if (remote != null) apply(remote) else phase = ArticlePhase.MISSING
    }

    private suspend fun loadAddress(address: ArticleAddress?) {
        if (address == null) { phase = ArticlePhase.MISSING; return }
        val local = ArticleService.article(address)
        if (local != null) {
            apply(local)
            refreshLatest(address)
            return
        }
        phase = ArticlePhase.FETCHING
        val remote = ArticleService.fetch(address)
        if (remote != null) apply(remote) else phase = ArticlePhase.MISSING
    }

    private suspend fun refreshLatest(address: ArticleAddress) {
        val latest = ArticleService.fetch(address) ?: return
        val current = article ?: return
        if (latest.createdAt > current.createdAt) apply(latest)
    }

    private suspend fun apply(next: Article) {
        val changed = article?.id != next.id
        if (changed) {
            val parsed = withContext(Dispatchers.Default) {
                val parsedBlocks = MarkdownParser.parse(next.content)
                Triple(parsedBlocks, parsedBlocks.map { it.plainText }, MarkdownParser.pubkeys(next.content))
            }
            blocks = parsed.first
            blockTexts = parsed.second
            viewModelScope.launch { ProfileCache.load(listOf(next.pubkey) + parsed.third) }
        }
        article = next
        phase = ArticlePhase.LOADED
        if (highlightsAddress != next.address) {
            highlightsAddress = next.address
            viewModelScope.launch { loadHighlights() }
        }
    }

    suspend fun loadHighlights() {
        val address = article?.address ?: return
        isLoadingHighlights = true
        try {
            val local = HighlightService.local(address)
            if (local.isNotEmpty()) highlights = local
            val fetched = HighlightService.fetch(address)
            if (address != article?.address) return
            highlights = fetched
            ProfileCache.load(fetched.map { it.pubkey }.distinct())
        } finally {
            isLoadingHighlights = false
        }
    }

    suspend fun publishHighlight(text: String, context: String, comment: String): Boolean {
        val current = article ?: return false
        return try {
            val highlight = HighlightService.publish(text, context, comment, current)
            if (highlights.none { it.id == highlight.id }) highlights = listOf(highlight) + highlights
            ToastCenter.show(L("highlightPublished"), ToastStyle.SUCCESS)
            true
        } catch (error: Throwable) {
            ToastCenter.error(error)
            false
        }
    }

    fun blockIndex(highlight: ArticleHighlight): Int? {
        val needle = highlight.content.split("\n").map { it.trimWs() }.firstOrNull { it.isNotEmpty() } ?: highlight.content
        return blockTexts.indexOfFirst { it.contains(needle) }.takeIf { it >= 0 }
    }
}
