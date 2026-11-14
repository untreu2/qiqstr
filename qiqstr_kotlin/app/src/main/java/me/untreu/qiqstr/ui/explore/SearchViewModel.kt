package me.untreu.qiqstr.ui.explore

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.data.services.RecentSearchStore
import me.untreu.qiqstr.data.services.SearchContext
import me.untreu.qiqstr.data.services.SearchKind
import me.untreu.qiqstr.data.services.SearchService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.services.TrendingService
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Article
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile
import org.json.JSONObject

enum class SearchScope(val raw: String) {
    TOP("top"), PEOPLE("people"), NOTES("notes"), HASHTAGS("hashtags"), ARTICLES("articles");

    val title: String
        get() = when (this) {
            TOP -> L("searchScopeTop")
            PEOPLE -> L("searchScopePeople")
            NOTES -> L("searchScopeNotes")
            HASHTAGS -> L("searchScopeHashtags")
            ARTICLES -> L("searchScopeArticles")
        }
}

data class HashtagMatch(val tag: String, val count: Int)

class SearchViewModel : ViewModel() {
    var query by mutableStateOf("")
        private set
    var scope by mutableStateOf(SearchScope.TOP)

    var people by mutableStateOf<List<Profile>>(emptyList())
        private set
    var notes by mutableStateOf<List<Note>>(emptyList())
        private set
    var articles by mutableStateOf<List<Article>>(emptyList())
        private set
    var resolvedHex by mutableStateOf<String?>(null)
        private set
    var pending by mutableStateOf<Set<SearchKind>>(emptySet())
        private set
    var isSearchingLocal by mutableStateOf(false)
        private set
    var remoteFailed by mutableStateOf(false)
        private set
    var hasSearched by mutableStateOf(false)
        private set
    var opened by mutableIntStateOf(0)
        private set

    var recents by mutableStateOf<List<String>>(emptyList())
        private set
    var suggestions by mutableStateOf<List<Profile>>(emptyList())
        private set
    var trendingNotes by mutableStateOf<List<Note>>(emptyList())
        private set
    var trendingHashtags by mutableStateOf<List<String>>(emptyList())
        private set
    var isLoadingTrending by mutableStateOf(false)
        private set
    var trendingFailed by mutableStateOf(false)
        private set

    private var job: Job? = null
    private var generation = 0
    private val failures = HashMap<SearchKind, Int>()
    private var started = false

    val trimmedQuery: String get() = query.trim()
    val isSearching: Boolean get() = isSearchingLocal || pending.isNotEmpty()
    val queryHashtag: String? get() = SearchService.hashtag(trimmedQuery)

    fun updateQuery(value: String) {
        if (value == query) return
        query = value
        schedule()
    }

    val hashtags: List<HashtagMatch>
        get() {
            val needle = trimmedQuery.lowercase().trim('#')
            if (needle.isEmpty()) return emptyList()
            val counts = HashMap<String, Int>()
            fun count(tags: List<String>) {
                for (tag in tags.map { it.lowercase() }.toSet()) {
                    if (tag.contains(needle) && SearchService.hashtag(tag) == tag) counts[tag] = (counts[tag] ?: 0) + 1
                }
            }
            notes.forEach { count(it.hashtags) }
            articles.forEach { count(it.hashtags) }
            for (tag in trendingHashtags) if (tag.contains(needle) && !counts.containsKey(tag)) counts[tag] = 0
            val matches = counts.map { HashtagMatch(it.key, it.value) }.sortedWith { lhs, rhs ->
                val lp = lhs.tag.startsWith(needle)
                val rp = rhs.tag.startsWith(needle)
                when {
                    lp != rp -> if (lp) -1 else 1
                    lhs.count == rhs.count -> lhs.tag.compareTo(rhs.tag)
                    else -> rhs.count.compareTo(lhs.count)
                }
            }.toMutableList()
            queryHashtag?.let { exact ->
                val current = matches.firstOrNull { it.tag == exact } ?: HashtagMatch(exact, 0)
                matches.removeAll { it.tag == exact }
                matches.add(0, current)
            }
            return matches.take(30)
        }

    val showsEmptyResults: Boolean
        get() {
            if (!hasSearched || isSearching || trimmedQuery.isEmpty() || resolvedHex != null) return false
            return when (scope) {
                SearchScope.TOP -> people.isEmpty() && notes.isEmpty() && articles.isEmpty() && hashtags.isEmpty()
                SearchScope.PEOPLE -> people.isEmpty()
                SearchScope.NOTES -> notes.isEmpty()
                SearchScope.HASHTAGS -> hashtags.isEmpty()
                SearchScope.ARTICLES -> articles.isEmpty()
            }
        }

    suspend fun start() {
        recents = RecentSearchStore.load()
        if (started) return
        started = true
        coroutineScope {
            launch { loadSuggestions() }
            launch { loadTrending(force = false) }
        }
    }

    suspend fun refresh() {
        if (trimmedQuery.isEmpty()) {
            suggestions = UserSearchService.suggestions(25)
            loadTrending(force = true)
        } else {
            schedule(debounce = false)
            job?.join()
        }
    }

    fun submit() {
        val text = trimmedQuery
        if (text.isEmpty()) return
        SearchService.entityURL(text)?.let {
            open(it)
            return
        }
        resolvedHex?.let {
            opened += 1
            Router.push(Route.Profile(it))
            return
        }
        remember()
    }

    fun remember(term: String? = null) {
        recents = RecentSearchStore.add(term ?: trimmedQuery)
    }

    fun useRecent(term: String) {
        updateQuery(term)
        remember(term)
    }

    fun removeRecent(term: String) {
        recents = RecentSearchStore.remove(term)
    }

    fun clearRecents() {
        RecentSearchStore.clear()
        recents = emptyList()
    }

