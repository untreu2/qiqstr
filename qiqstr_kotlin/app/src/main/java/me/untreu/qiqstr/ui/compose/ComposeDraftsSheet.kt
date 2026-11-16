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
import androidx.compose.material.icons.outlined.Schedule
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
internal fun ComposeDraftsSheet(
    drafts: List<ComposeDraft>,
    scheduled: List<ScheduledPost>,
    onSelect: (ComposeDraft) -> Unit,
    onDelete: (ComposeDraft) -> Unit,
    onSelectScheduled: (ScheduledPost) -> Unit,
    onDeleteScheduled: (ScheduledPost) -> Unit,
    onDismiss: () -> Unit,
) {
    val items = remember { mutableStateListOf<ComposeDraft>().apply { addAll(drafts) } }
    val posts = remember { mutableStateListOf<ScheduledPost>().apply { addAll(scheduled) } }
    Column(Modifier.fillMaxWidth().navigationBarsPadding().testTag("compose-drafts-sheet")) {
        CenterAlignedTopAppBar(
            title = { Text(L("feedDrafts")) },
            navigationIcon = {
                IconButton(onClick = onDismiss, modifier = Modifier.testTag("compose-drafts-close")) { Icon(Icons.Outlined.Check, L("done")) }
            },
            colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = AppColors.background),
        )
        if (items.isEmpty() && posts.isEmpty()) {
            EmptyStateView(icon = Icons.Outlined.Inbox, title = L("feedNoDrafts"))
        } else {
            LazyColumn(Modifier.fillMaxWidth()) {
                if (posts.isNotEmpty()) {
                    item(key = "scheduled-header") { DraftsSectionHeader(L("feedScheduledTitle")) }
                    items(posts, key = { "scheduled-${it.id}" }) { post ->
                        DraftSwipeToDelete(onDelete = {
                            onDeleteScheduled(post)
                            posts.removeAll { it.id == post.id }
                        }) {
                            ScheduledPostRow(post, Modifier.background(AppColors.background).clickable { onSelectScheduled(post) }.testTag("compose-scheduled-row"))
                        }
                        HorizontalDivider(Modifier.padding(start = 16.dp), color = AppColors.divider)
                    }
                    if (items.isNotEmpty()) item(key = "drafts-header") { DraftsSectionHeader(L("feedDrafts")) }
                }
                items(items, key = { it.id }) { draft ->
                    DraftSwipeToDelete(onDelete = {
                        onDelete(draft)
                        items.removeAll { it.id == draft.id }
                    }) {
                        ComposeDraftRow(draft, Modifier.background(AppColors.background).clickable { onSelect(draft) }.testTag("compose-draft-row"))
                    }
                    HorizontalDivider(Modifier.padding(start = 16.dp), color = AppColors.divider)
                }
            }
        }
    }
}

@Composable
private fun DraftsSectionHeader(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.labelLarge,
        color = AppColors.textSecondary,
        modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 4.dp),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DraftSwipeToDelete(onDelete: () -> Unit, content: @Composable () -> Unit) {
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart) {
            onDelete()
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
    ) { content() }
}

@Composable
private fun ScheduledPostRow(post: ScheduledPost, modifier: Modifier = Modifier) {
    val error = post.lastError
    val tint = if (error == null) AppColors.textSecondary else AppColors.error
    Column(modifier.fillMaxWidth()) {
        Row(
            Modifier.padding(start = 16.dp, end = 16.dp, top = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(Icons.Outlined.Schedule, null, Modifier.size(16.dp), tint = tint)
            Text(TimeFormat.full(post.publishAt), style = MaterialTheme.typography.labelLarge, color = tint)
        }
        ComposeDraftRow(post.draft, showsDate = false)
        if (error != null) {
            Text(
                error,
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.error,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp),
            )
        }
    }
}

@Composable
private fun ComposeDraftRow(draft: ComposeDraft, modifier: Modifier = Modifier, showsDate: Boolean = true) {
    val (title, icon) = when (draft.kind) {
        ComposeDraft.Kind.NEW_NOTE -> L("newPost") to Icons.Outlined.EditNote
        ComposeDraft.Kind.REPLY -> L("reply") to Icons.AutoMirrored.Outlined.Reply
        ComposeDraft.Kind.QUOTE -> L("quote") to Icons.Outlined.FormatQuote
    }
    Column(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(icon, null, Modifier.size(16.dp), tint = AppColors.textSecondary)
            Text(title, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, modifier = Modifier.weight(1f))
            if (showsDate) Text(TimeFormat.relative(draft.updatedAt / 1000), style = MaterialTheme.typography.bodySmall, color = AppColors.textTertiary)
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
