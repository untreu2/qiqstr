package me.untreu.qiqstr.ui.thread

import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Reply
import androidx.compose.material.icons.filled.SubdirectoryArrowRight
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.ComposeContext
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.components.BackTopBar
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.LoadingView
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.data.services.InteractionCounts
import me.untreu.qiqstr.data.services.WebOfTrustService
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.note.InteractionBar
import me.untreu.qiqstr.ui.note.NoteActionDialogs
import me.untreu.qiqstr.ui.note.NoteActionHandler
import me.untreu.qiqstr.ui.note.NoteAuthorLine
import me.untreu.qiqstr.ui.note.NoteContentView
import me.untreu.qiqstr.ui.note.NoteInteractionStore
import me.untreu.qiqstr.ui.note.NoteMenuItems
import me.untreu.qiqstr.ui.note.NoteReplyContextLine
import me.untreu.qiqstr.ui.note.NoteRepostHeader
import me.untreu.qiqstr.ui.note.NoteRow
import me.untreu.qiqstr.ui.note.NoteTranslateButton

@Composable
fun ThreadScreen(noteId: String) {
    val model: ThreadViewModel = viewModel(key = "thread-$noteId") { ThreadViewModel(noteId) }
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    var isRefreshing by remember { mutableStateOf(false) }
    val scrollBehavior = TopAppBarDefaults.pinnedScrollBehavior()

    LaunchedEffect(Unit) { model.start() }
    LaunchedEffect(DataBus.feedVersion) { model.reloadLocal() }
    LaunchedEffect(Unit) {
        snapshotFlow { NoteInteractionStore.deletedIds }.drop(1).collect {
            if (NoteInteractionStore.isDeleted(noteId)) Router.pop() else model.rebuild()
        }
    }
    LaunchedEffect(Unit) { snapshotFlow { WebOfTrustService.trustedCount }.drop(1).collect { model.rebuild() } }
    val ancestorCount = model.ancestors.size
    LaunchedEffect(ancestorCount) { if (ancestorCount > 0) listState.scrollToItem(ancestorCount) }
    DisposableEffect(Unit) { onDispose { model.stop() } }

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = AppColors.background,
        topBar = { BackTopBar(L("thread"), scrollBehavior = scrollBehavior) },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = {
                scope.launch {
                    isRefreshing = true
                    try { model.refresh() } finally { isRefreshing = false }
                }
            },
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            val focused = model.focused
            LazyColumn(Modifier.fillMaxSize().testTag("thread-list"), state = listState) {
                items(model.ancestors, key = { "a-${it.id}" }) { note ->
                    NoteRow(note, showsThreadContext = false, compact = true, showsConnector = true)
                }
                if (focused != null) {
                    item(key = "focused") { FocusedNoteView(focused, model.quoteCount) }
                    item(key = "reply-entry") { ThreadReplyEntryButton(focused) }
                    if (model.rows.isEmpty()) {
                        item(key = "no-replies") {
                            Box(Modifier.fillMaxWidth().padding(vertical = 32.dp).testTag("thread-no-replies"), contentAlignment = Alignment.Center) {
                                if (model.repliesSynced) {
                                    Text(L("noRepliesFound"), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
                                } else {
                                    CircularProgressIndicator(color = AppColors.textSecondary)
                                }
                            }
                        }
                    }
                    items(model.rows, key = { it.id }) { row -> ThreadRowView(row, model) }
                }
            }
            if (focused == null) {
                if (model.failed) {
                    EmptyStateView(
                        Icons.Outlined.ErrorOutline,
                        L("failedToLoadThread"),
                        actionTitle = L("retryText"),
                        modifier = Modifier.align(Alignment.Center).testTag("thread-error"),
                    ) { scope.launch { model.refresh() } }
                } else {
                    LoadingView()
                }
            }
        }
    }
}

private fun indent(depth: Int): Dp = (minOf(depth, ThreadViewModel.MAX_DEPTH + 1) * 24).dp

@Composable
private fun ThreadRowView(row: NoteThreadRow, model: ThreadViewModel) {
    when (row) {
        is NoteThreadRow.Reply -> {
            val guide = AppColors.divider
            Column {
                Box(
                    Modifier.fillMaxWidth().drawBehind {
                        for (level in 0 until row.depth) {
                            val x = (level * 24 + 16 + if (level == 0) 22 else 17).dp.toPx()
                            drawLine(guide, Offset(x, 0f), Offset(x, size.height), strokeWidth = 1.5.dp.toPx())
                        }
                    }.padding(start = indent(row.depth)),
                ) {
                    NoteRow(row.note, showsThreadContext = false, compact = row.depth > 0, swipeActions = true)
                }
                if (!row.hasChildren) HorizontalDivider(color = AppColors.divider, thickness = 0.5.dp)
            }
        }
        is NoteThreadRow.MoreReplies -> ThreadLink(L("moreReplies", "count" to row.hidden), Icons.Filled.KeyboardArrowDown, row.depth, "thread-more-replies") {
            model.expand(row.parentId)
        }
        is NoteThreadRow.ContinueThread -> ThreadLink("${L("viewMoreReplies")} (${row.count})", Icons.Filled.SubdirectoryArrowRight, row.depth, "thread-continue") {
            Router.push(Route.Thread(row.noteId))
        }
        is NoteThreadRow.LoadMore -> OutlinedButton(
            onClick = { model.showMoreTopLevel() },
            shape = CircleShape,
            modifier = Modifier.fillMaxWidth().padding(16.dp).testTag("thread-load-more"),
        ) { Text("${L("loadMore")} (${row.remaining})", fontWeight = FontWeight.SemiBold, color = AppColors.textPrimary) }
        is NoteThreadRow.HiddenReplies -> Row(
            Modifier.fillMaxWidth().clickable { model.revealHidden() }.padding(horizontal = 16.dp, vertical = 14.dp).testTag("thread-hidden-replies"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(Icons.Outlined.VisibilityOff, null, Modifier.size(16.dp), tint = AppColors.textSecondary)
            Text("${L("feedRepliesHidden", "count" to row.count)} ·", style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
            Text(L("feedSensitiveShow"), style = MaterialTheme.typography.bodySmall, color = AppColors.link)
        }
    }
}

@Composable
private fun ThreadLink(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, depth: Int, tag: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(start = indent(depth) + 16.dp, end = 16.dp, top = 10.dp, bottom = 10.dp).testTag(tag),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(icon, null, Modifier.size(16.dp), tint = AppColors.link)
        Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = AppColors.link)
    }
}

