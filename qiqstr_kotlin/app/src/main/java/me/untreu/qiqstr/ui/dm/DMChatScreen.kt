package me.untreu.qiqstr.ui.dm

import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.ArrowDownward
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.KeyboardArrowUp
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.NoEncryption
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.LoadingView
import me.untreu.qiqstr.core.components.PrimaryButton
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.services.ReadOnlyGate
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Profile

@Composable
fun DMChatScreen(pubkey: String) {
    val model: DMChatViewModel = viewModel { DMChatViewModel(pubkey) }
    val safety = remember { DMSafetyModel() }
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    val density = LocalDensity.current
    val listState = rememberLazyListState()
    val focusRequester = remember { FocusRequester() }
    var searchPresented by rememberSaveable { mutableStateOf(false) }
    var inputFocused by remember { mutableStateOf(false) }
    var unseenCount by remember { mutableIntStateOf(0) }
    var viewportHeight by remember { mutableIntStateOf(0) }
    val profile = ProfileCache.profiles[pubkey]
    val name = model.group?.displayName ?: profile?.bestName ?: Profile.shortNpub(pubkey)
    val messages = model.messages
    val rows = remember(messages) { model.rows(messages).asReversed() }
    val thresholdPx = with(density) { 360.dp.toPx() }
    val awayFromBottom by remember {
        derivedStateOf {
            val info = listState.layoutInfo
            val visible = info.visibleItemsInfo
            if (visible.isEmpty()) return@derivedStateOf false
            val average = visible.sumOf { it.size } / visible.size.toFloat()
            listState.firstVisibleItemIndex * average + listState.firstVisibleItemScrollOffset > thresholdPx
        }
    }

    LaunchedEffect(Unit) { model.appeared() }
    LaunchedEffect(Unit) { model.poll() }
    LaunchedEffect(pubkey) { ProfileCache.load(listOf(pubkey)) }
    DisposableEffect(Unit) { onDispose { model.disappeared() } }
    LaunchedEffect(awayFromBottom) { if (!awayFromBottom) unseenCount = 0 }
    LaunchedEffect(model.focusRequest) { if (model.focusRequest > 0) runCatching { focusRequester.requestFocus() } }
    LaunchedEffect(searchPresented) { if (!searchPresented) model.updateSearch("") }

    val lastMessage = messages.lastOrNull()
    var previousLastId by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(lastMessage?.id) {
        val old = previousLastId
        val new = lastMessage?.id
        previousLastId = new
        if (old == null || new == null) {
            listState.scrollToItem(0)
            return@LaunchedEffect
        }
        if (model.isSearching) return@LaunchedEffect
        if (awayFromBottom && lastMessage.isMine == false) {
            unseenCount += 1
            return@LaunchedEffect
        }
        listState.animateScrollToItem(0)
    }
    val lastIncomingId = messages.lastOrNull { !it.isMine }?.id
    var seenIncomingId by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(lastIncomingId) {
        if (seenIncomingId != null && lastIncomingId != null && seenIncomingId != lastIncomingId) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        seenIncomingId = lastIncomingId
    }
    LaunchedEffect(model.currentMatchId) {
        val id = model.currentMatchId ?: return@LaunchedEffect
        val index = rows.indexOfFirst { it.id == id }
        if (index >= 0) {
            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            listState.animateScrollToItem(index + 1, -viewportHeight / 2)
        }
    }
    var attachmentCount by remember { mutableIntStateOf(model.attachments.size) }
    LaunchedEffect(model.attachments.size) {
        val grew = model.attachments.size > attachmentCount
        attachmentCount = model.attachments.size
        if (grew && !awayFromBottom) listState.animateScrollToItem(0)
    }
    LaunchedEffect(inputFocused) {
        if (inputFocused) {
            delay(250)
            listState.animateScrollToItem(0)
        }
    }

    val actions = remember(model) {
        DMBubbleActions(
            onCopy = model::copy,
            onRetry = model::retry,
            onDiscard = model::discard,
            onQuote = model::quote,
            onInfo = model::showInfo,
            onReact = if (Session.canSign) model::react else null,
        )
    }

    Scaffold(
        containerColor = AppColors.background,
        contentWindowInsets = WindowInsets(0),
        topBar = {
            if (searchPresented) {
                SearchTopBar(model) { searchPresented = false }
            } else {
                ChatTopBar(pubkey, name, model, safety) { searchPresented = true }
            }
        },
        bottomBar = {
            Box(Modifier.windowInsetsPadding(WindowInsets.ime.union(WindowInsets.navigationBars))) {
                when {
                    model.isSearching -> MatchNavigator(model)
                    model.isRequest -> RequestBanner(name, model, safety, pubkey)
                    Session.canSign -> DMInputBar(
                        model,
                        focusRequester,
                        L("dmMessagePlaceholder", "name" to name),
                    ) { inputFocused = it }
                    else -> Box(Modifier.fillMaxWidth().padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
                        PrimaryButton(L("readOnlyAddKey"), { ReadOnlyGate.addKey() }, Modifier.testTag("dm-read-only-add-key"))
                    }
                }
            }
        },
        floatingActionButton = {
            AnimatedVisibility(
                awayFromBottom && messages.isNotEmpty() && !model.isSearching,
                enter = scaleIn(initialScale = 0.6f) + fadeIn(),
                exit = scaleOut(targetScale = 0.6f) + fadeOut(),
            ) {
                BadgedBox(badge = {
                    if (unseenCount > 0) {
                        Badge(containerColor = AppColors.textPrimary, contentColor = AppColors.background) {
                            Text(if (unseenCount > 99) "99+" else "$unseenCount")
                        }
                    }
                }) {
                    SmallFloatingActionButton(
                        onClick = {
                            unseenCount = 0
                            scope.launch { listState.animateScrollToItem(0) }
                        },
                        containerColor = AppColors.surface,
                        contentColor = AppColors.textPrimary,
                        shape = CircleShape,
                        modifier = Modifier.testTag("dm-jump-latest"),
                    ) { Icon(Icons.Outlined.ArrowDownward, L("dmJumpToLatest")) }
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding).onGloballyPositioned { viewportHeight = it.size.height }) {
            when {
                model.isLoading -> LoadingView(Modifier.testTag("dm-chat-loading"))
                messages.isEmpty() -> EmptyChat(pubkey, name, model)
                else -> LazyColumn(
                    state = listState,
                    reverseLayout = true,
                    modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp).testTag("dm-chat-messages"),
                ) {
                    item(key = "bottom-space") { Box(Modifier.padding(bottom = 6.dp)) }
                    items(rows, key = { it.id }, contentType = { if (it is DMChatRow.Day) 0 else 1 }) { row ->
                        Box(Modifier.animateItem()) {
                            when (row) {
                                is DMChatRow.Day -> DaySeparator(row.start)
                                is DMChatRow.Message -> DMMessageBubble(
                                    message = row.message,
                                    isFirstInGroup = row.isFirstInGroup,
                                    isLastInGroup = row.isLastInGroup,
                                    actions = actions,
                                    searchQuery = model.trimmedSearch,
                                    isCurrentMatch = model.currentMatchId == row.message.id,
                                    senderName = if (model.isGroup) ProfileCache.profile(row.message.sender)?.bestName ?: Profile.shortNpub(row.message.sender) else null,
                                    reactions = model.reactions(row.message),
                                )
                            }
                        }
                    }
                    if (model.canLoadOlder) {
                        item(key = "load-older") { LoadOlderButton(model) }
                    }
                    item(key = "top-space") { Box(Modifier.padding(top = 8.dp)) }
                }
            }
        }
    }

    DMSafetyDialogs(safety) { Router.pop() }

    model.infoMessage?.let { message ->
        ModalBottomSheet(onDismissRequest = { model.infoMessage = null }, containerColor = AppColors.background) {
            DMMessageInfoSheet(message, model.deliveryRelays(message), model.chatRelays()) { model.infoMessage = null }
        }
    }
}


