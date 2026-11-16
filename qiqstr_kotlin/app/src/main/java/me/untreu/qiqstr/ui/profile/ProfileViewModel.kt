package me.untreu.qiqstr.ui.profile

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.bridge.isHex
import me.untreu.qiqstr.data.services.BadgeService
import me.untreu.qiqstr.data.services.PinnedNotesService
import me.untreu.qiqstr.data.services.ProfileBadge
import me.untreu.qiqstr.data.services.ProfileCountsStore
import me.untreu.qiqstr.data.services.WebOfTrustService
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile

enum class ProfileTab(val raw: String) {
    NOTES("notes"), REPLIES("replies"), PHOTOS("photos"), LIKES("likes"), ARTICLES("articles");

    val title: String get() = if (this == PHOTOS) L("media") else L(raw)
}

class ProfileViewModel(val pubkey: String) : ViewModel() {
    var profile by mutableStateOf(ProfileCache.profile(pubkey) ?: Profile(pubkey))
        private set
    var nip05Verified by mutableStateOf(false)
        private set
    var followingCount by mutableStateOf(ProfileCountsStore.counts(pubkey)?.following)
        private set
    var followerCount by mutableStateOf(ProfileCountsStore.counts(pubkey)?.followers)
        private set
    var followsMe by mutableStateOf(false)
        private set
    var followScore by mutableStateOf<FollowScore?>(null)
        private set
    var mutualFollowers by mutableStateOf<List<String>>(emptyList())
        private set
    var badges by mutableStateOf<List<ProfileBadge>>(BadgeService.cached(pubkey) ?: emptyList())
        private set
    var articles by mutableStateOf<List<me.untreu.qiqstr.domain.Article>>(emptyList())
        private set
    private var articlesLimit = 50
    var canLoadMoreArticles by mutableStateOf(false)
        private set
    val tabs: List<ProfileTab> get() = ProfileTab.entries.filter { it != ProfileTab.ARTICLES || isMe || articles.isNotEmpty() }
    suspend fun reloadArticles() {
        articles = me.untreu.qiqstr.ui.articles.ArticleService.articles(listOf(pubkey), articlesLimit)
        canLoadMoreArticles = articles.size >= articlesLimit
    }
    private suspend fun syncArticles(force: Boolean) {
        me.untreu.qiqstr.ui.articles.ArticleService.sync(listOf(pubkey), force)
        reloadArticles()
    }
    var media by mutableStateOf<List<ProfileMediaEntry>>(emptyList())
        private set

    var notes by mutableStateOf<List<Note>>(emptyList())
        private set
    var replies by mutableStateOf<List<Note>>(emptyList())
        private set
    var likes by mutableStateOf<List<Note>>(emptyList())
        private set
    var pinned by mutableStateOf<List<Note>>(emptyList())
        private set
    private var pinnedIds: List<String> = emptyList()

    var isSyncingNotes by mutableStateOf(true)
        private set
    var hasLoadedNotes by mutableStateOf(false)
        private set
    var hasLoadedLikes by mutableStateOf(false)
        private set
    var canLoadMoreNotes by mutableStateOf(false)
        private set
    var canLoadMoreReplies by mutableStateOf(false)
        private set
    var canLoadMoreLikes by mutableStateOf(false)
        private set
    var isLoadingMore by mutableStateOf(false)
        private set
    var loadMoreCount by mutableIntStateOf(0)
        private set
    var isRefreshing by mutableStateOf(false)
        private set

    var tab by mutableStateOf(ProfileTab.NOTES)

    private var notesLimit = ProfileDataSource.PAGE_SIZE
    private var repliesLimit = ProfileDataSource.PAGE_SIZE
    private var reactionLimit = ProfileDataSource.PAGE_SIZE * 3
    private val requestedLikeIds = HashSet<String>()
    private val requestedPinnedIds = HashSet<String>()
    private var started = false
    private var likesExhausted = false
    private var checkedNip05: String? = null
    private var nip05Job: Job? = null

    val isMe: Boolean get() = Session.pubkey == pubkey
    val npub: String get() = Nip19.npub(pubkey) ?: pubkey
    val profileLink: String get() = "https://njump.me/$npub"
    val isValidPubkey: Boolean get() = pubkey.length == 64 && pubkey.all { it.isHex() }

    val displayName: String
        get() {
            if (profile.displayName.isNotEmpty()) return profile.displayName
            if (profile.name.isNotEmpty()) return profile.name
            Nip05Verifier.parts(profile.nip05)?.let { if (it.name != "_") return it.name }
            return L("anonymous")
        }

    val handle: String?
        get() {
            if (profile.name.isEmpty() || profile.displayName.isEmpty() || profile.name == profile.displayName) return null
            return "@${profile.name}"
        }

    val websiteURL: String?
        get() {
            val raw = profile.website.trim()
            if (raw.isEmpty()) return null
            return if (raw.startsWith("http://") || raw.startsWith("https://")) raw else "https://$raw"
        }