@Composable
fun ThreadReplyEntryButton(note: Note) {
    Surface(
        onClick = { Router.compose(ComposeContext.Reply(note)) },
        shape = CircleShape,
        color = AppColors.tile,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp).testTag("thread-reply-entry"),
    ) {
        Row(Modifier.padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Session.pubkey?.let { ProfileAvatar(it, size = 28.dp) }
            Text(L("addAReply"), style = MaterialTheme.typography.bodyLarge, color = AppColors.textSecondary, modifier = Modifier.weight(1f))
            Icon(Icons.AutoMirrored.Outlined.Reply, null, tint = AppColors.textSecondary)
        }
    }
}

@Composable
fun FocusedNoteView(note: Note, quoteCount: Int) {
    val model = NoteInteractionStore.model(note)
    val actions = remember { NoteActionHandler() }
    var showMenu by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    val profile = ProfileCache.profiles[note.pubkey]
    val name = profile?.bestName ?: note.authorName ?: Profile.shortNpub(note.pubkey)
    Box {
        Column(
            Modifier.fillMaxWidth()
                .combinedClickable(onClick = {}, onLongClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    showMenu = true
                })
                .padding(start = 16.dp, end = 16.dp, top = 14.dp)
                .testTag("thread-focused"),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val reposter = note.repostedBy
            if (note.isRepost && reposter != null) NoteRepostHeader(reposter, note.repostedByName)
            Row(
                Modifier.clip(CircleShape).clickable { Router.push(Route.Profile(note.pubkey)) }.testTag("thread-focused-author"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                ProfileAvatar(note.pubkey, size = 48.dp, fallbackUrl = note.authorImage)
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NoteAuthorLine(note, name, null, large = true)
                    val nip05 = profile?.nip05?.ifEmpty { null } ?: note.authorNip05
                    if (nip05 != null) {
                        Text(if (nip05.startsWith("_@")) nip05.drop(2) else nip05, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, maxLines = 1)
                    }
                }
            }
            if (note.isReply) focusedReplyTarget(note)?.let { NoteReplyContextLine(it) }
            NoteContentView(
                note,
                style = if (note.content.length > 280) MaterialTheme.typography.bodyLarge else MaterialTheme.typography.titleLarge,
                selectable = true,
                expandedByDefault = true,
            )
            NoteTranslateButton(note)
            Text(TimeFormat.full(note.createdAt), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
            StatsRow(note, model.counts, quoteCount)
            HorizontalDivider(color = AppColors.divider)
            InteractionBar(note, model, actions)
            HorizontalDivider(color = AppColors.divider)
        }
        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
            NoteMenuItems(note, actions) { showMenu = false }
        }
    }
    NoteActionDialogs(actions)
}

private fun focusedReplyTarget(note: Note): String? {
    note.tags.firstOrNull { it.size > 4 && it[0] == "e" && it[3] == "reply" && it[4].length == 64 }?.let { return it[4] }
    return note.tags.firstOrNull { it.size > 1 && it[0] == "p" && it[1] != note.pubkey }?.get(1)
}

@Composable
private fun StatsRow(note: Note, counts: InteractionCounts, quoteCount: Int) {
    val items = listOf(
        Triple(counts.reposts, L(if (counts.reposts == 1) "repost" else "reposts"), Route.NoteStatistics(note.id)),
        Triple(quoteCount, L("quotes"), Route.Quotes(note.id)),
        Triple(counts.reactions, L(if (counts.reactions == 1) "reaction" else "reactions"), Route.NoteStatistics(note.id)),
        Triple(counts.zapAmount, L("feedSats"), Route.NoteStatistics(note.id)),
    ).filter { it.first > 0 }
    if (items.isEmpty()) return
    FlowRow(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        items.forEach { (count, label, route) ->
            Row(
                Modifier.clickable { Router.push(route) }.testTag("thread-stat-$label"),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(Sats.compact(count.toLong()), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = AppColors.textPrimary)
                Text(label, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, maxLines = 1)
            }
        }
    }
}