@Composable
private fun ChatTopBar(pubkey: String, name: String, model: DMChatViewModel, safety: DMSafetyModel, onSearch: () -> Unit) {
    var menuOpen by remember { mutableStateOf(false) }
    var groupInfo by remember { mutableStateOf(false) }
    if (groupInfo) DMGroupInfoSheet(pubkey, onDismiss = { groupInfo = false }, onLeft = { Router.pop() })
    TopAppBar(
        navigationIcon = { IconButton(onClick = { Router.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } },
        title = {
            Row(
                Modifier
                    .widthIn(max = 260.dp)
                    .clip(CircleShape)
                    .clickable { if (model.isGroup) groupInfo = true else Router.push(Route.Profile(pubkey)) }
                    .padding(start = 4.dp, end = 16.dp, top = 4.dp, bottom = 4.dp)
                    .testTag("dm-chat-header"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (model.isGroup) DMGroupAvatar(model.group, 30.dp) else ProfileAvatar(pubkey, size = 30.dp)
                Text(name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        },
        actions = {
            Box {
                IconButton(onClick = { menuOpen = true }, modifier = Modifier.testTag("dm-chat-more")) { Icon(Icons.Outlined.MoreVert, L("profileMoreActions")) }
                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    DropdownMenuItem(
                        text = { Text(L("dmSearchInChat")) },
                        leadingIcon = { Icon(Icons.Outlined.Search, null) },
                        enabled = model.messages.isNotEmpty(),
                        onClick = { menuOpen = false; onSearch() },
                    )
                    if (model.isGroup) DropdownMenuItem(text = { Text(L("dmGroupInfo")) }, onClick = { menuOpen = false; groupInfo = true }, modifier = Modifier.testTag("dm-group-info-open"))
                    if (!model.isGroup) DropdownMenuItem(
                        text = { Text(L("dmViewProfile")) },
                        leadingIcon = { Icon(Icons.Outlined.AccountCircle, null) },
                        onClick = { menuOpen = false; Router.push(Route.Profile(pubkey)) },
                    )
                    if (!model.isGroup) DropdownMenuItem(
                        text = { Text(L("dmCopyNpub")) },
                        leadingIcon = { Icon(Icons.Outlined.ContentCopy, null) },
                        onClick = {
                            menuOpen = false
                            val clipboard = App.context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                            clipboard.setPrimaryClip(ClipData.newPlainText("npub", Nip19.npub(pubkey) ?: pubkey))
                            ToastCenter.show(L("copiedToClipboard"), ToastStyle.SUCCESS)
                        },
                    )
                    DMSafetyMenuItems(pubkey, safety) { menuOpen = false }
                }
            }
        },
        colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.background),
    )
}

@Composable
private fun SearchTopBar(model: DMChatViewModel, onClose: () -> Unit) {
    val focusRequester = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focusRequester.requestFocus() } }
    TopAppBar(
        navigationIcon = { IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("cancel")) } },
        title = {
            Box(contentAlignment = Alignment.CenterStart) {
                if (model.searchQuery.isEmpty()) {
                    Text(L("dmSearchPrompt"), style = MaterialTheme.typography.bodyLarge, color = AppColors.textTertiary)
                }
                BasicTextField(
                    value = model.searchQuery,
                    onValueChange = model::updateSearch,
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyLarge.copy(color = AppColors.textPrimary),
                    cursorBrush = SolidColor(AppColors.textPrimary),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { model.previousMatch() }),
                    modifier = Modifier.fillMaxWidth().focusRequester(focusRequester).testTag("dm-search-field"),
                )
            }
        },
        colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.background),
    )
}

