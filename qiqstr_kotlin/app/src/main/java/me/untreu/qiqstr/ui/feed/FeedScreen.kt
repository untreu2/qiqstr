package me.untreu.qiqstr.ui.feed

import me.untreu.qiqstr.app.AppTab
import me.untreu.qiqstr.app.ScrollToTopOnReselect
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.fillMaxWidth as fillWidth
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.AutoAwesomeMosaic
import androidx.compose.material.icons.outlined.DynamicFeed
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.LibraryAdd
import androidx.compose.material.icons.outlined.LocalFireDepartment
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Tag
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.PillButton
import me.untreu.qiqstr.core.components.PrimaryButton
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.services.ExploreService
import me.untreu.qiqstr.data.services.FollowService
import me.untreu.qiqstr.data.services.HashtagFollowService
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.ui.note.FeedSortMode
import me.untreu.qiqstr.ui.note.NoteInteractionStore
import me.untreu.qiqstr.ui.note.NoteList

@Composable
fun FeedScreen() {
    val model: FeedViewModel = viewModel()
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    var isRefreshing by remember { mutableStateOf(false) }
    var isManagingTopics by remember { mutableStateOf(false) }
    var showMenu by remember { mutableStateOf(false) }
    val scrollBehavior = TopAppBarDefaults.enterAlwaysScrollBehavior()

    LaunchedEffect(Unit) { model.start() }
    LaunchedEffect(DataBus.feedVersion) { model.reload() }
    LaunchedEffect(DataBus.listsVersion) { model.loadLists() }
    LaunchedEffect(DataBus.interactionVersion) { if (DataBus.interactionVersion > 0) NoteInteractionStore.refreshAll() }
    LaunchedEffect(Unit) {
        snapshotFlow { Triple(Session.mutedPubkeys, Session.mutedWords, NoteInteractionStore.deletedIds) }.drop(1).collect { model.refilter() }
    }
    LaunchedEffect(Unit) { snapshotFlow { HashtagFollowService.tags }.drop(1).collect { model.topicsChanged() } }
    LaunchedEffect(Unit) { snapshotFlow { ExploreService.pinnedFeeds }.drop(1).collect { model.pinnedFeedsChanged(it) } }
    ScrollToTopOnReselect(AppTab.FEED, listState) { scrollBehavior.state.heightOffset = 0f }
    LaunchedEffect(model.scrollToTopToken) { if (model.scrollToTopToken > 0 && model.notes.isNotEmpty()) listState.animateScrollToItem(0) }
    LaunchedEffect(Unit) { snapshotFlow { model.source to model.sort }.drop(1).collect { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove) } }

    val refresh: () -> Unit = {
        scope.launch {
            isRefreshing = true
            try { model.refresh() } finally { isRefreshing = false }
        }
    }

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = AppColors.background,
        topBar = {
            CenterAlignedTopAppBar(
                navigationIcon = {
                    IconButton(onClick = { Router.showSidebar = true }, modifier = Modifier.semantics { contentDescription = L("profile") }.testTag("feed-avatar")) {
                        val me = Session.pubkey
                        if (me != null) ProfileAvatar(me, size = 30.dp) else Icon(Icons.Outlined.AccountCircle, null)
                    }
                },
                title = {
                    Box {
                        Surface(
                            onClick = { showMenu = true },
                            shape = CircleShape,
                            color = AppColors.tile,
                            modifier = Modifier.widthIn(max = 220.dp).testTag("feed-title"),
                        ) {
                            Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(model.source.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                                Icon(Icons.Filled.KeyboardArrowDown, null, Modifier.size(18.dp), tint = AppColors.textSecondary)
                            }
                        }
                        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }, modifier = Modifier.testTag("feed-selector")) {
                            FeedMenu(model, onManageTopics = { isManagingTopics = true }) { showMenu = false }
                        }
                    }
                },
                actions = {
                    IconButton(onClick = { Router.compose() }, modifier = Modifier.testTag("feed-compose")) {
                        Icon(Icons.Outlined.EditNote, L("newPost"))
                    }
                },
                scrollBehavior = scrollBehavior,
                colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = AppColors.background, scrolledContainerColor = AppColors.background),
            )
        },
    ) { padding ->
        PullToRefreshBox(isRefreshing = isRefreshing, onRefresh = refresh, modifier = Modifier.fillMaxSize().padding(padding)) {
            val showsFollowPrompt = model.source.isExplore && FollowService.isLoaded && FollowService.count == 0 && model.notes.isNotEmpty()
            NoteList(
                notes = model.notes,
                state = listState,
                isLoadingMore = model.isLoadingMore,
                onAppearNote = model::loadMoreIfNeeded,
                modifier = Modifier.testTag("feed-list"),
            ) {
                if (showsFollowPrompt) item(key = "follow-prompt") { FeedFollowPrompt(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) }
            }
            if (model.notes.isEmpty()) {
                when {
                    !model.hasLoaded || model.isSyncing -> FeedSkeleton(Modifier.semantics { contentDescription = L("loadingYourFeed") }.testTag("feed-loading"))
                    model.source is FeedSource.List -> EmptyStateView(Icons.AutoMirrored.Outlined.List, L("noNotesYet"), actionTitle = L("refresh"), modifier = Modifier.align(Alignment.Center), action = refresh)
                    model.source.isTopicFeed || model.source.isCurated -> EmptyStateView(Icons.Outlined.Tag, L("noNotesYet"), actionTitle = L("refresh"), modifier = Modifier.align(Alignment.Center), action = refresh)
                    else -> FeedEmptyState(Modifier.align(Alignment.Center), onExplore = { model.select(FeedSource.Explore) }, onRefresh = refresh)
                }
            }
            AnimatedVisibility(
                visible = model.pendingCount > 0,
                enter = slideInVertically { -it } + fadeIn(),
                exit = slideOutVertically { -it } + fadeOut(),
                modifier = Modifier.align(Alignment.TopCenter).padding(top = 8.dp),
            ) {
                FeedNewNotesPill(model.pendingCount) { model.acceptPending() }
            }
        }
    }
    if (isManagingTopics) {
        TopicsManagerSheet(onDismiss = { isManagingTopics = false }) { model.select(FeedSource.Topic(it)) }
    }
}

