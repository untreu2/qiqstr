package me.untreu.qiqstr.ui.notifications

import androidx.compose.foundation.lazy.rememberLazyListState
import me.untreu.qiqstr.app.AppTab
import me.untreu.qiqstr.app.ScrollToTopOnReselect
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
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material.icons.outlined.FilterListOff
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.outlined.VolumeOff
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.AppLanguage
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.LoadingView
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.NotificationBadge
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.explore.ExploreLargeScaffold
import me.untreu.qiqstr.ui.explore.LongPressMenuBox
import me.untreu.qiqstr.ui.explore.MenuAction
import me.untreu.qiqstr.ui.explore.PaddedBox
import me.untreu.qiqstr.ui.explore.RefreshBox

@Composable
fun NotificationsScreen() {
    val model: NotificationsViewModel = viewModel()
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    ScrollToTopOnReselect(AppTab.NOTIFICATIONS, listState)
    LaunchedEffect(DataBus.notificationVersion, Session.mutedPubkeys, Session.mutedWords) {
        if (model.isLoaded) delay(300)
        model.reload()
    }
    LaunchedEffect(Unit) {
        model.markSeenOnce()
        NotificationBadge.markRead()
    }
    ExploreLargeScaffold(
        title = L("notifications"),
        subtitle = if (model.filter == NotificationFilter.ALL) null else model.filter.title,
        showBack = false,
        actions = { FilterMenu(model) },
    ) { padding ->
        PaddedBox(padding) {
            val visible = model.visible
            when {
                !model.isLoaded -> LoadingView()
                model.errorMessage != null && model.all.isEmpty() -> EmptyStateView(
                    icon = Icons.Outlined.WarningAmber,
                    title = L("failedToLoadNotifications"),
                    message = model.errorMessage,
                    actionTitle = L("retryText"),
                    modifier = Modifier.align(Alignment.Center),
                ) { scope.launch { model.reload() } }
                else -> RefreshBox(onRefresh = { model.refresh() }) {
                    LazyColumn(Modifier.fillMaxSize().testTag("notifications-list"), state = listState) {
                        if (visible.groups.isEmpty() && visible.hidden == 0) {
                            item(key = "empty") { EmptyNotifications(model.filter) }
                        } else {
                            items(visible.groups, key = { it.id }) { group ->
                                NotificationListRow(group, model)
                                HorizontalDivider(color = AppColors.divider)
                            }
                            if (visible.hidden > 0) item(key = "hidden") { HiddenRow(visible.hidden) { model.revealHidden() } }
                            item(key = "footer") { Footer(model) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptyNotifications(filter: NotificationFilter) {
    val locale = AppLanguage.locale
    val filterName = if (locale.language == "de") filter.title else filter.title.lowercase(locale)
    EmptyStateView(
        icon = if (filter == NotificationFilter.ALL) Icons.Outlined.Notifications else filter.icon,
        title = if (filter == NotificationFilter.ALL) L("noNotificationsYet") else L("notificationsFilterEmpty", "filter" to filterName),
        message = L("whenSomeoneInteractsWithYourPosts"),
        modifier = Modifier.padding(top = 40.dp),
    )
}

@Composable
private fun FilterMenu(model: NotificationsViewModel) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }, modifier = Modifier.testTag("notifications-filter-menu")) {
            Icon(if (model.filter == NotificationFilter.ALL) Icons.Outlined.FilterList else Icons.Outlined.FilterListOff, model.filter.title)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            NotificationFilter.entries.forEach { filter ->
                DropdownMenuItem(
                    text = { Text(filter.title) },
                    leadingIcon = { Icon(filter.icon, null) },
                    trailingIcon = { RadioButton(selected = model.filter == filter, onClick = null) },
                    onClick = {
                        model.filter = filter
                        open = false
                    },
                    modifier = Modifier.testTag("notifications-filter-${filter.raw}"),
                )
            }
            HorizontalDivider()
            DropdownMenuItem(
                text = { Text(L("notificationsOnlyKnown")) },
                leadingIcon = { Icon(Icons.Outlined.People, null) },
                trailingIcon = { Checkbox(checked = model.onlyTrusted, onCheckedChange = null) },
                onClick = { model.updateOnlyTrusted(!model.onlyTrusted) },
                modifier = Modifier.testTag("notifications-only-known"),
            )
        }
    }
}

@Composable
private fun NotificationListRow(group: NotificationGroup, model: NotificationsViewModel) {
    LaunchedEffect(group.id) { model.loadMoreIfNeeded(group) }
    LongPressMenuBox(
        onClick = { open(group) },
        modifier = Modifier.testTag("notification-row-${group.id}"),
        menu = { dismiss ->
            group.focusedNoteId?.let { noteId ->
                MenuAction(L("notificationOpenNote"), Icons.Outlined.ChatBubbleOutline) {
                    dismiss()
                    Router.push(Route.Thread(noteId))
                }
            }
            group.authors.take(5).forEach { pubkey ->
                MenuAction(ProfileCache.profiles[pubkey]?.bestName ?: Profile.shortNpub(pubkey), Icons.Outlined.AccountCircle) {
                    dismiss()
                    Router.push(Route.Profile(pubkey))
                }
            }
            val single = group.authors.firstOrNull()
            if (!group.isGrouped && single != null) {
                HorizontalDivider()
                MenuAction(L("mute"), Icons.Outlined.VolumeOff, destructive = true) {
                    dismiss()
                    model.mute(single)
                }
            }
        },
    ) {
        Box(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) { NotificationRowView(group, model.isUnread(group)) }
    }
}

private fun open(group: NotificationGroup) {
    if (group.isGrouped) {
        group.targetNoteId?.let { Router.push(Route.Thread(it)) }
        return
    }
    val id = group.focusedNoteId
    val pubkey = group.authors.firstOrNull()
    when {
        id != null -> Router.push(Route.Thread(id))
        pubkey != null -> Router.push(Route.Profile(pubkey))
    }
}

@Composable
private fun HiddenRow(count: Int, onReveal: () -> Unit) {
    Row(
        Modifier.fillMaxWidth()
            .testTag("notifications-hidden-row")
            .clickable(onClick = onReveal)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(Icons.Outlined.VisibilityOff, null, tint = AppColors.textSecondary)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(L("notificationsHiddenCount", "count" to count), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Text(L("notificationsHiddenFooter"), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
        }
        Text(L("showKey"), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
    }
}

@Composable
private fun Footer(model: NotificationsViewModel) {
    val scope = rememberCoroutineScope()
    Box(Modifier.fillMaxWidth().padding(vertical = 16.dp), contentAlignment = Alignment.Center) {
        when {
            model.isLoadingMore -> CircularProgressIndicator(Modifier.size(24.dp), color = AppColors.textPrimary)
            model.hasReachedEnd -> Icon(Icons.Outlined.CheckCircle, null, Modifier.size(16.dp), tint = AppColors.textTertiary)
            else -> OutlinedButton(onClick = { scope.launch { model.loadMore() } }, modifier = Modifier.testTag("notifications-load-more")) {
                Text(L("notificationLoadOlder"), color = AppColors.textPrimary)
            }
        }
    }
}