@Composable
private fun MatchNavigator(model: DMChatViewModel) {
    val hasMatches = model.searchMatches.isNotEmpty()
    Surface(
        shape = CircleShape,
        color = AppColors.inputFill,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                model.matchPositionText,
                style = MaterialTheme.typography.bodyMedium,
                color = AppColors.textSecondary,
                modifier = Modifier.weight(1f).testTag("dm-search-position"),
            )
            IconButton(onClick = model::previousMatch, enabled = hasMatches, modifier = Modifier.testTag("dm-search-previous")) {
                Icon(Icons.Outlined.KeyboardArrowUp, L("dmSearchPrevious"))
            }
            IconButton(onClick = model::nextMatch, enabled = hasMatches, modifier = Modifier.testTag("dm-search-next")) {
                Icon(Icons.Outlined.KeyboardArrowDown, L("dmSearchNext"))
            }
        }
    }
}

@Composable
private fun RequestBanner(name: String, model: DMChatViewModel, safety: DMSafetyModel, pubkey: String) {
    Surface(color = AppColors.surface, tonalElevation = 2.dp, modifier = Modifier.fillMaxWidth().testTag("dm-request-banner")) {
        Column(
            Modifier.padding(horizontal = 20.dp, vertical = 14.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(L(if (model.isGroup) "dmGroupRequestNotice" else "dmRequestNotice", "name" to name), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, textAlign = TextAlign.Center)
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (!model.isGroup) OutlinedButton(
                    onClick = { safety.blockTarget = pubkey },
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = AppColors.error),
                    modifier = Modifier.heightIn(min = 48.dp).testTag("dm-request-block"),
                ) { Text(L("block"), fontWeight = FontWeight.SemiBold) }
                Button(
                    onClick = model::acceptRequest,
                    colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
                    modifier = Modifier.heightIn(min = 48.dp).testTag("dm-request-accept"),
                ) { Text(L("dmRequestAccept"), fontWeight = FontWeight.SemiBold) }
            }
        }
    }
}

