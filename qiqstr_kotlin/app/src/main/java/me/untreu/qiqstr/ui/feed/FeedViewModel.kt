package me.untreu.qiqstr.ui.feed

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.data.services.DiscoverFeed
import me.untreu.qiqstr.data.services.ExploreSafety
import me.untreu.qiqstr.data.services.ExploreSeenStore
import me.untreu.qiqstr.data.services.ExploreService
import me.untreu.qiqstr.data.services.HashtagFollowService
import me.untreu.qiqstr.data.services.MuteService
import me.untreu.qiqstr.data.services.TrendingService
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.ui.note.FeedFollowSet
import me.untreu.qiqstr.ui.note.FeedSortMode
import me.untreu.qiqstr.ui.note.NoteContentCache
import me.untreu.qiqstr.ui.note.NoteInteractionStore
import me.untreu.qiqstr.ui.note.NoteRepository

sealed interface FeedSource {
    val id: String
    val title: String

    object Explore : FeedSource {
        override val id get() = "explore"
        override val title get() = L("feedExplore")
    }

    data class Discover(val feed: DiscoverFeed) : FeedSource {
        override val id get() = "dvm_${feed.id}"
        override val title get() = feed.name
    }

    object Following : FeedSource {
        override val id get() = "following"
        override val title get() = L("all")
    }

    data class List(val set: FeedFollowSet) : FeedSource {
        override val id get() = set.id
        override val title get() = set.title
    }

    data class Topic(val tag: String) : FeedSource {
        override val id get() = "topic_$tag"
        override val title get() = "#$tag"
    }

    object Topics : FeedSource {
        override val id get() = "topics"
        override val title get() = L("feedTopics")
    }

    val isExplore: Boolean get() = this == Explore
    val isCurated: Boolean get() = this == Explore || this is Discover
    val isTopicFeed: Boolean get() = this is Topic || this == Topics
}

class FeedViewModel : ViewModel() {
    var notes by mutableStateOf<kotlin.collections.List<Note>>(emptyList())
        private set
    var pendingCount by mutableIntStateOf(0)
        private set
    var hasLoaded by mutableStateOf(false)
        private set
    var isSyncing by mutableStateOf(true)
        private set
    var isLoadingMore by mutableStateOf(false)
        private set
    var canLoadMore by mutableStateOf(true)
        private set
    var lists by mutableStateOf<kotlin.collections.List<FeedFollowSet>>(emptyList())
        private set
    var source by mutableStateOf<FeedSource>(FeedSource.Explore)
        private set
    var scrollToTopToken by mutableIntStateOf(0)
        private set

    var sort by mutableStateOf(FeedSortMode.from(Prefs.string("feed_sort_mode")))
        private set
    var showReplies by mutableStateOf(Prefs.bool("feed_show_replies"))
        private set
    var showReposts by mutableStateOf(Prefs.bool("feed_show_reposts", true))
        private set
    var includeTopics by mutableStateOf(Prefs.bool("feed_include_topics"))
        private set

    private var fetched: kotlin.collections.List<Note> = emptyList()
    private var limit = PAGE_SIZE
    private var latestDisplayed = 0L
    private var acceptNext = true
    private var generation = 0
    private val prefetched = HashSet<String>()
    private var exhaustedRelays = false
    private var graceJob: Job? = null
    private var reloadJob: Job? = null
    private val discoverCache = HashMap<String, kotlin.collections.List<Note>>()
    private var exploreHidden: Map<String, Double>? = null

    companion object {
        const val PAGE_SIZE = 50
        private const val EXPLORE_MINIMUM_FRESH = 15

        private suspend fun topicNotes(tags: kotlin.collections.List<String>, limit: Int, includeReplies: Boolean): kotlin.collections.List<Note> {
            val merged = mutableListOf<Note>()
            val seen = HashSet<String>()
            for (tag in tags) {
                for (note in NoteRepository.hashtag(tag, limit)) {
                    if ((includeReplies || !note.isReply) && seen.add(note.listId)) merged.add(note)
                }
            }
            merged.sortByDescending { it.displayTimestamp }
            return merged.take(limit)
        }

        private fun interleave(home: kotlin.collections.List<Note>, extra: kotlin.collections.List<Note>, limit: Int, sort: FeedSortMode): kotlin.collections.List<Note> {
            val listIds = home.map { it.listId }.toMutableSet()
            val originals = home.map { it.id }.toMutableSet()
            val merged = home.toMutableList()
            for (note in extra) {
                if (note.id !in originals && listIds.add(note.listId)) {
                    originals.add(note.id)
                    merged.add(note)
                }
            }
            when (sort) {
                FeedSortMode.LATEST -> merged.sortByDescending { it.displayTimestamp }
                FeedSortMode.MOST_INTERACTED -> merged.sortWith { lhs, rhs ->
                    val l = lhs.reactionCount + lhs.repostCount + lhs.replyCount + lhs.zapCount
                    val r = rhs.reactionCount + rhs.repostCount + rhs.replyCount + rhs.zapCount
                    if (l == r) rhs.displayTimestamp.compareTo(lhs.displayTimestamp) else r.compareTo(l)
                }
            }
            return merged.take(limit)
        }
    }

