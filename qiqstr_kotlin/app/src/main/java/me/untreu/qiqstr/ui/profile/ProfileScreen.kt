package me.untreu.qiqstr.ui.profile

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.Reply
import androidx.compose.material.icons.automirrored.outlined.VolumeOff
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.PersonOff
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.AvatarView
import me.untreu.qiqstr.core.components.BackTopBar
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.services.MuteService
import me.untreu.qiqstr.data.services.PinnedNotesService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.ui.note.NoteRow

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(pubkey: String) {
    val hex = remember(pubkey) { Nip19.pubkeyHex(pubkey) ?: pubkey }
    val model = viewModel(key = "profile-$hex") { ProfileViewModel(hex) }
    if (!model.isValidPubkey) {
        Scaffold(containerColor = AppColors.background, topBar = { BackTopBar(model.displayName) }) { padding ->
            EmptyStateView(icon = Icons.Outlined.PersonOff, title = L("errorLoadingUserProfile"), modifier = Modifier.padding(padding))
        }
        return
    }
    ProfileEffects(model)
    var viewerImage by remember { mutableStateOf<String?>(null) }
    var mediaSelection by remember { mutableStateOf<Int?>(null) }
    val listState = rememberLazyListState()
    val density = LocalDensity.current
    val topInset = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val barBottom = with(density) { (topInset + 64.dp).toPx() }
    var identityBottom by remember { mutableFloatStateOf(Float.MAX_VALUE) }
    val titleVisible by remember { derivedStateOf { listState.firstVisibleItemIndex > 0 || identityBottom <= barBottom } }
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val muted = MuteService.isMuted(hex)

    Box(Modifier.fillMaxSize()) {
        PullToRefreshBox(isRefreshing = model.isRefreshing, onRefresh = model::refresh, modifier = Modifier.fillMaxSize()) {
            LazyColumn(
                state = listState,
                contentPadding = PaddingValues(bottom = 24.dp),
                modifier = Modifier.fillMaxSize().testTag("profile-scroll"),
            ) {
                item(key = "header") {
                    ProfileHeader(model, onViewImage = { viewerImage = it }, onIdentityBottom = { identityBottom = it })
                }
                if (muted) {
                    item(key = "muted") {
                        EmptyStateView(
                            icon = Icons.AutoMirrored.Outlined.VolumeOff,
                            title = L("profileMutedTitle"),
                            message = L("profileMutedMessage"),
                            actionTitle = L("unmute"),
                            modifier = Modifier.padding(top = 32.dp).testTag("profile-muted-notice"),
                        ) { scope.launch { ProfileModeration.setMuted(hex, false) } }
                    }
                } else {
                    item(key = "tabs") {
                        PrimaryTabRow(
                            selectedTabIndex = model.tabs.indexOf(model.tab).coerceAtLeast(0),
                            containerColor = AppColors.background,
                            modifier = Modifier.padding(top = 18.dp, bottom = 8.dp).testTag("profile-tabs"),
                        ) {
                            model.tabs.forEach { tab ->
                                Tab(
                                    selected = model.tab == tab,
                                    onClick = {
                                        if (model.tab != tab) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                        model.tab = tab
                                    },
                                    text = { Text(tab.title, maxLines = 1) },
                                )
                            }
                        }
                    }
                    tabContent(model) { mediaSelection = it }
                    footer(model)
                }
            }
        }
        ProfileTopBar(model, titleVisible)
    }
    viewerImage?.let { url -> ProfileImageViewer(url) { viewerImage = null } }
    mediaSelection?.let { index -> ProfileMediaPager(model.media, index) { mediaSelection = null } }
}