    val visibleNotes: List<Note>
        get() {
            val pinnedSet = pinned.map { it.id }.toSet()
            val deleted = me.untreu.qiqstr.ui.note.NoteInteractionStore.deletedIds
            return notes.filter { (it.isRepost || it.id !in pinnedSet) && it.id !in deleted }
        }

    val canLoadMoreCurrent: Boolean
        get() = when (tab) {
            ProfileTab.NOTES, ProfileTab.PHOTOS -> canLoadMoreNotes
            ProfileTab.REPLIES -> canLoadMoreReplies
            ProfileTab.LIKES -> canLoadMoreLikes
            ProfileTab.ARTICLES -> canLoadMoreArticles
        }

    fun start() {
        if (started || !isValidPubkey) return
        started = true
        viewModelScope.launch {
            reloadProfile()
            coroutineScope {
                launch { reloadNotes() }
                launch { reloadArticles() }
                launch { loadPinned(remote = false) }
                launch { loadFollowing(sync = false) }
                launch { loadBadges(remote = false) }
            }
            launch { syncAll(force = false) }
        }
    }

    fun refresh() {
        if (!isValidPubkey || isRefreshing) return
        isRefreshing = true
        viewModelScope.launch {
            val job = launch { syncAll(force = true) }
            withTimeoutOrNull(4000) { job.join() }
            isRefreshing = false
        }
    }

    private suspend fun syncAll(force: Boolean) = coroutineScope {
        launch { syncArticles(force) }
        launch { syncProfile(force) }
        launch { syncNotes(force) }
        launch { syncLikes() }
        launch { loadPinned(remote = true) }
        launch { loadCounts() }
        launch { loadFollowScore() }
        launch { loadBadges(remote = true) }
    }

    private suspend fun syncProfile(force: Boolean) {
        SyncService.syncProfile(pubkey, force)
        reloadProfile()
    }

    private suspend fun syncNotes(force: Boolean) {
        isSyncingNotes = true
        SyncService.syncProfileNotes(pubkey, force)
        reloadNotes()
        isSyncingNotes = false
    }

    private suspend fun syncLikes() {
        SyncService.syncProfileReactions(pubkey)
        reloadLikes()
    }

    suspend fun reloadProfile() {
        ProfileDataSource.profile(pubkey)?.let { fresh ->
            if (fresh != profile) profile = fresh
            if (ProfileCache.profile(pubkey) != fresh) ProfileCache.set(fresh)
        }
        scheduleNip05Check()
    }

    private fun scheduleNip05Check() {
        val nip05 = profile.nip05
        if (nip05 == checkedNip05) return
        checkedNip05 = nip05
        nip05Job?.cancel()
        nip05Job = viewModelScope.launch {
            if (nip05.isEmpty()) { nip05Verified = false; return@launch }
            val ok = Nip05Verifier.verify(nip05, pubkey)
            if (profile.nip05 == nip05) nip05Verified = ok
        }
    }

    suspend fun reloadNotes() {
        val (newNotes, newReplies) = coroutineScope {
            val n = async { ProfileDataSource.notes(pubkey, notesLimit) }
            val r = async { ProfileDataSource.replies(pubkey, repliesLimit) }
            n.await() to r.await()
        }
        if (newNotes != notes) notes = newNotes
        if (newReplies != replies) replies = newReplies
        rebuildMedia()
        canLoadMoreNotes = newNotes.size >= notesLimit
        canLoadMoreReplies = newReplies.size >= repliesLimit
        hasLoadedNotes = true
        preloadAuthors(newNotes + newReplies)
    }

    private suspend fun rebuildMedia() {
        val own = (notes + replies).filter { !it.isRepost && it.pubkey == pubkey }.sortedByDescending { it.createdAt }
        val result = withContext(Dispatchers.Default) {
            val seen = HashSet<String>()
            own.filter { it.contentWarning == null || WebOfTrustService.showsSensitiveContent }.flatMap { note -> ProfileMediaEntry.extract(note).filter { seen.add(it.url) } }
        }
        if (result != media) media = result
    }

    suspend fun reloadLikes() {
        val loaded = ProfileDataSource.likes(pubkey, reactionLimit)
        if (loaded != likes) likes = loaded
        hasLoadedLikes = true
        preloadAuthors(loaded)
        val ids = ProfileDataSource.likedNoteIds(pubkey, reactionLimit)
        canLoadMoreLikes = !likesExhausted && ids.isNotEmpty()
        val have = loaded.map { it.id }.toSet()
        val missing = ids.filter { it !in have && it !in requestedLikeIds }
        if (missing.isEmpty()) return
        requestedLikeIds.addAll(missing)
        if (ProfileDataSource.fetchMissingNotes(missing)) {
            val refreshed = ProfileDataSource.likes(pubkey, reactionLimit)
            if (refreshed != likes) likes = refreshed
            preloadAuthors(refreshed)
        }
    }

    suspend fun loadPinned(remote: Boolean) {
        val ids = if (remote) PinnedNotesService.load(pubkey) else PinnedNotesService.cachedIds(pubkey)
        applyPinned(ids)
    }

    suspend fun pinnedChanged() {
        if (!isMe) return
        applyPinned(PinnedNotesService.pinnedIds)
    }