    private val authors: kotlin.collections.List<String>?
        get() = (source as? FeedSource.List)?.set?.pubkeys

    val followedTopics: kotlin.collections.List<String> get() = HashtagFollowService.tags

    private val activeTopics: kotlin.collections.List<String>
        get() = when (val s = source) {
            is FeedSource.Topic -> listOf(s.tag)
            FeedSource.Topics -> followedTopics
            FeedSource.Following -> if (includeTopics) followedTopics else emptyList()
            else -> emptyList()
        }

    fun updateSort(value: FeedSortMode) {
        if (value == sort) return
        sort = value
        Prefs.set("feed_sort_mode", value.raw)
        resetForContextChange()
    }

    fun updateShowReplies(value: Boolean) {
        if (value == showReplies) return
        showReplies = value
        Prefs.set("feed_show_replies", value)
        resetForContextChange()
    }

    fun updateShowReposts(value: Boolean) {
        if (value == showReposts) return
        showReposts = value
        Prefs.set("feed_show_reposts", value)
        resetForContextChange()
    }

    val hasNoteFilters: Boolean get() = !source.isCurated && !source.isTopicFeed

    fun updateIncludeTopics(value: Boolean) {
        if (value == includeTopics) return
        includeTopics = value
        Prefs.set("feed_include_topics", value)
        if (source != FeedSource.Following) return
        resetForContextChange()
        if (value) syncTopicsInBackground()
    }

    private suspend fun query(limit: Int): kotlin.collections.List<Note> {
        val current = source
        if (current.isExplore) return exploreNotes(force = false)
        if (current is FeedSource.Discover) return discoverNotes(current.feed, force = false)
        val topics = activeTopics
        if (current.isTopicFeed) return topicNotes(topics, limit, includeReplies = true)
        val home = NoteRepository.feed(authors, limit, sort, showReplies)
        if (topics.isEmpty()) return home
        val extra = topicNotes(topics, limit, includeReplies = false)
        return interleave(home, extra, limit, sort)
    }

    private suspend fun exploreNotes(force: Boolean): kotlin.collections.List<Note> {
        if (exploreHidden == null) exploreHidden = ExploreSeenStore.snapshot()
        val hidden = exploreHidden ?: emptyMap()
        val pool = TrendingService.explorePool(force)
        val ids = pool.filter { it !in hidden }.toMutableList()
        if (ids.size < EXPLORE_MINIMUM_FRESH) ids += pool.filter { it in hidden }.sortedBy { hidden[it] ?: 0.0 }
        val byId = NoteRepository.notes(ids).associateBy { it.id }
        return ExploreSafety.screen(ids.mapNotNull { byId[it] })
    }

    private suspend fun discoverNotes(feed: DiscoverFeed, force: Boolean): kotlin.collections.List<Note> {
        if (!force) discoverCache[feed.id]?.let { return it }
        val fetched = ExploreService.feedNotes(feed) ?: return discoverCache[feed.id] ?: emptyList()
        val notes = ExploreSafety.screen(fetched)
        discoverCache[feed.id] = notes
        return notes
    }

    private suspend fun syncTopics(tags: kotlin.collections.List<String>, force: Boolean = false) = coroutineScope {
        tags.map { tag -> async { SyncService.syncHashtag(tag, force) } }.awaitAll()
    }

    private fun syncTopicsInBackground() {
        val tags = activeTopics
        if (tags.isEmpty()) return
        val generation = this.generation
        viewModelScope.launch {
            syncTopics(tags)
            if (generation == this@FeedViewModel.generation && source.isTopicFeed && notes.isEmpty()) isSyncing = false
        }
    }

    private suspend fun fetchOlder(until: Long): Int {
        var received = 0
        if (!source.isTopicFeed) {
            var pubkeys = authors ?: emptyList()
            if (pubkeys.isEmpty()) Session.pubkey?.let { me -> pubkeys = (NoteRepository.following() + me).distinct() }
            received += NoteRepository.fetchOlder(pubkeys, until)
        }
        for (tag in activeTopics) received += NoteRepository.fetchOlderHashtag(tag, until)
        return received
    }

