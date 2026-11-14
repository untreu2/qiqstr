package me.untreu.qiqstr.ui.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Reply
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.FormatQuote
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.components.EmptyStateView

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ComposeDraftsSheet(drafts: List<ComposeDraft>, onSelect: (ComposeDraft) -> Unit, onDelete: (ComposeDraft) -> Unit, onDismiss: () -> Unit) {
    val items = remember { mutableStateListOf<ComposeDraft>().apply { addAll(drafts) } }
    Column(Modifier.fillMaxWidth().navigationBarsPadding().testTag("compose-drafts-sheet")) {
        CenterAlignedTopAppBar(
            title = { Text(L("feedDrafts")) },
            navigationIcon = {
                IconButton(onClick = onDismiss, modifier = Modifier.testTag("compose-drafts-close")) { Icon(Icons.Outlined.Check, L("done")) }
            },
            colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = AppColors.background),
        )
        if (items.isEmpty()) {
            EmptyStateView(icon = Icons.Outlined.Inbox, title = L("feedNoDrafts"))
        } else {
            LazyColumn(Modifier.fillMaxWidth()) {
                items(items, key = { it.id }) { draft ->
                    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
                        if (value == SwipeToDismissBoxValue.EndToStart) {
                            onDelete(draft)
                            items.removeAll { it.id == draft.id }
                            true
                        } else {
                            false
                        }
                    })
                    SwipeToDismissBox(
                        state = state,
                        enableDismissFromStartToEnd = false,
                        backgroundContent = {
                            Box(Modifier.fillMaxSize().background(AppColors.error).padding(horizontal = 20.dp), contentAlignment = Alignment.CenterEnd) {
                                Icon(Icons.Outlined.Delete, L("delete"), tint = Color.White)
                            }
                        },
                    ) {
                        ComposeDraftRow(draft, Modifier.background(AppColors.background).clickable { onSelect(draft) }.testTag("compose-draft-row"))
                    }
                    HorizontalDivider(Modifier.padding(start = 16.dp), color = AppColors.divider)
                }
            }
        }
    }
}

@Composable
private fun ComposeDraftRow(draft: ComposeDraft, modifier: Modifier = Modifier) {
    val (title, icon) = when (draft.kind) {
        ComposeDraft.Kind.NEW_NOTE -> L("newPost") to Icons.Outlined.EditNote
        ComposeDraft.Kind.REPLY -> L("reply") to Icons.AutoMirrored.Outlined.Reply
        ComposeDraft.Kind.QUOTE -> L("quote") to Icons.Outlined.FormatQuote
    }
    Column(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(icon, null, Modifier.size(16.dp), tint = AppColors.textSecondary)
            Text(title, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, modifier = Modifier.weight(1f))
            Text(TimeFormat.relative(draft.updatedAt / 1000), style = MaterialTheme.typography.bodySmall, color = AppColors.textTertiary)
        }
        Text(
            draft.preview.ifEmpty { L("feedDraftEmpty") },
            style = MaterialTheme.typography.bodyLarge,
            color = if (draft.preview.isEmpty()) AppColors.textSecondary else AppColors.textPrimary,
            maxLines = 3,
            overflow = TextOverflow.Ellipsis,
        )
        if (draft.media.isNotEmpty() || draft.poll != null) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                if (draft.media.isNotEmpty()) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Icon(Icons.Outlined.Image, null, Modifier.size(14.dp), tint = AppColors.textSecondary)
                        Text("${draft.media.size}", style = MaterialTheme.typography.labelSmall, color = AppColors.textSecondary)
                    }
                }
                if (draft.poll != null) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Icon(Icons.Outlined.BarChart, null, Modifier.size(14.dp), tint = AppColors.textSecondary)
                        Text(L("feedPoll"), style = MaterialTheme.typography.labelSmall, color = AppColors.textSecondary)
                    }
                }
            }
        }
    }
}