    private suspend fun applyPinned(ids: List<String>) {
        pinnedIds = ids
        if (ids.isEmpty()) { pinned = emptyList(); return }
        var found = ProfileDataSource.notes(ids, owner = pubkey)
        val missing = ids.filter { id -> found.none { it.id == id } && id !in requestedPinnedIds }
        if (missing.isNotEmpty()) {
            requestedPinnedIds.addAll(missing)
            if (ProfileDataSource.fetchMissingNotes(missing)) found = ProfileDataSource.notes(ids, owner = pubkey)
        }
        if (pinnedIds != ids) return
        val order = ids.withIndex().associate { it.value to it.index }
        val sorted = found.filter { it.id in order }.sortedByDescending { order[it.id] ?: 0 }
        if (sorted != pinned) pinned = sorted
        preloadAuthors(sorted)
    }

    suspend fun loadFollowing(sync: Boolean) {
        if (sync) SyncService.syncFollowingList(pubkey, force = true)
        val list = ProfileDataSource.following(pubkey)
        if (list.isNotEmpty() || sync) {
            followingCount = list.size
            ProfileCountsStore.update(pubkey, following = list.size)
        }
        val me = Session.pubkey
        if (me != null && me != pubkey) followsMe = me in list
    }

    private suspend fun loadCounts() = coroutineScope {
        launch {
            ProfileDataSource.followerCount(pubkey)?.let { count ->
                followerCount = count
                ProfileCountsStore.update(pubkey, followers = count)
            }
        }
        launch {
            loadFollowing(sync = false)
            loadFollowing(sync = true)
        }
    }

    suspend fun loadFollowScore() {
        if (isMe) { followScore = null; return }
        val score = ProfileDataSource.followScore(pubkey)
        if (score != followScore) followScore = score
        if (score == null || score.count <= 0) { mutualFollowers = emptyList(); return }
        val mutuals = ProfileDataSource.mutualFollowers(pubkey)
        if (mutuals != mutualFollowers) mutualFollowers = mutuals
        val missing = mutuals.take(40).filter { ProfileCache.profile(it) == null }
        if (missing.isNotEmpty()) ProfileCache.load(missing)
    }

    suspend fun loadBadges(remote: Boolean) {
        val loaded = if (remote) BadgeService.refresh(pubkey) else BadgeService.local(pubkey)
        if (!remote && loaded.isEmpty()) return
        if (loaded != badges) badges = loaded
    }

    private suspend fun fetchOlderFromRelays(before: List<Note>): Boolean {
        val oldest = before.map { it.displayTimestamp }.filter { it > 0 }.minOrNull() ?: TimeFormat.now
        return ProfileDataSource.fetchOlder(listOf(pubkey), oldest) > 0
    }

    fun loadMore() {
        if (isLoadingMore) return
        isLoadingMore = true
        viewModelScope.launch {
            try {
                val page = ProfileDataSource.PAGE_SIZE
                when (tab) {
                    ProfileTab.ARTICLES -> {
                        if (!canLoadMoreArticles) return@launch
                        val previous = articles.size
                        articlesLimit += page
                        reloadArticles()
                        if (articles.size <= previous) {
                            me.untreu.qiqstr.ui.articles.ArticleService.fetchOlder(listOf(pubkey), articles.lastOrNull()?.createdAt ?: TimeFormat.now)
                            reloadArticles()
                        }
                        if (articles.size <= previous) canLoadMoreArticles = false
                    }
                    ProfileTab.NOTES, ProfileTab.PHOTOS -> {
                        if (!canLoadMoreNotes) return@launch
                        notesLimit += page
                        val previous = notes.size
                        reloadNotes()
                        if (notes.size <= previous && fetchOlderFromRelays(notes)) reloadNotes()
                        if (notes.size <= previous) canLoadMoreNotes = false
                    }
                    ProfileTab.REPLIES -> {
                        if (!canLoadMoreReplies) return@launch
                        repliesLimit += page
                        val previous = replies.size
                        reloadNotes()
                        if (replies.size <= previous && fetchOlderFromRelays(replies)) reloadNotes()
                        if (replies.size <= previous) canLoadMoreReplies = false
                    }
                    ProfileTab.LIKES -> {
                        if (!canLoadMoreLikes) return@launch
                        val oldest = ProfileDataSource.oldestReactionTimestamp(pubkey, reactionLimit)
                        reactionLimit += page * 3
                        val localIds = ProfileDataSource.likedNoteIds(pubkey, reactionLimit)
                        if (localIds.size < reactionLimit && ProfileDataSource.syncOlderReactions(pubkey, oldest) == 0) likesExhausted = true
                        reloadLikes()
                    }
                }
            } finally {
                isLoadingMore = false
                loadMoreCount += 1
            }
        }
    }

    private fun preloadAuthors(notes: List<Note>) {
        val pubkeys = notes.flatMap { listOf(it.pubkey, it.repostedBy ?: "") }
            .filter { it.isNotEmpty() && ProfileCache.profile(it) == null }.distinct()
        if (pubkeys.isEmpty()) return
        viewModelScope.launch { ProfileCache.load(pubkeys) }
    }
}