    fun topicsChanged() {
        val tags = followedTopics
        when (val s = source) {
            is FeedSource.Topic -> if (s.tag !in tags) select(FeedSource.Following)
            FeedSource.Topics -> if (tags.isEmpty()) select(FeedSource.Following) else refreshTopicsQuietly()
            FeedSource.Following -> if (includeTopics) refreshTopicsQuietly()
            else -> Unit
        }
    }

    private fun refreshTopicsQuietly() {
        val tags = activeTopics
        viewModelScope.launch {
            reload()
            syncTopics(tags)
        }
    }

    fun start() {
        if (graceJob != null) return
        if (Session.isNewAccount) isSyncing = false
        graceJob = viewModelScope.launch {
            delay(8000)
            isSyncing = false
        }
        syncTopicsInBackground()
    }

    suspend fun reload() {
        val generation = this.generation
        delay(120)
        if (generation != this.generation) return
        val result = query(limit)
        if (generation != this.generation) return
        apply(result)
    }

    private fun apply(result: kotlin.collections.List<Note>) {
        fetched = result
        val visible = filtered(result)
        val me = Session.pubkey
        if (notes.isEmpty() || acceptNext || source.isCurated) {
            acceptNext = false
            show(visible)
        } else {
            val displayedIds = notes.map { it.listId }.toSet()
            var others = 0
            var ownNew = false
            for (note in visible) {
                if (note.displayTimestamp > latestDisplayed && note.listId !in displayedIds) {
                    if ((if (note.isRepost) note.repostedBy else note.pubkey) == me) ownNew = true else others += 1
                }
            }
            if (others > 0) {
                notes = visible.filter { note ->
                    note.displayTimestamp <= latestDisplayed || note.listId in displayedIds || (if (note.isRepost) note.repostedBy else note.pubkey) == me
                }
                pendingCount = others
            } else {
                if (ownNew) latestDisplayed = maxOf(latestDisplayed, visible.maxOfOrNull { it.displayTimestamp } ?: 0)
                notes = visible
                pendingCount = 0
            }
        }
        if (result.isNotEmpty()) isSyncing = false
        hasLoaded = true
        canLoadMore = !source.isCurated && (!exhaustedRelays || result.size >= limit)
        afterLoad(visible)
    }

    private fun show(visible: kotlin.collections.List<Note>) {
        notes = visible
        latestDisplayed = visible.maxOfOrNull { it.displayTimestamp } ?: 0
        pendingCount = 0
    }

    private fun afterLoad(visible: kotlin.collections.List<Note>) {
        NoteInteractionStore.seed(visible)
        val fresh = visible.filter { it.listId !in prefetched }
        if (fresh.isEmpty()) return
        prefetched.addAll(fresh.map { it.listId })
        NoteInteractionStore.requestCounts(fresh.map { it.id })
        NoteRepository.prefetchEmbedded(fresh)
        val pubkeys = (fresh.map { it.pubkey } + fresh.mapNotNull { it.repostedBy }).toSet()
        viewModelScope.launch {
            NoteContentCache.warm(fresh)
            ProfileCache.load(pubkeys.filter { ProfileCache.profile(it) == null })
        }
    }

    fun filtered(list: kotlin.collections.List<Note>): kotlin.collections.List<Note> {
        val mutedPubkeys = Session.mutedPubkeys.toSet()
        val words = Session.mutedWords.map { it.lowercase() }.filter { it.isNotEmpty() }
        val deleted = NoteInteractionStore.deletedIds
        val hidesReposts = hasNoteFilters && !showReposts
        val seen = HashSet<String>()
        return list.filter { note ->
            if (note.id in deleted || !seen.add(note.listId)) return@filter false
            if (hidesReposts && note.isRepost) return@filter false
            if (MuteService.hides(note) && !isSelectedTopic(note)) return@filter false
            if (note.pubkey in mutedPubkeys) return@filter false
            if (note.repostedBy?.let { it in mutedPubkeys } == true) return@filter false
            if (words.isNotEmpty()) {
                val content = note.content.lowercase()
                if (words.any { content.contains(it) }) return@filter false
            }
            true
        }
    }

    private fun isSelectedTopic(note: Note): Boolean {
        val tag = (source as? FeedSource.Topic)?.tag ?: return false
        return !MuteService.isThreadMuted(note.rootId ?: note.id) && note.hashtags.any { it.lowercase() == tag.lowercase() }
    }

    fun refilter() {
        notes = filtered(notes)
    }

    fun acceptPending() {
        val visible = filtered(fetched)
        show(visible)
        afterLoad(visible)
        scrollToTopToken += 1
    }