@Composable
private fun ProfileEffects(model: ProfileViewModel) {
    LaunchedEffect(Unit) { model.start() }
    LaunchedEffect(DataBus.feedVersion) { model.reloadArticles() }
    LaunchedEffect(DataBus.feedVersion) {
        if (!model.hasLoadedNotes) return@LaunchedEffect
        delay(250)
        model.reloadNotes()
    }
    LaunchedEffect(DataBus.profileVersion) {
        if (!model.hasLoadedNotes) return@LaunchedEffect
        delay(250)
        model.reloadProfile()
    }
    LaunchedEffect(DataBus.interactionVersion) {
        if (!model.hasLoadedLikes) return@LaunchedEffect
        delay(400)
        model.reloadLikes()
    }
    LaunchedEffect(PinnedNotesService.version) {
        if (model.hasLoadedNotes) model.pinnedChanged()
    }
    LaunchedEffect(MuteService.mutedPubkeys.size) {
        if (model.hasLoadedNotes) model.reloadNotes()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProfileTopBar(model: ProfileViewModel, titleVisible: Boolean) {
    val container by animateColorAsState(if (titleVisible) AppColors.background else Color.Transparent, label = "profile-bar")
    val iconColor by animateColorAsState(if (titleVisible) AppColors.textPrimary else Color.White, label = "profile-bar-icons")
    TopAppBar(
        title = {
            AnimatedVisibility(titleVisible, enter = fadeIn() + slideInVertically { it / 3 }, exit = fadeOut() + slideOutVertically { it / 3 }) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AvatarView(model.profile.picture.ifEmpty { null }, 26.dp)
                    Text(model.displayName, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        },
        navigationIcon = { IconButton(onClick = { Router.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } },
        actions = { if (model.isMe) me.untreu.qiqstr.ui.articles.ArticleWriteMenu(); ProfileMenu(model) },
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = container,
            navigationIconContentColor = iconColor,
            actionIconContentColor = iconColor,
            titleContentColor = AppColors.textPrimary,
        ),
    )
}

private fun LazyListScope.tabContent(model: ProfileViewModel, onOpenMedia: (Int) -> Unit) {
    when (model.tab) {
        ProfileTab.ARTICLES -> {
            if (model.isMe) item("article-write") { me.untreu.qiqstr.ui.articles.ArticleWriteMenu() }
            if (model.articles.isEmpty()) item("articles-empty") { Text(L("profileNoArticles"), Modifier.padding(24.dp)) }
            items(model.articles, key = { "article-${it.id}" }) { article -> me.untreu.qiqstr.ui.articles.ArticleCard(article, Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) }
        }
        ProfileTab.NOTES -> {
            items(model.pinned, key = { "pinned-${it.id}" }) { note -> PinnedNoteRow(note, model.isMe) }
            noteRows(model, model.visibleNotes, L("noNotesFromThisUser"), Icons.Outlined.ChatBubbleOutline, "profile-notes")
        }
        ProfileTab.REPLIES -> noteRows(model, model.replies, L("noRepliesFound"), Icons.AutoMirrored.Outlined.Reply, "profile-replies")
        ProfileTab.PHOTOS -> {
            if (model.media.isEmpty()) {
                if (model.isSyncingNotes || !model.hasLoadedNotes) loadingRow()
                else item(key = "photos-empty") {
                    EmptyStateView(icon = Icons.Outlined.PhotoLibrary, title = L("profileNoMedia"), modifier = Modifier.padding(top = 12.dp).testTag("profile-photos-empty"))
                }
            } else {
                profileMediaGrid(model.media, onOpenMedia)
            }
        }
        ProfileTab.LIKES -> {
            if (model.likes.isEmpty() && !model.hasLoadedLikes) loadingRow()
            else noteRows(model, model.likes, L("profileNoLikes"), Icons.Outlined.FavoriteBorder, "profile-likes")
        }
    }
}

private fun LazyListScope.noteRows(model: ProfileViewModel, notes: List<Note>, empty: String, icon: ImageVector, id: String) {
    if (notes.isEmpty()) {
        if (model.isSyncingNotes || !model.hasLoadedNotes) {
            loadingRow()
        } else if (model.tab != ProfileTab.NOTES || model.pinned.isEmpty()) {
            item(key = "$id-empty") {
                EmptyStateView(icon = icon, title = empty, modifier = Modifier.padding(top = 12.dp).testTag("$id-empty"))
            }
        }
        return
    }
    items(notes, key = { "$id-${it.listId}" }) { note ->
        Column(Modifier.testTag("$id-row")) {
            NoteRow(note)
            HorizontalDivider(color = AppColors.divider)
        }
    }
}

private fun LazyListScope.loadingRow() {
    item(key = "loading") {
        Box(Modifier.fillMaxWidth().padding(vertical = 48.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(color = AppColors.textPrimary)
        }
    }
}

private fun LazyListScope.footer(model: ProfileViewModel) {
    val hasItems = when (model.tab) {
        ProfileTab.NOTES -> model.notes.isNotEmpty()
        ProfileTab.REPLIES -> model.replies.isNotEmpty()
        ProfileTab.PHOTOS -> model.media.isNotEmpty()
        ProfileTab.LIKES -> model.likes.isNotEmpty()
        ProfileTab.ARTICLES -> model.articles.isNotEmpty()
    }
    if (!hasItems || !model.canLoadMoreCurrent) return
    item(key = "load-more-${model.tab.raw}-${model.loadMoreCount}") {
        LaunchedEffect(Unit) { model.loadMore() }
        Box(Modifier.fillMaxWidth().padding(24.dp).testTag("profile-load-more"), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(Modifier.size(28.dp), color = AppColors.textPrimary)
        }
    }
}

@Composable
private fun PinnedNoteRow(note: Note, isMine: Boolean) {
    val scope = rememberCoroutineScope()
    var working by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().testTag("profile-pinned-row")) {
        Row(
            Modifier.fillMaxWidth().padding(start = 16.dp, top = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(Icons.Filled.PushPin, null, Modifier.size(14.dp), tint = AppColors.textSecondary)
            Text(L("pinnedNotes"), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = AppColors.textSecondary, modifier = Modifier.weight(1f))
            if (isMine) {
                Box {
                    IconButton(onClick = { menu = true }, enabled = !working) {
                        Icon(Icons.Outlined.MoreHoriz, L("unpinNote"), tint = AppColors.textSecondary)
                    }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(
                            text = { Text(L("unpinNote"), color = AppColors.error) },
                            leadingIcon = { Icon(Icons.Outlined.PushPin, null, tint = AppColors.error) },
                            modifier = Modifier.testTag("unpin-note"),
                            onClick = {
                                menu = false
                                working = true
                                scope.launch {
                                    try {
                                        PinnedNotesService.toggle(note.id)
                                        ToastCenter.show(L("noteUnpinned"), ToastStyle.SUCCESS)
                                    } catch (error: Throwable) {
                                        ToastCenter.error(error)
                                    } finally {
                                        working = false
                                    }
                                }
                            },
                        )
                    }
                }
            }
        }
        NoteRow(note)
        HorizontalDivider(color = AppColors.divider)
    }
}