@Composable
private fun FeedMenu(model: FeedViewModel, onManageTopics: () -> Unit, onDismiss: () -> Unit) {
    val choose: (FeedSource) -> Unit = { onDismiss(); model.select(it) }
    val header: @Composable (String) -> Unit = { title ->
        Text(
            title,
            style = MaterialTheme.typography.labelMedium,
            color = AppColors.textSecondary,
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 4.dp),
        )
    }
    MenuToggle(L("feedExplore"), Icons.Outlined.Explore, model.source == FeedSource.Explore) { choose(FeedSource.Explore) }
    MenuToggle(L("all"), Icons.Outlined.Group, model.source == FeedSource.Following) { choose(FeedSource.Following) }
    model.lists.forEach { set ->
        MenuToggle(set.title, Icons.AutoMirrored.Outlined.List, (model.source as? FeedSource.List)?.set?.id == set.id) { choose(FeedSource.List(set)) }
    }
    DropdownMenuItem(
        text = { Text(L("feedAddFeed")) },
        leadingIcon = { Icon(Icons.Outlined.Add, null) },
        onClick = { onDismiss(); Router.push(Route.FollowSets) },
        modifier = Modifier.testTag("feed-add-list"),
    )
    HorizontalDivider()
    header(L("exploreFeeds"))
    ExploreService.pinnedFeeds.forEach { feed ->
        MenuToggle(feed.name, Icons.Outlined.AutoAwesome, (model.source as? FeedSource.Discover)?.feed?.id == feed.id) { choose(FeedSource.Discover(feed)) }
    }
    DropdownMenuItem(
        text = { Text(L("exploreDiscoverFeeds")) },
        leadingIcon = { Icon(Icons.Outlined.GridView, null) },
        onClick = { onDismiss(); Router.push(Route.DiscoverFeeds) },
        modifier = Modifier.testTag("feed-discover-feeds"),
    )
    HorizontalDivider()
    header(L("feedTopics"))
    val tags = HashtagFollowService.tags
    if (tags.isNotEmpty()) {
        if (tags.size > 1) MenuToggle(L("feedAllTopics"), Icons.Outlined.AutoAwesomeMosaic, model.source == FeedSource.Topics) { choose(FeedSource.Topics) }
        tags.forEach { tag ->
            MenuToggle("#$tag", Icons.Outlined.Tag, (model.source as? FeedSource.Topic)?.tag == tag) { choose(FeedSource.Topic(tag)) }
        }
        MenuToggle(L("feedFollowingPlusTopics"), Icons.Outlined.LibraryAdd, model.includeTopics, "feed-include-topics") {
            model.updateIncludeTopics(!model.includeTopics)
        }
    }
    DropdownMenuItem(
        text = { Text(L("feedManageTopics")) },
        leadingIcon = { Icon(Icons.Outlined.Tag, null) },
        onClick = { onDismiss(); onManageTopics() },
        modifier = Modifier.testTag("feed-manage-topics"),
    )
    if (!model.source.isTopicFeed && !model.source.isCurated) {
        HorizontalDivider()
        header(L("sortBy"))
        FeedSortMode.entries.forEach { mode ->
            val icon = if (mode == FeedSortMode.LATEST) Icons.Outlined.Schedule else Icons.Outlined.LocalFireDepartment
            MenuToggle(mode.title, icon, model.sort == mode) { onDismiss(); model.updateSort(mode) }
        }
    }
}

