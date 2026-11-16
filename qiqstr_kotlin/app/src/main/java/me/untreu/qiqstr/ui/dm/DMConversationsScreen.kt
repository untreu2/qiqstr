package me.untreu.qiqstr.ui.dm

import androidx.compose.foundation.lazy.rememberLazyListState
import me.untreu.qiqstr.app.AppTab
import me.untreu.qiqstr.app.ScrollToTopOnReselect
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Drafts
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.Forum
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.MarkEmailUnread
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SearchBar
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.unit.em
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.LoadingView
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.data.services.ReadOnlyGate
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Profile

@Composable
fun DMConversationsScreen() {
    val model: DMConversationsViewModel = viewModel()
    val safety = remember { DMSafetyModel() }
    val scope = rememberCoroutineScope()
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    var menuOpen by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { model.appeared() }
    LaunchedEffect(Unit) { model.poll() }
    LaunchedEffect(DataBus.feedVersion) { model.reloadFollowing() }
    LaunchedEffect(model.hasLoaded) { model.autoSelectFilter() }
    DisposableEffect(Unit) { onDispose { model.disappeared() } }

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = AppColors.background,
        contentWindowInsets = WindowInsets(0),
        topBar = {
            LargeTopAppBar(
                title = { Text(L("messages")) },
                actions = {
                    if (model.hasUnread) {
                        Box {
                            IconButton(onClick = { menuOpen = true }, modifier = Modifier.testTag("dm-more")) { Icon(Icons.Outlined.MoreVert, null) }
                            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                                DropdownMenuItem(
                                    text = { Text(L("dmMarkAllRead")) },
                                    leadingIcon = { Icon(Icons.Outlined.CheckCircle, null) },
                                    onClick = { menuOpen = false; model.markAllRead() },
                                )
                            }
                        }
                    }
                    IconButton(onClick = { model.showNewMessage = true }, modifier = Modifier.testTag("dm-new-message")) {
                        Icon(Icons.Outlined.EditNote, L("newMessage"))
                    }
                },
                colors = TopAppBarDefaults.largeTopAppBarColors(containerColor = AppColors.background, scrolledContainerColor = AppColors.background),
                scrollBehavior = scrollBehavior,
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when {
                !Session.canSign -> EmptyStateView(
                    icon = Icons.Outlined.Lock,
                    title = L("readOnlyTitle"),
                    message = L("readOnlyMessage"),
                    actionTitle = L("readOnlyAddKey"),
                    modifier = Modifier.align(Alignment.Center).testTag("dm-read-only"),
                ) { ReadOnlyGate.addKey() }
                model.isInitialLoading -> LoadingView(Modifier.testTag("dm-loading"))
                else -> ConversationList(model, safety)
            }
        }
    }

    DMSafetyDialogs(safety)

    if (model.showNewMessage) {
        val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(onDismissRequest = { model.showNewMessage = false }, sheetState = state, containerColor = AppColors.background) {
            DMNewMessageSheet(onDismiss = {
                scope.launch { state.hide() }.invokeOnCompletion { model.showNewMessage = false }
            }) { pubkey ->
                scope.launch {
                    state.hide()
                    model.showNewMessage = false
                    delay(250)
                    Router.push(Route.DMChat(pubkey))
                }
            }
        }
    }
}