@Composable
private fun LoadOlderButton(model: DMChatViewModel) {
    val scope = rememberCoroutineScope()
    Box(Modifier.fillMaxWidth().heightIn(min = 44.dp).padding(top = 8.dp), contentAlignment = Alignment.Center) {
        OutlinedButton(
            onClick = { scope.launch { model.loadOlder() } },
            enabled = !model.isLoadingOlder,
            shape = CircleShape,
            modifier = Modifier.testTag("dm-load-earlier"),
        ) {
            if (model.isLoadingOlder) {
                CircularProgressIndicator(Modifier.size(16.dp), color = AppColors.textPrimary, strokeWidth = 2.dp)
            } else {
                Text(L("dmLoadEarlier"), style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

@Composable
private fun DaySeparator(start: Long) {
    Box(Modifier.fillMaxWidth().padding(top = 18.dp, bottom = 8.dp), contentAlignment = Alignment.Center) {
        Text(
            DMFormat.daySeparator(start),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = AppColors.textSecondary,
            modifier = Modifier.background(AppColors.tile, CircleShape).padding(horizontal = 12.dp, vertical = 5.dp),
        )
    }
}

@Composable
private fun EmptyChat(pubkey: String, name: String, model: DMChatViewModel) {
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            scope.launch {
                refreshing = true
                model.refresh()
                refreshing = false
            }
        },
        modifier = Modifier.fillMaxSize().testTag("dm-chat-empty"),
    ) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = 80.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            if (model.isGroup) DMGroupAvatar(model.group, 84.dp) else ProfileAvatar(pubkey, size = 84.dp)
            Text(name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            if (model.isPeerUnavailable) {
                Row(Modifier.padding(horizontal = 32.dp).testTag("dm-chat-peer-unavailable"), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Outlined.NoEncryption, null, Modifier.size(18.dp), tint = AppColors.textSecondary)
                    Text(L("dmPeerNotOnMarmot", "name" to name), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, textAlign = TextAlign.Center)
                }
            } else {
                Text(L("noMessagesYet"), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
            }
            Row(Modifier.padding(horizontal = 32.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.Lock, null, Modifier.size(12.dp), tint = AppColors.textSecondary)
                Text(L("dmEncryptionNotice"), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, textAlign = TextAlign.Center)
            }
        }
    }
}
