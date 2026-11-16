package me.untreu.qiqstr.ui.thread

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.components.CustomEmojiImage
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.components.BackTopBar
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.data.services.InteractionService
import me.untreu.qiqstr.data.services.NoteInteractionDetail
import me.untreu.qiqstr.data.services.NoteInteractionKind
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.NotificationItem
import me.untreu.qiqstr.domain.Profile

enum class NoteStatisticsTab {
    REACTIONS, REPOSTS, ZAPS;

    val title: String
        get() = when (this) {
            REACTIONS -> L("reactions")
            REPOSTS -> L("reposts")
            ZAPS -> L("zaps")
        }
}

data class NoteReactionGroup(val emoji: String, val items: List<NoteInteractionDetail>) {
    val emojiUrl: String? get() = items.firstNotNullOfOrNull { it.emojiUrl }
}

class NoteStatisticsViewModel(val noteId: String) : ViewModel() {
    var details by mutableStateOf<List<NoteInteractionDetail>>(emptyList())
        private set
    var isLoading by mutableStateOf(true)
        private set

    val reactions: List<NoteInteractionDetail> get() = details.filter { it.kind == NoteInteractionKind.REACTION }
    val reposts: List<NoteInteractionDetail> get() = details.filter { it.kind == NoteInteractionKind.REPOST }.sortedByDescending { it.createdAt }
    val zaps: List<NoteInteractionDetail> get() = details.filter { it.kind == NoteInteractionKind.ZAP }.sortedByDescending { it.zapAmount }
    val totalZapped: Long
        get() = zaps.fold(0L) { total, item ->
            val sum = total + item.zapAmount.toLong().coerceIn(0, NotificationItem.MAX_SATS)
            if (sum < total) Long.MAX_VALUE else sum
        }

    val reactionGroups: List<NoteReactionGroup>
        get() = reactions.groupBy { emoji(it.content) }
            .map { (emoji, items) -> NoteReactionGroup(emoji, items.sortedByDescending { it.createdAt }) }
            .sortedWith { a, b -> if (a.items.size == b.items.size) a.emoji.compareTo(b.emoji) else b.items.size.compareTo(a.items.size) }

    companion object {
        fun emoji(content: String): String {
            val trimmed = content.trim()
            if (trimmed.isEmpty() || trimmed == "+") return "❤️"
            if (trimmed == "-") return "👎"
            if (trimmed.startsWith(":") && trimmed.endsWith(":")) return trimmed
            return trimmed.take(4)
        }
    }

    suspend fun load() {
        apply(InteractionService.detailedInteractions(noteId))
        SyncService.syncInteractions(listOf(noteId))
        apply(InteractionService.detailedInteractions(noteId))
        isLoading = false
    }

    private fun apply(items: List<NoteInteractionDetail>) {
        details = items.distinctBy { it.id }
        if (details.isNotEmpty()) isLoading = false
        val pubkeys = details.map { it.pubkey }.distinct().filter { ProfileCache.profile(it) == null }
        if (pubkeys.isNotEmpty()) viewModelScope.launch { ProfileCache.load(pubkeys) }
    }
}