@Composable
private fun ConversationList(model: DMConversationsViewModel, safety: DMSafetyModel) {
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    var refreshing by remember { mutableStateOf(false) }
    val conversations = model.visibleConversations
    Column(Modifier.fillMaxSize()) {
        SearchBar(
            inputField = {
                SearchBarDefaults.InputField(
                    query = model.query,
                    onQueryChange = { model.query = it },
                    onSearch = {},
                    expanded = false,
                    onExpandedChange = {},
                    placeholder = { Text(L("search")) },
                    leadingIcon = { Icon(Icons.Outlined.Search, null) },
                    trailingIcon = {
                        if (model.query.isNotEmpty()) IconButton(onClick = { model.query = "" }) { Icon(Icons.Outlined.Close, L("cancel")) }
                    },
                    modifier = Modifier.testTag("dm-search"),
                )
            },
            expanded = false,
            onExpandedChange = {},
            windowInsets = WindowInsets(0),
            colors = SearchBarDefaults.colors(containerColor = AppColors.inputFill),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 8.dp),
        ) {}
        if (!model.isSearching) {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 8.dp).testTag("dm-filter")) {
                DMConversationFilter.entries.forEachIndexed { index, filter ->
                    SegmentedButton(
                        selected = model.filter == filter,
                        onClick = {
                            if (model.filter != filter) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            model.filter = filter
                        },
                        shape = SegmentedButtonDefaults.itemShape(index, DMConversationFilter.entries.size),
                        colors = SegmentedButtonDefaults.colors(
                            activeContainerColor = AppColors.textPrimary,
                            activeContentColor = AppColors.background,
                            inactiveContainerColor = AppColors.background,
                        ),
                        icon = {},
                    ) { Text(model.title(filter), maxLines = 1) }
                }
            }
        }
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = {
                scope.launch {
                    refreshing = true
                    model.refresh()
                    refreshing = false
                }
            },
            modifier = Modifier.fillMaxSize(),
        ) {
            val listState = rememberLazyListState()
            ScrollToTopOnReselect(AppTab.DM, listState)
            LazyColumn(Modifier.fillMaxSize().testTag("dm-conversations-list"), state = listState) {
                items(conversations, key = { it.peer }) { conversation ->
                    ConversationItem(conversation, model, safety, Modifier.animateItem())
                }
                if (!model.isSearching && conversations.isNotEmpty()) {
                    item(key = "notice") { EncryptionNotice() }
                }
            }
            if (conversations.isEmpty()) {
                val searched = model.searchedPubkey
                when {
                    model.isSearching && searched != null -> EmptyStateView(
                        icon = Icons.Outlined.Forum,
                        title = L("noResultsFound"),
                        message = L("dmSearchNewPerson"),
                        actionTitle = L("dmStartChat"),
                        modifier = Modifier.align(Alignment.TopCenter).padding(top = 60.dp).testTag("dm-search-start-chat"),
                    ) {
                        model.query = ""
                        Router.push(Route.DMChat(searched))
                    }
                    model.isSearching -> EmptyStateView(
                        icon = Icons.Outlined.Search,
                        title = L("noResultsFound"),
                        modifier = Modifier.align(Alignment.TopCenter).padding(top = 60.dp).testTag("dm-search-empty"),
                    )
                    model.filter == DMConversationFilter.REQUESTS -> EmptyStateView(
                        icon = Icons.Outlined.Inbox,
                        title = L("dmRequestsEmptyTitle"),
                        message = L("dmRequestsEmptyMessage"),
                        modifier = Modifier.align(Alignment.TopCenter).padding(top = 80.dp).testTag("dm-requests-empty"),
                    )
                    else -> EmptyStateView(
                        icon = Icons.Outlined.Forum,
                        title = L("noConversationsYet"),
                        message = L("startConversationBy"),
                        actionTitle = L("newMessage"),
                        modifier = Modifier.align(Alignment.TopCenter).padding(top = 80.dp).testTag("dm-empty"),
                    ) { model.showNewMessage = true }
                }
            }
        }
    }
}

@Composable
private fun EncryptionNotice() {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 16.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Outlined.Lock, null, Modifier.size(12.dp), tint = AppColors.textSecondary)
        Spacer(Modifier.width(6.dp))
        Text(L("dmEncryptionNotice"), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, textAlign = TextAlign.Center)
    }
}

