package me.untreu.qiqstr.ui.feed

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Tag
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MenuDefaults
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.services.HashtagFollowService
import me.untreu.qiqstr.data.services.ToastCenter

@Composable
fun TopicsManagerSheet(onDismiss: () -> Unit, onSelect: (String) -> Unit = {}) {
    val state = rememberModalBottomSheetState()
    val scope = rememberCoroutineScope()
    val dismiss: () -> Unit = { scope.launch { state.hide() }.invokeOnCompletion { onDismiss() } }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state, containerColor = AppColors.background) {
        TopicsManagerContent(onDone = dismiss, onSelect = { onSelect(it); dismiss() })
    }
}

@Composable
fun TopicsManagerContent(onDone: () -> Unit, onSelect: (String) -> Unit) {
    var draft by remember { mutableStateOf("") }
    val haptics = LocalHapticFeedback.current
    val tags = HashtagFollowService.tags
    val normalized = HashtagFollowService.normalize(draft)
    val canAdd = normalized != null && !HashtagFollowService.isFollowing(normalized)
    val showsInvalidHint = draft.isNotBlank() && draft != "#" && normalized == null
    val add = {
        val tag = normalized
        if (canAdd && tag != null) {
            draft = ""
            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            App.scope.launch { runCatching { HashtagFollowService.follow(tag) }.onFailure { ToastCenter.error(it) } }
        }
    }
    val remove: (String) -> Unit = { tag ->
        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        App.scope.launch { runCatching { HashtagFollowService.unfollow(tag) }.onFailure { ToastCenter.error(it) } }
    }
    Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
        TopAppBar(
            title = { Text(L("feedManageTopics")) },
            actions = { Row(Modifier.testTag("topics-done")) { TextAction(L("done"), onDone) } },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.background),
        )
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                placeholder = { Text(L("feedTopicPlaceholder")) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { add() }),
                modifier = Modifier.weight(1f).testTag("topics-field"),
            )
            IconButton(onClick = add, enabled = canAdd, modifier = Modifier.testTag("topics-add")) {
                Icon(Icons.Filled.AddCircle, L("feedAddTopic"))
            }
        }
        Text(
            if (showsInvalidHint) L("feedTopicInvalid") else L("feedTopicsFooter"),
            style = MaterialTheme.typography.bodySmall,
            color = if (showsInvalidHint) AppColors.error else AppColors.textSecondary,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )
        if (tags.isEmpty()) {
            if (HashtagFollowService.isLoaded) {
                EmptyStateView(Icons.Outlined.Tag, L("feedNoTopics"), L("feedNoTopicsMessage"))
            } else {
                repeat(3) {
                    ListItem(
                        headlineContent = { Text("#placeholder", color = AppColors.textTertiary) },
                        leadingContent = { Icon(Icons.Outlined.Tag, null, tint = AppColors.textTertiary) },
                        colors = ListItemDefaults.colors(containerColor = AppColors.background),
                    )
                }
            }
        } else {
            Text(L("feedTopics"), style = MaterialTheme.typography.labelLarge, color = AppColors.textSecondary, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
            LazyColumn(Modifier.fillMaxWidth().heightIn(max = 420.dp)) {
                items(tags, key = { it }) { tag ->
                    TopicRow(tag, pending = HashtagFollowService.isPending(tag), onSelect = { onSelect(tag) }, onRemove = { remove(tag) })
                    HorizontalDivider(color = AppColors.divider, thickness = 0.5.dp)
                }
            }
        }
    }
}

@Composable
private fun TopicRow(tag: String, pending: Boolean, onSelect: () -> Unit, onRemove: () -> Unit) {
    var showMenu by remember { mutableStateOf(false) }
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart) onRemove()
        false
    })
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Row(Modifier.fillMaxSize().background(AppColors.error).padding(horizontal = 24.dp), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.Delete, L("feedRemoveTopic"), tint = androidx.compose.ui.graphics.Color.White)
            }
        },
    ) {
        ListItem(
            headlineContent = { Text("#$tag", color = if (pending) AppColors.textTertiary else AppColors.textPrimary) },
            leadingContent = { Icon(Icons.Outlined.Tag, null) },
            colors = ListItemDefaults.colors(containerColor = AppColors.background),
            modifier = Modifier
                .combinedClickable(enabled = !pending, onClick = onSelect, onLongClick = { showMenu = true })
                .testTag("topics-row-$tag"),
        )
        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
            DropdownMenuItem(
                text = { Text(L("feedRemoveTopic")) },
                leadingIcon = { Icon(Icons.Outlined.Delete, null) },
                onClick = { showMenu = false; onRemove() },
                colors = MenuDefaults.itemColors(textColor = AppColors.error, leadingIconColor = AppColors.error),
            )
        }
    }
}