    suspend fun refresh() {
        acceptNext = true
        exhaustedRelays = false
        when (val s = source) {
            FeedSource.Explore -> {
                exploreHidden = ExploreSeenStore.snapshot()
                TrendingService.explorePool(force = true)
            }
            is FeedSource.Discover -> discoverNotes(s.feed, force = true)
            FeedSource.Following -> coroutineScope {
                val feed = async { SyncService.syncFeed(force = true) }
                val topics = async { syncTopics(activeTopics, force = true) }
                feed.await()
                topics.await()
            }
            is FeedSource.List -> SyncService.syncListFeed(s.set.pubkeys, force = true)
            is FeedSource.Topic, FeedSource.Topics -> syncTopics(activeTopics, force = true)
        }
        acceptNext = true
        reload()
        NoteInteractionStore.requestCounts(notes.take(40).map { it.id })
    }

    fun loadMoreIfNeeded(note: Note) {
        ExploreSeenStore.mark(note.id)
        if (!canLoadMore || isLoadingMore) return
        val index = notes.indexOfFirst { it.listId == note.listId }
        if (index < 0 || index < notes.size - 6) return
        viewModelScope.launch { loadMore() }
    }

    suspend fun loadMore() {
        if (!canLoadMore || isLoadingMore || source.isCurated) return
        isLoadingMore = true
        try {
            val generation = this.generation
            val previousCount = fetched.size
            limit += PAGE_SIZE
            var result = query(limit)
            if (generation != this.generation) return
            if (result.size <= previousCount || result.size < limit) {
                val oldest = (result.ifEmpty { notes }).map { it.displayTimestamp }.filter { it > 0 }.minOrNull() ?: TimeFormat.now
                val received = fetchOlder(oldest)
                if (generation != this.generation) return
                if (received == 0 && SyncService.hasConnectedRelays()) exhaustedRelays = true
                result = query(limit)
                if (generation != this.generation) return
            }
            mergeOlder(result)
        } finally {
            isLoadingMore = false
        }
    }

    private fun mergeOlder(result: kotlin.collections.List<Note>) {
        fetched = result
        val visible = filtered(result)
        val displayedIds = notes.map { it.listId }.toSet()
        val additions = visible.filter { it.listId !in displayedIds && it.displayTimestamp <= latestDisplayed }
        notes = if (sort == FeedSortMode.MOST_INTERACTED) visible else notes + additions
        canLoadMore = !(additions.isEmpty() && exhaustedRelays)
        afterLoad(additions)
    }

    fun select(newSource: FeedSource) {
        if (newSource == source) return
        source = newSource
        resetForContextChange()
        when (newSource) {
            is FeedSource.List -> viewModelScope.launch { SyncService.syncListFeed(newSource.set.pubkeys) }
            is FeedSource.Topic, FeedSource.Topics -> syncTopicsInBackground()
            FeedSource.Following -> if (includeTopics) syncTopicsInBackground()
            else -> Unit
        }
    }

    private fun resetForContextChange() {
        generation += 1
        notes = emptyList()
        fetched = emptyList()
        pendingCount = 0
        limit = PAGE_SIZE
        latestDisplayed = 0
        acceptNext = true
        exhaustedRelays = false
        canLoadMore = true
        hasLoaded = false
        isSyncing = true
        graceJob?.cancel()
        graceJob = viewModelScope.launch {
            delay(6000)
            isSyncing = false
        }
        reloadJob?.cancel()
        reloadJob = viewModelScope.launch { reload() }
    }

    fun pinnedFeedsChanged(pinned: kotlin.collections.List<DiscoverFeed>) {
        val current = source as? FeedSource.Discover ?: return
        if (pinned.any { it.id == current.feed.id }) return
        select(FeedSource.Explore)
    }

    suspend fun loadLists() {
        val me = Session.pubkey ?: return
        val own = NoteRepository.followSets(listOf(me), 100)
        val favorites = Prefs.stringList("favorite_follow_set_ids") ?: emptyList()
        val result = own.filter { it.pubkeys.isNotEmpty() }.toMutableList()
        if (favorites.isNotEmpty()) {
            val follows = NoteRepository.following()
            val others = NoteRepository.followSets(follows, 500)
            for (id in favorites) {
                val set = (own + others).firstOrNull { it.id == id || it.dTag == id } ?: continue
                if (result.none { it.id == set.id } && set.pubkeys.isNotEmpty()) result.add(set)
            }
        }
        lists = result
        val active = source as? FeedSource.List ?: return
        val updated = result.firstOrNull { it.id == active.set.id }
        if (updated != null) {
            if (updated != active.set) source = FeedSource.List(updated)
        } else {
            select(FeedSource.Following)
        }
    }
}
