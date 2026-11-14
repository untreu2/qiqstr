package me.untreu.qiqstr.ui.explore

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Article
import me.untreu.qiqstr.ui.articles.ArticleService

enum class ExploreScope(val raw: String) {
    FOLLOWING("following"), GLOBAL("global");

    val title: String get() = if (this == FOLLOWING) L("following") else L("exploreGlobal")

    companion object {
        fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: FOLLOWING
    }
}

class ExploreViewModel : ViewModel() {
    var articles by mutableStateOf<List<Article>>(emptyList())
        private set
    var isLoading by mutableStateOf(true)
        private set
    var isLoadingMore by mutableStateOf(false)
        private set
    var canLoadMore by mutableStateOf(false)
        private set
    var hasFollows by mutableStateOf(true)
        private set
    var query by mutableStateOf("")
        private set
    var scope by mutableStateOf(ExploreScope.from(Prefs.string(SCOPE_KEY)))
        private set

    val users = UserSearchModel(viewModelScope, resultLimit = 6)

    private var limit = ArticleService.PAGE_SIZE
    private var authors: List<String>? = null
    private var generation = 0
    private var remoteExhausted = false

    val trimmedQuery: String get() = query.trim().lowercase()

    fun updateQuery(value: String) {
        if (value == query) return
        query = value
        users.updateQuery(value)
    }

    fun updateScope(value: ExploreScope) {
        if (value == scope) return
        scope = value
        Prefs.set(SCOPE_KEY, value.raw)
        viewModelScope.launch { start() }
    }

    val visibleArticles: List<Article>
        get() {
            val q = trimmedQuery
            if (q.isEmpty()) return articles
            return articles.filter { article ->
                article.title.lowercase().contains(q) ||
                    (article.summary ?: "").lowercase().contains(q) ||
                    (article.authorName ?: "").lowercase().contains(q) ||
                    (ProfileCache.profiles[article.pubkey]?.bestName?.lowercase()?.contains(q) ?: false) ||
                    article.hashtags.any { it.lowercase().contains(q) } ||
                    article.content.lowercase().contains(q)
            }
        }

    suspend fun start() {
        generation += 1
        val current = generation
        limit = ArticleService.PAGE_SIZE
        remoteExhausted = false
        articles = emptyList()
        isLoading = true
        resolveAuthors()
        if (current != generation) return
        reload()
        if (articles.isNotEmpty()) isLoading = false
        ArticleService.sync(authors, force = false)
        if (current != generation) return
        reload()
        isLoading = false
    }

    suspend fun refresh() {
        val current = generation
        resolveAuthors()
        if (current != generation) return
        ArticleService.sync(authors, force = true)
        if (current != generation) return
        remoteExhausted = false
        reload()
        isLoading = false
    }

    suspend fun reload() {
        val current = generation
        if (scope == ExploreScope.FOLLOWING && authors.isNullOrEmpty()) {
            articles = emptyList()
            canLoadMore = false
            return
        }
        val loaded = ArticleService.articles(authors, limit)
        if (current != generation) return
        articles = loaded
        canLoadMore = loaded.size >= limit || !remoteExhausted
        viewModelScope.launch { ProfileCache.load(loaded.map { it.pubkey }.distinct()) }
    }

    suspend fun loadMore() {
        if (isLoadingMore || !canLoadMore || trimmedQuery.isNotEmpty()) return
        val current = generation
        isLoadingMore = true
        try {
            val previous = articles.size
            limit += ArticleService.PAGE_SIZE
            reload()
            if (current != generation) return
            if (articles.size <= previous) {
                val oldest = articles.minOfOrNull { it.createdAt } ?: TimeFormat.now
                val fetched = ArticleService.fetchOlder(authors, oldest)
                if (current != generation) return
                if (fetched == 0) remoteExhausted = true
                reload()
                if (articles.size <= previous) canLoadMore = false
            }
        } finally {
            if (current == generation) isLoadingMore = false
        }
    }

    private suspend fun resolveAuthors() {
        when (scope) {
            ExploreScope.GLOBAL -> {
                authors = null
                hasFollows = true
            }
            ExploreScope.FOLLOWING -> {
                val me = Session.pubkey
                if (me == null) {
                    authors = emptyList()
                    return
                }
                val follows = SyncService.followingList(me)
                hasFollows = follows.isNotEmpty()
                authors = (follows + me).distinct()
            }
        }
    }

    companion object {
        private const val SCOPE_KEY = "explore_scope"
    }
}