@Composable
private fun ConversationItem(conversation: DMConversation, model: DMConversationsViewModel, safety: DMSafetyModel, modifier: Modifier = Modifier) {
    val current by rememberUpdatedState(conversation)
    val canToggle = conversation.isUnread || model.canMarkUnread(conversation)
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        when (value) {
            SwipeToDismissBoxValue.StartToEnd -> if (current.isUnread || model.canMarkUnread(current)) model.toggleRead(current)
            SwipeToDismissBoxValue.EndToStart -> safety.deleteTarget = current.peer
            SwipeToDismissBoxValue.Settled -> Unit
        }
        false
    })
    var menuOpen by remember { mutableStateOf(false) }
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = canToggle,
        backgroundContent = {
            val direction = state.dismissDirection
            val (color, icon, alignment) = when (direction) {
                SwipeToDismissBoxValue.StartToEnd -> Triple(
                    if (conversation.isUnread) AppColors.textPrimary else AppColors.accent,
                    if (conversation.isUnread) Icons.Outlined.Drafts else Icons.Outlined.MarkEmailUnread,
                    Alignment.CenterStart,
                )
                SwipeToDismissBoxValue.EndToStart -> Triple(AppColors.error, Icons.Outlined.DeleteOutline, Alignment.CenterEnd)
                SwipeToDismissBoxValue.Settled -> Triple(AppColors.background, null, Alignment.Center)
            }
            Box(Modifier.fillMaxSize().background(color).padding(horizontal = 24.dp), contentAlignment = alignment) {
                if (icon != null) Icon(icon, null, tint = AppColors.background)
            }
        },
        modifier = modifier.testTag("dm-conversation-${conversation.peer}"),
    ) {
        Box(Modifier.background(AppColors.background)) {
            DMConversationRow(
                conversation,
                Modifier.combinedClickable(
                    onClick = { Router.push(Route.DMChat(conversation.peer)) },
                    onLongClick = { menuOpen = true },
                ),
            )
            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                DropdownMenuItem(
                    text = { Text(L("message")) },
                    leadingIcon = { Icon(Icons.AutoMirrored.Outlined.Chat, null) },
                    onClick = { menuOpen = false; Router.push(Route.DMChat(conversation.peer)) },
                )
                if (!DMService.isGroup(conversation.peer)) DropdownMenuItem(
                    text = { Text(L("dmViewProfile")) },
                    leadingIcon = { Icon(Icons.Outlined.AccountCircle, null) },
                    onClick = { menuOpen = false; Router.push(Route.Profile(conversation.peer)) },
                )
                if (canToggle) {
                    DropdownMenuItem(
                        text = { Text(if (conversation.isUnread) L("dmMarkRead") else L("dmMarkUnread")) },
                        leadingIcon = { Icon(if (conversation.isUnread) Icons.Outlined.Drafts else Icons.Outlined.MarkEmailUnread, null) },
                        onClick = { menuOpen = false; model.toggleRead(conversation) },
                    )
                }
                if (!DMService.isGroup(conversation.peer)) DropdownMenuItem(
                    text = { Text(L("dmCopyNpub")) },
                    leadingIcon = { Icon(Icons.Outlined.ContentCopy, null) },
                    onClick = { menuOpen = false; model.copyNpub(conversation.peer) },
                )
                DMSafetyMenuItems(conversation.peer, safety) { menuOpen = false }
            }
        }
    }
}

@Composable
fun DMConversationRow(conversation: DMConversation, modifier: Modifier = Modifier) {
    val profile = ProfileCache.profiles[conversation.peer]
    val name = DMService.group(conversation.peer)?.displayName ?: profile?.bestName ?: Profile.shortNpub(conversation.peer)
    Row(
        modifier.fillMaxWidth().padding(start = 6.dp, end = 16.dp, top = 10.dp, bottom = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        val dot by animateFloatAsState(if (conversation.isUnread) 1f else 0f, label = "unread")
        Box(Modifier.padding(top = 21.dp).size(10.dp)) {
            if (dot > 0f) {
                Box(Modifier.size(10.dp).graphicsLayer { scaleX = dot; scaleY = dot; alpha = dot }.background(AppColors.accent, CircleShape).testTag("dm-unread-dot"))
            }
        }
        if (DMService.isGroup(conversation.peer)) DMGroupAvatar(DMService.group(conversation.peer), 52.dp) else ProfileAvatar(conversation.peer, size = 52.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    name,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Text(DMFormat.listTime(conversation.timestamp), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
            }
            ConversationPreview(conversation.lastMessage)
        }
    }
}

@Composable
private fun ConversationPreview(message: DMMessage) {
    val (icon, text) = DMFormat.preview(message)
    val tint = AppColors.textSecondary
    Text(
        buildAnnotatedString {
            if (message.isMine) withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(L("dmYouPrefix")) }
            if (icon != null) {
                appendInlineContent("icon", "")
                append(" ")
            }
            append(text)
        },
        inlineContent = if (icon == null) emptyMap() else mapOf(
            "icon" to InlineTextContent(Placeholder(1.em, 1.em, PlaceholderVerticalAlign.TextCenter)) { Icon(icon, null, tint = tint) },
        ),
        style = MaterialTheme.typography.bodyMedium,
        color = tint,
        maxLines = 2,
        minLines = 2,
        overflow = TextOverflow.Ellipsis,
    )
}
