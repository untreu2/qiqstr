package me.untreu.qiqstr.ui.feed

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.outlined.Tag
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.data.services.HashtagFollowService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.ui.note.NoteContentCache
import me.untreu.qiqstr.ui.note.NoteInteractionStore
import me.untreu.qiqstr.ui.note.NoteList
import me.untreu.qiqstr.ui.note.NoteRepository

class HashtagFeedViewModel(rawTag: String) : ViewModel() {
    val tag: String = rawTag.removePrefix("#")
    var notes by mutableStateOf<List<Note>>(emptyList())
        private set
    var hasLoaded by mutableStateOf(false)
        private set
    var isSyncing by mutableStateOf(true)
        private set
    var isLoadingMore by mutableStateOf(false)
        private set
    var canLoadMore by mutableStateOf(true)
        private set
    var recentCount by mutableStateOf<Int?>(null)
        private set
    var followFeedback by mutableIntStateOf(0)
        private set
    private var limit = FeedViewModel.PAGE_SIZE
    private val seen = HashSet<String>()
    private var exhausted = false

    val isFollowing: Boolean get() = HashtagFollowService.isFollowing(tag)
    val isFollowPending: Boolean get() = HashtagFollowService.isPending(tag)

    fun toggleFollow() {
        followFeedback += 1
        viewModelScope.launch {
            try { HashtagFollowService.toggle(tag) } catch (error: Throwable) { ToastCenter.error(error) }
        }
    }

    suspend fun sync(force: Boolean = false) {
        isSyncing = true
        SyncService.syncHashtag(tag, force)
        isSyncing = false
        reload()
    }

    suspend fun loadRecentCount() {
        recentCount = HashtagFollowService.recentCount(tag)
    }

    suspend fun reload() {
        delay(120)
        apply(NoteRepository.hashtag(tag, limit))
    }

    private fun apply(result: List<Note>) {
        val muted = Session.mutedPubkeys.toSet()
        val words = Session.mutedWords.map { it.lowercase() }.filter { it.isNotEmpty() }
        val deleted = NoteInteractionStore.deletedIds
        val ids = HashSet<String>()
        notes = result.filter { note ->
            if (!ids.add(note.listId) || note.id in deleted || note.pubkey in muted) return@filter false
            val content = note.content.lowercase()
            words.none { content.contains(it) }
        }
        hasLoaded = true
        canLoadMore = !exhausted || result.size >= limit
        val fresh = notes.filter { it.listId !in seen }
        seen.addAll(fresh.map { it.listId })
        if (fresh.isEmpty()) return
        NoteInteractionStore.seed(fresh)
        NoteInteractionStore.requestCounts(fresh.map { it.id })
        NoteRepository.prefetchEmbedded(fresh)
        viewModelScope.launch {
            NoteContentCache.warm(fresh)
            ProfileCache.load(fresh.map { it.pubkey }.distinct().filter { ProfileCache.profile(it) == null })
        }
    }

    fun loadMoreIfNeeded(note: Note) {
        if (!canLoadMore || isLoadingMore) return
        val index = notes.indexOfFirst { it.listId == note.listId }
        if (index < 0 || index < notes.size - 6) return
        viewModelScope.launch { loadMore() }
    }

    suspend fun loadMore() {
        if (!canLoadMore || isLoadingMore) return
        isLoadingMore = true
        try {
            val previous = notes.size
            limit += FeedViewModel.PAGE_SIZE
            var result = NoteRepository.hashtag(tag, limit)
            if (result.size <= previous || result.size < limit) {
                val oldest = result.ifEmpty { notes }.map { it.createdAt }.filter { it > 0 }.minOrNull() ?: TimeFormat.now
                if (NoteRepository.fetchOlderHashtag(tag, oldest) == 0) exhausted = true
                result = NoteRepository.hashtag(tag, limit)
            }
            apply(result)
            if (notes.size <= previous) canLoadMore = !exhausted
        } finally {
            isLoadingMore = false
        }
    }
}

@Composable
fun HashtagFeedScreen(tag: String) {
    val model: HashtagFeedViewModel = viewModel(key = "hashtag-$tag") { HashtagFeedViewModel(tag) }
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    var isRefreshing by remember { mutableStateOf(false) }
    val scrollBehavior = TopAppBarDefaults.enterAlwaysScrollBehavior()
    LaunchedEffect(Unit) { model.sync() }
    LaunchedEffect(DataBus.feedVersion) {
        model.reload()
        model.loadRecentCount()
    }
    LaunchedEffect(model.followFeedback) { if (model.followFeedback > 0) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove) }
    val refresh: () -> Unit = {
        scope.launch {
            isRefreshing = true
            try { model.sync(force = true) } finally { isRefreshing = false }
        }
    }
    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = AppColors.background,
        topBar = {
            CenterAlignedTopAppBar(
                navigationIcon = { IconButton(onClick = { Router.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } },
                title = {
                    Surface(
                        onClick = { scope.launch { if (model.notes.isNotEmpty()) listState.animateScrollToItem(0) } },
                        shape = CircleShape,
                        color = AppColors.textPrimary,
                        contentColor = AppColors.background,
                        modifier = Modifier.testTag("hashtag-title"),
                    ) {
                        Text("#${model.tag}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp))
                    }
                },
                actions = {
                    Box(Modifier.padding(end = 8.dp)) {
                        HashtagFollowButton(model.isFollowing, model.isFollowPending, model::toggleFollow)
                    }
                },
                scrollBehavior = scrollBehavior,
                colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = AppColors.background, scrolledContainerColor = AppColors.background),
            )
        },
    ) { padding ->
        PullToRefreshBox(isRefreshing = isRefreshing, onRefresh = refresh, modifier = Modifier.fillMaxSize().padding(padding)) {
            NoteList(
                notes = model.notes,
                state = listState,
                isLoadingMore = model.isLoadingMore,
                onAppearNote = model::loadMoreIfNeeded,
                modifier = Modifier.testTag("hashtag-list"),
            ) {
                val count = model.recentCount
                if (count != null && count > 0 && model.notes.isNotEmpty()) item(key = "recent-count") { HashtagFeedHeader(count) }
            }
            if (model.notes.isEmpty()) {
                if (!model.hasLoaded || model.isSyncing) {
                    CircularProgressIndicator(Modifier.align(Alignment.Center), color = AppColors.textPrimary)
                } else {
                    EmptyStateView(Icons.Outlined.Tag, L("noNotesYet"), actionTitle = L("refresh"), modifier = Modifier.align(Alignment.Center), action = refresh)
                }
            }
        }
    }
}

@Composable
fun HashtagFeedHeader(count: Int) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp).testTag("hashtag-recent-count"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.AutoMirrored.Filled.TrendingUp, null, Modifier.size(18.dp), tint = AppColors.textSecondary)
        Text(L("feedTopicPostsLastDay", "count" to count), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
    }
}

@Composable
fun HashtagFollowButton(isFollowing: Boolean, isPending: Boolean, onClick: () -> Unit) {
    val modifier = Modifier.testTag("hashtag-follow")
    if (isFollowing) {
        OutlinedButton(onClick = onClick, enabled = !isPending, shape = CircleShape, modifier = modifier) {
            Text(L("following"), fontWeight = FontWeight.SemiBold, color = AppColors.textPrimary)
        }
    } else {
        Button(
            onClick = onClick,
            enabled = !isPending,
            shape = CircleShape,
            colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
            modifier = modifier,
        ) { Text(L("follow"), fontWeight = FontWeight.SemiBold) }
    }
}