@Composable
fun NoteStatisticsScreen(noteId: String) {
    val model: NoteStatisticsViewModel = viewModel(key = "stats-$noteId") { NoteStatisticsViewModel(noteId) }
    var tab by rememberSaveable { mutableStateOf(NoteStatisticsTab.REACTIONS) }
    var isRefreshing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    LaunchedEffect(Unit) { model.load() }
    val count: (NoteStatisticsTab) -> Int = {
        when (it) {
            NoteStatisticsTab.REACTIONS -> model.reactions.size
            NoteStatisticsTab.REPOSTS -> model.reposts.size
            NoteStatisticsTab.ZAPS -> model.zaps.size
        }
    }
    Scaffold(containerColor = AppColors.background, topBar = { BackTopBar(L("interactions")) }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).testTag("statistics-tabs")) {
                NoteStatisticsTab.entries.forEachIndexed { index, item ->
                    val n = count(item)
                    SegmentedButton(
                        selected = tab == item,
                        onClick = {
                            if (tab != item) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            tab = item
                        },
                        shape = SegmentedButtonDefaults.itemShape(index, NoteStatisticsTab.entries.size),
                        label = { Text(if (n > 0) "${item.title} $n" else item.title, maxLines = 1) },
                    )
                }
            }
            PullToRefreshBox(
                isRefreshing = isRefreshing,
                onRefresh = {
                    scope.launch {
                        isRefreshing = true
                        try { model.load() } finally { isRefreshing = false }
                    }
                },
                modifier = Modifier.fillMaxSize(),
            ) {
                LazyColumn(Modifier.fillMaxSize().testTag("statistics-list")) {
                    when (tab) {
                        NoteStatisticsTab.REACTIONS -> model.reactionGroups.forEach { group ->
                            item(key = "h-${group.emoji}") {
                                Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    ReactionEmoji(group, 20)
                                    Text("${group.items.size}", style = MaterialTheme.typography.titleSmall, color = AppColors.textSecondary)
                                }
                            }
                            items(group.items, key = { "r-${group.emoji}-${it.id}" }) { detail ->
                                InteractionUserRow(detail) { ReactionEmoji(group, 28) }
                            }
                        }
                        NoteStatisticsTab.REPOSTS -> items(model.reposts, key = { it.id }) { detail ->
                            InteractionUserRow(detail) { Icon(Icons.Filled.Repeat, null, tint = AppColors.repost) }
                        }
                        NoteStatisticsTab.ZAPS -> {
                            if (model.totalZapped > 0) {
                                item(key = "zap-total") {
                                    Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                        Icon(Icons.Filled.Bolt, null, Modifier.size(18.dp), tint = AppColors.zap)
                                        Text("${Sats.format(model.totalZapped)} ${L("feedSats")}", style = MaterialTheme.typography.titleSmall)
                                    }
                                }
                            }
                            items(model.zaps, key = { it.id }) { detail ->
                                InteractionUserRow(detail) {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Icon(Icons.Filled.Bolt, null, Modifier.size(18.dp), tint = AppColors.zap)
                                        Text(Sats.format(detail.zapAmount.toLong()), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                                    }
                                }
                            }
                        }
                    }
                }
                if (count(tab) == 0) {
                    if (model.isLoading) {
                        CircularProgressIndicator(Modifier.align(Alignment.Center), color = AppColors.textPrimary)
                    } else {
                        EmptyStateView(Icons.Outlined.BarChart, L("noInteractionsYet"), modifier = Modifier.align(Alignment.Center).testTag("statistics-empty"))
                    }
                }
            }
        }
    }
}

@Composable
private fun InteractionUserRow(detail: NoteInteractionDetail, trailing: @Composable () -> Unit) {
    val name = ProfileCache.profiles[detail.pubkey]?.bestName ?: Profile.shortNpub(detail.pubkey)
    ListItem(
        headlineContent = { Text(name, fontWeight = FontWeight.SemiBold, maxLines = 1) },
        supportingContent = {
            if (detail.kind == NoteInteractionKind.ZAP && detail.content.isNotEmpty()) {
                Text(detail.content, maxLines = 2, color = AppColors.textSecondary)
            } else {
                Text(TimeFormat.relative(detail.createdAt), color = AppColors.textSecondary)
            }
        },
        leadingContent = { ProfileAvatar(detail.pubkey, size = 40.dp) },
        trailingContent = { Box { trailing() } },
        colors = ListItemDefaults.colors(containerColor = AppColors.background),
        modifier = Modifier.clickable { Router.push(Route.Profile(detail.pubkey)) }.testTag("statistics-user-row"),
    )
}

@Composable
private fun ReactionEmoji(group: NoteReactionGroup, size: Int) {
    val url = group.emojiUrl
    if (url != null) CustomEmojiImage(url, size.dp) else Text(group.emoji, style = MaterialTheme.typography.titleLarge)
}
