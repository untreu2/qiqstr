package me.untreu.qiqstr.ui.bookmarks

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.BookmarkRemove
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.LoadingView
import me.untreu.qiqstr.data.services.BookmarkService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.ui.note.NoteRow
import me.untreu.qiqstr.ui.profile.ProfileSearchField

class BookmarksViewModel : ViewModel() {
    var notes by mutableStateOf<List<Note>>(emptyList())
        private set
    var isLoading by mutableStateOf(true)
        private set
    var isRefreshing by mutableStateOf(false)
        private set
    var removing by mutableStateOf<Set<String>>(emptySet())
        private set
    var removedCount by mutableIntStateOf(0)
        private set
    private var loaded = false

    fun load() {
        if (loaded) return
        loaded = true
        viewModelScope.launch {
            if (!BookmarkService.isLoaded) BookmarkService.load()
            reload()
        }
    }

    fun refresh() {
        if (isRefreshing) return
        isRefreshing = true
        viewModelScope.launch {
            BookmarkService.refresh()
            reload()
            isRefreshing = false
        }
    }

    suspend fun reload() {
        val ids = BookmarkService.bookmarkedIds.toSet()
        notes = notes.filter { it.id in ids }
        notes = BookmarkService.notes()
        isLoading = false
    }

    fun remove(note: Note) {
        removing = removing + note.id
        val snapshot = notes
        notes = notes.filter { it.id != note.id }
        viewModelScope.launch {
            try {
                BookmarkService.remove(note.id)
                removedCount += 1
                ToastCenter.show(L("bookmarkRemoved"), ToastStyle.SUCCESS)
            } catch (error: Throwable) {
                notes = snapshot
                ToastCenter.error(error)
            } finally {
                removing = removing - note.id
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BookmarksScreen() {
    val model = viewModel { BookmarksViewModel() }
    val haptics = LocalHapticFeedback.current
    var query by rememberSaveable { mutableStateOf("") }
    val scroll = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    LaunchedEffect(Unit) { model.load() }
    LaunchedEffect(BookmarkService.bookmarkedIds) { if (!model.isLoading) model.reload() }
    LaunchedEffect(model.removedCount) { if (model.removedCount > 0) haptics.performHapticFeedback(HapticFeedbackType.LongPress) }
    val visible = run {
        val q = query.trim()
        val deleted = me.untreu.qiqstr.ui.note.NoteInteractionStore.deletedIds
        val notes = model.notes.filter { it.id !in deleted }
        if (q.isEmpty()) notes
        else notes.filter { note ->
            note.content.contains(q, ignoreCase = true) ||
                (note.authorName ?: "").contains(q, ignoreCase = true) ||
                (ProfileCache.profiles[note.pubkey]?.bestName?.contains(q, ignoreCase = true) ?: false)
        }
    }

    Scaffold(
        modifier = Modifier.nestedScroll(scroll.nestedScrollConnection),
        containerColor = AppColors.background,
        topBar = {
            LargeTopAppBar(
                title = { Text(L("bookmarksTitle")) },
                navigationIcon = { IconButton(onClick = { Router.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } },
                scrollBehavior = scroll,
                colors = TopAppBarDefaults.largeTopAppBarColors(containerColor = AppColors.background),
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            ProfileSearchField(query, { query = it }, L("search"), tag = "bookmarks-search")
            PullToRefreshBox(isRefreshing = model.isRefreshing, onRefresh = model::refresh, modifier = Modifier.fillMaxSize()) {
                when {
                    model.notes.isEmpty() && (model.isLoading || BookmarkService.isSyncing) -> LoadingView()
                    model.notes.isEmpty() -> Box(Modifier.fillMaxSize()) {
                        EmptyStateView(icon = Icons.Outlined.BookmarkBorder, title = L("noBookmarks"), message = L("youHaventBookmarkedAnyNotesYet"))
                    }
                    visible.isEmpty() -> Box(Modifier.fillMaxSize()) {
                        EmptyStateView(icon = Icons.Outlined.Search, title = L("noResultsFound"), message = L("trySearchingDifferentTerm"))
                    }
                    else -> LazyColumn(Modifier.fillMaxSize().testTag("bookmarks-list")) {
                        if (query.isEmpty()) {
                            item(key = "subtitle") {
                                Text(
                                    L("bookmarksSubtitle"),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = AppColors.textSecondary,
                                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                                )
                            }
                        }
                        items(visible, key = { it.id }) { note ->
                            BookmarkRow(note, removing = note.id in model.removing, modifier = Modifier.animateItem()) { model.remove(note) }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BookmarkRow(note: Note, removing: Boolean, modifier: Modifier, onRemove: () -> Unit) {
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart) onRemove()
        false
    })
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Row(
                Modifier.fillMaxSize().background(AppColors.error).padding(horizontal = 20.dp),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) { Icon(Icons.Outlined.BookmarkRemove, L("removeBookmark"), tint = Color.White, modifier = Modifier.testTag("bookmark-remove-${note.id}")) }
        },
        modifier = modifier.alpha(if (removing) 0.4f else 1f).testTag("bookmark-row-${note.id}"),
    ) {
        Box(Modifier.background(AppColors.background)) {
            Column {
                NoteRow(note)
                HorizontalDivider(color = AppColors.divider)
            }
        }
    }
}