@Composable
private fun MenuToggle(title: String, icon: ImageVector, selected: Boolean, tag: String? = null, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal) },
        leadingIcon = { Icon(icon, null) },
        trailingIcon = { if (selected) Icon(Icons.Filled.Check, null) },
        onClick = onClick,
        modifier = if (tag != null) Modifier.testTag(tag) else Modifier,
    )
}

@Composable
fun FeedNewNotesPill(count: Int, onClick: () -> Unit) {
    val haptics = LocalHapticFeedback.current
    LaunchedEffect(count) { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove) }
    Surface(
        onClick = onClick,
        shape = CircleShape,
        color = AppColors.textPrimary,
        contentColor = AppColors.background,
        shadowElevation = 6.dp,
        modifier = Modifier.testTag("feed-new-notes"),
    ) {
        Row(Modifier.padding(horizontal = 18.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Filled.ArrowUpward, null, Modifier.size(18.dp))
            Text(if (count == 1) L("feedNewNotesOne") else L("feedNewNotesMany", "count" to count), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
fun FeedSkeleton(modifier: Modifier = Modifier) {
    val transition = rememberInfiniteTransition(label = "skeleton")
    val alpha by transition.animateFloat(0.5f, 1f, infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "skeleton-alpha")
    Column(modifier.fillMaxSize().background(AppColors.background)) {
        repeat(6) { index ->
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.size(44.dp).background(AppColors.tile.copy(alpha = AppColors.tile.alpha * alpha), CircleShape))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    SkeletonBar(0.45f, alpha)
                    repeat(if (index % 2 == 0) 3 else 2) { SkeletonBar(0.95f, alpha) }
                    SkeletonBar(0.3f, alpha)
                }
            }
            HorizontalDivider(color = AppColors.divider, thickness = 0.5.dp)
        }
    }
}

@Composable
private fun SkeletonBar(fraction: Float, alpha: Float) {
    Box(Modifier.fillWidth(fraction).height(12.dp).background(AppColors.tile.copy(alpha = AppColors.tile.alpha * alpha * 1.6f), RoundedCornerShape(6.dp)))
}

@Composable
fun FeedFollowPrompt(modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxWidth().background(AppColors.overlayLight, RoundedCornerShape(20.dp)).padding(16.dp).testTag("feed-follow-prompt"),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Outlined.Group, null)
            Text(L("feedFollowPromptTitle"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        }
        Text(L("feedFollowPromptMessage"), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
        PillButton(L("suggestedFollows"), { Router.push(Route.SuggestedFollows) }, modifier = Modifier.testTag("feed-follow-prompt-open"))
    }
}

@Composable
fun FeedEmptyState(modifier: Modifier = Modifier, onExplore: () -> Unit, onRefresh: () -> Unit) {
    Column(
        modifier.fillMaxWidth().padding(32.dp).testTag("feed-empty"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(Icons.Outlined.DynamicFeed, null, Modifier.size(44.dp), tint = AppColors.textSecondary)
        Text(L("yourFeedIsEmpty"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Text(L("followSomeoneToSeePosts"), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
        PrimaryButton(L("suggestedFollows"), { Router.push(Route.SuggestedFollows) }, modifier = Modifier.testTag("feed-empty-suggested"))
        PillButton(L("feedExplore"), onExplore, filled = false, icon = Icons.Outlined.Explore, modifier = Modifier.testTag("feed-empty-explore"))
        TextAction(L("refresh"), onRefresh)
    }
}
