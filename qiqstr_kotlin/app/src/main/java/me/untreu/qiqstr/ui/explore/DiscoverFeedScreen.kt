package me.untreu.qiqstr.ui.explore

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.outlined.WifiOff
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.data.services.DiscoverFeed
import me.untreu.qiqstr.data.services.DiscoverFeedContent
import me.untreu.qiqstr.data.services.ExploreService
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Article
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.articles.ArticleCard
import me.untreu.qiqstr.ui.note.NoteInteractionStore
import me.untreu.qiqstr.ui.note.NoteRow

class DiscoverFeedViewModel(val feedId: String) : ViewModel() {
    var feed by mutableStateOf(ExploreService.feed(feedId))
        private set
    var notes by mutableStateOf<List<Note>>(emptyList())
        private set
    var articles by mutableStateOf<List<Article>>(emptyList())
        private set
    var isLoading by mutableStateOf(true)
        private set
    var failed by mutableStateOf(false)
        private set

    suspend fun load() {
        if (feed == null) {
            ExploreService.loadFeeds()
            feed = ExploreService.feed(feedId)
        }
        val feed = feed
        if (feed == null) {
            isLoading = false
            failed = true
            return
        }
        isLoading = notes.isEmpty() && articles.isEmpty()
        try {
            when (feed.content) {
                DiscoverFeedContent.NOTES -> {
                    val result = ExploreService.feedNotes(feed)
                    if (result == null) {
                        failed = notes.isEmpty()
                        return
                    }
                    notes = result
                    NoteInteractionStore.seed(result)
                    NoteInteractionStore.requestCounts(result.take(40).map { it.id })
                }
                DiscoverFeedContent.READS -> {
                    val result = ExploreService.feedArticles(feed)
                    if (result == null) {
                        failed = articles.isEmpty()
                        return
                    }
                    articles = result
                }
            }
            failed = false
            val pubkeys = (notes.map { it.pubkey } + articles.map { it.pubkey }).distinct()
            ProfileCache.load(pubkeys.filter { ProfileCache.profile(it) == null })
        } finally {
            isLoading = false
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DiscoverFeedScreen(feedId: String) {
    val model: DiscoverFeedViewModel = viewModel(key = "discover-$feedId") { DiscoverFeedViewModel(feedId) }
    val scope = rememberCoroutineScope()
    val scroll = TopAppBarDefaults.pinnedScrollBehavior()
    var menuOpen by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { model.load() }
    val feed = model.feed
    Scaffold(
        modifier = Modifier.fillMaxSize().nestedScroll(scroll.nestedScrollConnection).testTag("discover-feed-view"),
        containerColor = AppColors.background,
        contentWindowInsets = WindowInsets(0),
        topBar = {
            TopAppBar(
                title = { Text(feed?.name ?: L("exploreFeeds"), maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { IconButton(onClick = { Router.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } },
                actions = {
                    if (feed != null) {
                        Box {
                            IconButton(onClick = { menuOpen = true }, modifier = Modifier.testTag("discover-feed-menu")) {
                                Icon(Icons.Outlined.MoreVert, L("exploreMoreOptions"))
                            }
                            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                                if (feed.content == DiscoverFeedContent.NOTES) {
                                    val pinned = ExploreService.isPinned(feed)
                                    MenuAction(L(if (pinned) "exploreFeedRemoveFromHome" else "exploreFeedAddToHome"), if (pinned) Icons.Outlined.PushPin else Icons.Filled.PushPin) {
                                        menuOpen = false
                                        ExploreService.togglePin(feed)
                                    }
                                }
                                MenuAction(L("exploreFeedCreator"), Icons.Outlined.AccountCircle) {
                                    menuOpen = false
                                    Router.push(Route.Profile(feed.pubkey))
                                }
                            }
                        }
                    }
                },
                scrollBehavior = scroll,
                colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.background, scrolledContainerColor = AppColors.background),
            )
        },
    ) { padding ->
        PaddedBox(padding) {
            RefreshBox(onRefresh = { model.load() }) {
                val isReads = feed?.content == DiscoverFeedContent.READS
                LazyColumn(Modifier.fillMaxSize()) {
                    if (feed != null) item(key = "header") { FeedHeader(feed) }
                    if (isReads) {
                        items(model.articles, key = { "article-${it.id}" }) { ArticleCard(it, Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) }
                    } else {
                        items(model.notes, key = { "note-${it.listId}" }) { NoteRow(it) }
                    }
                }
                val isEmpty = if (isReads) model.articles.isEmpty() else model.notes.isEmpty()
                if (isEmpty) {
                    val modifier = Modifier.align(Alignment.Center)
                    when {
                        model.isLoading -> Column(modifier.fillMaxWidth().padding(top = 180.dp)) { repeat(3) { SearchNoteSkeletonRow(if (it % 2 == 0) 3 else 2) } }
                        model.failed -> EmptyStateView(icon = Icons.Outlined.WifiOff, title = L("exploreUnavailable"), actionTitle = L("retry"), modifier = modifier) {
                            scope.launch { model.load() }
                        }
                        else -> EmptyStateView(icon = Icons.Outlined.Inbox, title = L("noNotesYet"), modifier = modifier)
                    }
                }
            }
        }
    }
}

@Composable
private fun FeedHeader(feed: DiscoverFeed) {
    LaunchedEffect(feed.pubkey) { ProfileCache.load(listOf(feed.pubkey)) }
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            DiscoverFeedArtwork(feed, 60.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(feed.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                Row(
                    Modifier.clickable { Router.push(Route.Profile(feed.pubkey)) },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    ProfileAvatar(feed.pubkey, size = 18.dp)
                    Text(
                        L("exploreByAuthor", "name" to (ProfileCache.profiles[feed.pubkey]?.bestName ?: Profile.shortNpub(feed.pubkey))),
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
        if (feed.about.isNotEmpty()) Text(feed.about, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
        if (feed.content == DiscoverFeedContent.NOTES) DiscoverFeedPinButton(feed)
    }
}
