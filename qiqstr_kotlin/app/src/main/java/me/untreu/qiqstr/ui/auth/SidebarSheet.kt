package me.untreu.qiqstr.ui.auth

import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.Article
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.CellTower
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.PortableWifiOff
import androidx.compose.material.icons.outlined.Sensors
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.qiqstr.core.fetchFollowerCounts
import com.qiqstr.core.getConnectedRelayCount
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.app.AppSheet
import me.untreu.qiqstr.app.FollowListMode
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.core.ThemePreference
import me.untreu.qiqstr.core.ThemeState
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Profile

class SidebarViewModel : ViewModel() {
    var followerCount by mutableStateOf<Int?>(null)
        private set
    var followingCount by mutableStateOf<Int?>(null)
        private set
    var relayCount by mutableStateOf<Int?>(null)
        private set

    init {
        viewModelScope.launch {
            while (true) {
                delay(10_000)
                loadRelays()
            }
        }
    }

    suspend fun loadProfile() {
        val me = Session.pubkey ?: return
        ProfileCache.refresh(me)
        SyncService.syncProfile(me)
        ProfileCache.refresh(me)
    }

    suspend fun loadFollowing() {
        val me = Session.pubkey ?: return
        followingCount = SyncService.followingList(me).filter { it != me }.toSet().size
    }

    suspend fun loadFollowers() {
        val me = Session.pubkey ?: return
        val map = Json.obj(runCatching { fetchFollowerCounts(listOf(me)) }.getOrNull())
        if (map == null) {
            if (followerCount == null) followerCount = 0
            return
        }
        followerCount = map.int(me)
    }

    suspend fun loadRelays() {
        relayCount = runCatching { getConnectedRelayCount().toInt() }.getOrNull()
    }

