package me.untreu.qiqstr.ui.profile

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.QiqTextField
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.services.FollowSet
import me.untreu.qiqstr.data.services.FollowSetService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddToListSheet(pubkey: String, displayName: String, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    var working by remember { mutableStateOf<Set<String>>(emptySet()) }
    var showCreate by remember { mutableStateOf(false) }
    var newTitle by remember { mutableStateOf("") }
    val ownSets = FollowSetService.sets
    LaunchedEffect(Unit) { if (!FollowSetService.isLoaded) FollowSetService.load() }

    fun toggle(set: FollowSet, isMember: Boolean) {
        working = working + set.id
        scope.launch {
            try {
                if (isMember) {
                    FollowSetService.removeMember(pubkey, from = set.id)
                    ToastCenter.show(L("profileRemovedFromList", "list" to set.displayTitle), ToastStyle.SUCCESS)
                } else {
                    FollowSetService.addMember(pubkey, to = set.id)
                    ToastCenter.show(L("profileAddedToList", "list" to set.displayTitle), ToastStyle.SUCCESS)
                }
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            } catch (error: Throwable) {
                ToastCenter.error(error)
            } finally {
                working = working - set.id
            }
        }
    }

    fun create() {
        val title = newTitle.trim()
        newTitle = ""
        showCreate = false
        if (title.isEmpty()) return
        scope.launch {
            try {
                val created = FollowSetService.create(title, pubkeys = listOf(pubkey))
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                ToastCenter.show(L("profileAddedToList", "list" to created.displayTitle), ToastStyle.SUCCESS)
            } catch (error: Throwable) {
                ToastCenter.error(error)
            }
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = AppColors.background, modifier = Modifier.testTag("add-to-list-sheet")) {
        Text(
            L("addToList"),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
        )
        LazyColumn(Modifier.fillMaxWidth().navigationBarsPadding()) {
            if (ownSets.isEmpty()) {
                item {
                    if (FollowSetService.isLoaded) {
                        EmptyStateView(icon = Icons.Outlined.Group, title = L("noLists"), message = L("noListsDescription"))
                    } else {
                        Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = AppColors.textPrimary) }
                    }
                }
            } else {
                items(ownSets, key = { it.id }) { set ->
                    val isMember = pubkey in set.pubkeys
                    val busy = set.id in working
                    ListItem(
                        headlineContent = { Text(set.displayTitle) },
                        supportingContent = { Text(L("profileListMemberCount", "count" to set.pubkeys.size)) },
                        trailingContent = {
                            when {
                                busy -> CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = AppColors.textPrimary)
                                isMember -> Icon(Icons.Outlined.Check, null, tint = AppColors.link)
                            }
                        },
                        colors = ListItemDefaults.colors(containerColor = AppColors.background),
                        modifier = Modifier.clickable(enabled = !busy) { toggle(set, isMember) }.testTag("add-to-list-row"),
                    )
                }
                item {
                    Text(
                        L("profileAddToListFooter", "name" to displayName),
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textSecondary,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
            }
            item {
                ListItem(
                    headlineContent = { Text(L("createList")) },
                    leadingContent = { Icon(Icons.Outlined.Add, null) },
                    colors = ListItemDefaults.colors(containerColor = AppColors.background),
                    modifier = Modifier.clickable { showCreate = true }.testTag("add-to-list-create"),
                )
            }
        }
    }
    if (showCreate) {
        AlertDialog(
            onDismissRequest = { showCreate = false; newTitle = "" },
            title = { Text(L("createList")) },
            text = { QiqTextField(newTitle, { newTitle = it }, L("listNameHint")) },
            confirmButton = { TextAction(L("profileCreateAndAdd"), ::create, enabled = newTitle.isNotBlank()) },
            dismissButton = { TextAction(L("cancel"), { showCreate = false; newTitle = "" }) },
        )
    }
}