    suspend fun loadTrending(force: Boolean) = coroutineScope {
        if (trendingNotes.isEmpty()) isLoadingTrending = true
        try {
            val tags = async { TrendingService.trendingHashtags(force) }
            val ids = TrendingService.trendingNoteIds(force)
            val loaded = TrendingService.hydratedNotes(ids)
            if (loaded.isNotEmpty() || force) trendingNotes = loaded
            trendingFailed = trendingNotes.isEmpty()
            if (trendingHashtags.isEmpty()) trendingHashtags = TrendingService.hashtags(trendingNotes)
            viewModelScope.launch { ProfileCache.load(loaded.map { it.pubkey }.distinct()) }
            val remoteTags = tags.await()
            if (remoteTags.isNotEmpty()) trendingHashtags = remoteTags
        } finally {
            isLoadingTrending = false
        }
    }

    private suspend fun loadSuggestions() {
        if (suggestions.isNotEmpty()) return
        suggestions = UserSearchService.suggestions(25)
    }

    private fun open(url: String) {
        opened += 1
        Router.openUrl(url)
    }

    private fun schedule(debounce: Boolean = true) {
        job?.cancel()
        generation += 1
        val current = generation
        val text = trimmedQuery
        failures.clear()
        remoteFailed = false
        if (text.isEmpty()) {
            reset()
            return
        }
        if (SearchService.looksSecret(text)) {
            reset()
            ToastCenter.show(L("searchSecretBlocked"), ToastStyle.ERROR)
            return
        }
        SearchService.entityURL(text)?.let {
            reset()
            open(it)
            return
        }
        SearchService.hexId(text)?.let {
            reset()
            resolvedHex = it
            hasSearched = true
            return
        }
        resolvedHex = null
        isSearchingLocal = true
        pending = SearchKind.entries.toSet()
        job = viewModelScope.launch {
            if (debounce) delay(350)
            run(text, current)
        }
    }

    private fun reset() {
        people = emptyList()
        notes = emptyList()
        articles = emptyList()
        resolvedHex = null
        pending = emptySet()
        isSearchingLocal = false
        hasSearched = false
    }

    private suspend fun isCurrent(generation: Int): Boolean = generation == this.generation && coroutineContext.isActive

    private suspend fun run(text: String, generation: Int) = coroutineScope {
        val context = SearchContext.current
        val localPeople = async { SearchService.localProfiles(text, PEOPLE_LIMIT, context) }
        val localNotes = async { SearchService.localNotes(text, NOTES_LIMIT, context) }
        val localArticles = async { SearchService.localArticles(text, ARTICLES_LIMIT, context) }
        val foundPeople = localPeople.await()
        val foundNotes = localNotes.await()
        val foundArticles = localArticles.await()
        if (!isCurrent(generation)) return@coroutineScope
        people = foundPeople
        notes = foundNotes
        articles = foundArticles
        isSearchingLocal = false
        hasSearched = true
        viewModelScope.launch { ProfileCache.load((foundNotes.map { it.pubkey } + foundArticles.map { it.pubkey }).distinct()) }
        for (kind in SearchKind.entries) launch { runRemote(kind, text, context, generation) }
    }

    private suspend fun runRemote(kind: SearchKind, text: String, context: SearchContext, generation: Int) {
        SearchService.remote(kind, text, REMOTE_LIMIT).collect { batch ->
            if (!isCurrent(generation)) return@collect
            if (batch.failed) failures[kind] = (failures[kind] ?: 0) + 1
            if (batch.events.isNotEmpty()) merge(kind, batch.events, context, generation)
        }
        if (generation != this.generation) return
        pending = pending - kind
        updateRemoteFailure()
    }

    private suspend fun merge(kind: SearchKind, events: List<JSONObject>, context: SearchContext, generation: Int) {
        SearchService.store(events)
        if (!isCurrent(generation)) return
        when (kind) {
            SearchKind.PEOPLE -> {
                val found = SearchService.profiles(events, context)
                for (profile in found) if (ProfileCache.profile(profile.pubkey) == null) ProfileCache.set(profile)
                val seen = people.map { it.pubkey }.toHashSet()
                people = (people + found.filter { seen.add(it.pubkey) }).take(PEOPLE_LIMIT)
            }
            SearchKind.NOTES -> {
                val known = notes.map { it.id }.toSet()
                val ids = events.mapNotNull { it.str("id") }.filter { it !in known }
                val hydrated = SearchService.notes(ids, context)
                if (!isCurrent(generation)) return
                val seen = notes.map { it.id }.toHashSet()
                notes = (notes + hydrated.filter { seen.add(it.id) }).take(NOTES_LIMIT)
                SyncService.fetchMissingProfiles(SearchService.pubkeys(events))
                viewModelScope.launch { ProfileCache.load(hydrated.map { it.pubkey }.distinct()) }
            }
            SearchKind.ARTICLES -> {
                val hydrated = SearchService.articles(events)
                if (!isCurrent(generation)) return
                val seen = articles.map { "${it.pubkey}:${it.dTag}" }.toHashSet()
                articles = (articles + hydrated.filter { seen.add("${it.pubkey}:${it.dTag}") }).take(ARTICLES_LIMIT)
                SyncService.fetchMissingProfiles(SearchService.pubkeys(events))
            }
        }
    }

    private fun updateRemoteFailure() {
        if (pending.isNotEmpty()) return
        remoteFailed = SearchKind.entries.all { (failures[it] ?: 0) >= it.relays.size }
    }

    companion object {
        const val PEOPLE_LIMIT = 40
        const val NOTES_LIMIT = 60
        const val ARTICLES_LIMIT = 30
        private const val REMOTE_LIMIT = 25
    }
}