    fun refresh() {
        viewModelScope.launch { loadProfile() }
        viewModelScope.launch { loadFollowing() }
        viewModelScope.launch { loadFollowers() }
        viewModelScope.launch { loadRelays() }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun SidebarSheet(onDismiss: () -> Unit) {
    ScopedViewModels { SidebarContent(onDismiss) }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun SidebarContent(onDismiss: () -> Unit) {
    val model: SidebarViewModel = viewModel()
    val me = Session.pubkey ?: ""
    val profile = ProfileCache.profiles[me]
    val haptics = rememberHaptics()
    LaunchedEffect(Unit) { model.refresh() }
    LaunchedEffect(DataBus.feedVersion) { model.loadFollowing() }
    LaunchedEffect(DataBus.profileVersion) { if (me.isNotEmpty()) ProfileCache.refresh(me) }

    fun open(route: Route) {
        if (me.isEmpty()) return
        onDismiss()
        Router.push(route)
    }

    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).navigationBarsPadding().padding(bottom = 16.dp).testTag("sidebar")) {
        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 16.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(
                    Modifier.fillMaxWidth().testTag("sidebar-header").combinedClickable(
                        onClick = { open(Route.Profile(me)) },
                        onLongClick = {
                            val npub = Session.npub ?: return@combinedClickable
                            SecureClipboard.copy(npub, sensitive = false)
                            ToastCenter.show(L("copiedNpub"), ToastStyle.SUCCESS)
                        },
                    ),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    ProfileAvatar(me, size = 60.dp)
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(profile?.givenName ?: L("anonymous"), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        profile?.nip05?.ifEmpty { null }?.let {
                            Text(it, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        Text(Profile.shortNpub(me), style = MaterialTheme.typography.bodyMedium, fontFamily = FontFamily.Monospace, color = AppColors.textSecondary, maxLines = 1)
                    }
                }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    CountButton(model.followingCount, L("followingCount"), "sidebar-following-count") { open(Route.FollowList(me, FollowListMode.FOLLOWING)) }
                    CountButton(model.followerCount, L(if (model.followerCount == 1) "followerSingular" else "followers"), "sidebar-followers-count") {
                        open(Route.FollowList(me, FollowListMode.FOLLOWERS))
                    }
                }
            }
            FilledTonalIconButton(onClick = onDismiss, modifier = Modifier.size(36.dp).testTag("sidebar-close")) {
                Icon(Icons.Filled.Close, L("close"), Modifier.size(18.dp))
            }
        }
        SidebarGroup {
            SidebarRow(L("profile"), Icons.Outlined.Person, "sidebar-profile") { open(Route.Profile(me)) }
            SidebarRow(L("reads"), Icons.AutoMirrored.Outlined.Article, "sidebar-reads") { open(Route.Reads) }
            SidebarRow(L("liveTitle"), Icons.Outlined.Sensors, "sidebar-live") { open(Route.LiveStreams) }
            SidebarRow(L("listsTitle"), Icons.AutoMirrored.Outlined.List, "sidebar-lists") { open(Route.FollowSets) }
            SidebarRow(L("bookmarks"), Icons.Outlined.BookmarkBorder, "sidebar-bookmarks") { open(Route.Bookmarks) }
        }
        SidebarGroup {
            val badge = if (Session.accounts.size > 1) Session.accounts.size else 0
            SidebarRow(L("switchAccount"), Icons.Outlined.People, "sidebar-switch-account", badge) {
                onDismiss()
                App.scope.launch {
                    delay(400)
                    Router.present(AppSheet.SwitchAccount)
                }
            }
            SidebarRow(L("settings"), Icons.Outlined.Settings, "sidebar-settings") { open(Route.Settings) }
        }
        Text(
            L("authAppearance"),
            style = MaterialTheme.typography.labelLarge,
            color = AppColors.textSecondary,
            modifier = Modifier.padding(start = 20.dp, top = 12.dp, bottom = 8.dp),
        )
        val options = listOf(ThemePreference.SYSTEM to L("authThemeSystem"), ThemePreference.LIGHT to L("authThemeLight"), ThemePreference.DARK to L("authThemeDark"))
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp).testTag("sidebar-theme")) {
            options.forEachIndexed { index, (value, title) ->
                SegmentedButton(
                    selected = ThemeState.preference == value,
                    onClick = {
                        if (ThemeState.preference != value) haptics.selection()
                        ThemeState.applyTheme(value)
                    },
                    shape = SegmentedButtonDefaults.itemShape(index, options.size),
                ) { Text(title, maxLines = 1) }
            }
        }
        model.relayCount?.let { relays ->
            Row(
                Modifier.padding(start = 20.dp, top = 12.dp).testTag("sidebar-relay-count"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(if (relays > 0) Icons.Outlined.CellTower else Icons.Outlined.PortableWifiOff, null, Modifier.size(16.dp), tint = AppColors.textSecondary)
                Text(L("authConnectedRelays", "count" to relays), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
            }
        }
    }
}

@Composable
private fun SidebarGroup(content: @Composable () -> Unit) {
    Column(Modifier.padding(top = 12.dp)) {
        HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = AppColors.divider)
        content()
    }
}

@Composable
private fun SidebarRow(title: String, icon: ImageVector, tag: String, badge: Int = 0, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(title) },
        leadingContent = { Icon(icon, null) },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (badge > 0) Text("$badge", color = AppColors.textSecondary)
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = AppColors.textTertiary)
            }
        },
        colors = ListItemDefaults.colors(containerColor = AppColors.background),
        modifier = Modifier.testTag(tag).combinedClickableRow(onClick),
    )
}

@OptIn(ExperimentalFoundationApi::class)
private fun Modifier.combinedClickableRow(onClick: () -> Unit) = combinedClickable(onClick = onClick)

@Composable
private fun CountButton(value: Int?, label: String, tag: String, onClick: () -> Unit) {
    Row(
        Modifier.testTag(tag).combinedClickableRow(onClick).padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        AnimatedContent(value, label = "count") { shown ->
            if (shown != null) {
                Text(Sats.compact(shown.toLong()), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = AppColors.textPrimary)
            } else {
                CircularProgressIndicator(Modifier.size(12.dp), strokeWidth = 1.5.dp, color = AppColors.textSecondary)
            }
        }
        Text(label, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, maxLines = 1)
    }
}
