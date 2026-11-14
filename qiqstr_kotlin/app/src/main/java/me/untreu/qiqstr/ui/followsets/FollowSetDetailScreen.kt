package me.untreu.qiqstr.ui.followsets

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.ListAlt
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.PersonAdd
import androidx.compose.material.icons.outlined.PersonRemove
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberSwipeToDismissBoxState
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.LoadingView
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.services.FollowSet
import me.untreu.qiqstr.data.services.FollowSetService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.explore.ExploreUserMenu
import me.untreu.qiqstr.ui.explore.ExploreUserRow
import me.untreu.qiqstr.ui.profile.ProfileSearchField

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FollowSetDetailScreen(setId: String) {
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    val set = FollowSetService.set(withId = setId)
    var editor by remember { mutableStateOf<FollowSetEditorMode?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    var removing by remember { mutableStateOf<Set<String>>(emptySet()) }
    var query by rememberSaveable { mutableStateOf("") }
    var refreshing by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    val scroll = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    LaunchedEffect(Unit) { if (!FollowSetService.isLoaded) FollowSetService.load() }
    LaunchedEffect(set?.pubkeys) { set?.let { ProfileCache.load(it.pubkeys + it.pubkey) } }

    fun remove(pubkey: String, from: FollowSet) {
        removing = removing + pubkey
        scope.launch {
            try {
                FollowSetService.removeMember(pubkey, from = from.id)
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                ToastCenter.show(L("exploreMemberRemoved"), ToastStyle.SUCCESS)
            } catch (error: Throwable) {
                ToastCenter.error(error)
            } finally {
                removing = removing - pubkey
            }
        }
    }

    fun deleteSet() {
        val target = set ?: return
        Router.pop()
        App.scope.launch {
            try {
                FollowSetService.delete(target.id)
                ToastCenter.show(L("exploreListDeleted"), ToastStyle.SUCCESS)
            } catch (error: Throwable) {
                ToastCenter.error(error)
            }
        }
    }

    Scaffold(
        modifier = Modifier.nestedScroll(scroll.nestedScrollConnection),
        containerColor = AppColors.background,
        topBar = {
            LargeTopAppBar(
                title = { Text(set?.displayTitle ?: L("listsTitle"), maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { IconButton(onClick = { Router.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } },
                actions = {
                    if (set != null) {
                        val own = FollowSetService.isOwn(set)
                        val favorite = FollowSetService.isFavorite(set.id)
                        if (own) {
                            IconButton(onClick = { editor = FollowSetEditorMode.Members(set) }, modifier = Modifier.testTag("followset-add-members")) {
                                Icon(Icons.Outlined.PersonAdd, L("exploreAddMembers"))
                            }
                        }
                        Box {
                            IconButton(onClick = { menu = true }, modifier = Modifier.testTag("followset-more")) {
                                Icon(Icons.Outlined.MoreVert, L("exploreMoreOptions"))
                            }
                            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                                Box(Modifier.testTag("followset-toggle-feed")) {
                                    FavoriteItem(favorite) {
                                        menu = false
                                        FollowSetService.toggleFavorite(set.id)
                                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                    }
                                }
                                if (own) {
                                    Box(Modifier.testTag("followset-edit")) {
                                        MenuItem(L("exploreEditList"), Icons.Outlined.Edit) { menu = false; editor = FollowSetEditorMode.Details(set) }
                                    }
                                    HorizontalDivider()
                                    Box(Modifier.testTag("followset-delete")) {
                                        MenuItem(L("deleteList"), Icons.Outlined.Delete, destructive = true) { menu = false; confirmDelete = true }
                                    }
                                } else {
                                    MenuItem(L("exploreViewAuthor"), Icons.Outlined.AccountCircle) { menu = false; Router.push(Route.Profile(set.pubkey)) }
                                }
                            }
                        }
                    }
                },
                scrollBehavior = scroll,
                colors = TopAppBarDefaults.largeTopAppBarColors(containerColor = AppColors.background),
            )
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            when {
                set != null -> Content(
                    set,
                    query,
                    onQuery = { query = it },
                    removing = removing,
                    refreshing = refreshing,
                    onRefresh = { refreshing = true; scope.launch { FollowSetService.refresh(); refreshing = false } },
                    onAddMembers = { editor = FollowSetEditorMode.Members(set) },
                    onRemove = { remove(it, set) },
                )
                !FollowSetService.isLoaded || FollowSetService.isSyncing -> LoadingView()
                else -> EmptyStateView(icon = Icons.AutoMirrored.Outlined.ListAlt, title = L("exploreListNotFound"))
            }
        }
    }

    editor?.let { mode -> FollowSetEditorSheet(mode, onDismiss = { editor = null }) }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("${L("deleteList")}?") },
            text = { Text(L("exploreDeleteListConfirm", "title" to (set?.displayTitle ?: ""))) },
            confirmButton = {
                Box(Modifier.testTag("followset-confirm-delete")) {
                    TextAction(L("deleteList"), { confirmDelete = false; deleteSet() }, color = AppColors.error)
                }
            },
            dismissButton = { TextAction(L("cancel"), { confirmDelete = false }) },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Content(
    set: FollowSet,
    query: String,
    onQuery: (String) -> Unit,
    removing: Set<String>,
    refreshing: Boolean,
    onRefresh: () -> Unit,
    onAddMembers: () -> Unit,
    onRemove: (String) -> Unit,
) {
    val own = FollowSetService.isOwn(set)
    val members = run {
        val q = query.trim()
        if (q.isEmpty()) set.pubkeys
        else set.pubkeys.filter { pubkey ->
            val profile = ProfileCache.profiles[pubkey] ?: return@filter pubkey.contains(q, ignoreCase = true)
            profile.bestName.contains(q, ignoreCase = true) || profile.nip05.contains(q, ignoreCase = true)
        }
    }
    PullToRefreshBox(isRefreshing = refreshing, onRefresh = onRefresh, modifier = Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize().testTag("followset-members")) {
            item(key = "search") { ProfileSearchField(query, onQuery, L("exploreSearchMembers"), tag = "followset-search") }
            item(key = "info") {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (set.description.isNotEmpty()) Text(set.description, style = MaterialTheme.typography.bodyLarge)
                    if (!own) {
                        Row(
                            Modifier.fillMaxWidth().clickable { Router.push(Route.Profile(set.pubkey)) }.padding(vertical = 4.dp).testTag("followset-owner"),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            ProfileAvatar(set.pubkey, size = 28.dp)
                            Text(
                                L("exploreByAuthor", "name" to (ProfileCache.profiles[set.pubkey]?.bestName ?: Profile.shortNpub(set.pubkey))),
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.weight(1f),
                            )
                            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null, tint = AppColors.textTertiary)
                        }
                    }
                    if (FollowSetService.isFavorite(set.id)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Icon(Icons.Outlined.PushPin, null, Modifier.size(18.dp), tint = AppColors.textSecondary)
                            Text(L("exploreInFeed"), color = AppColors.textSecondary)
                        }
                    }
                }
            }
            if (set.pubkeys.isEmpty()) {
                item(key = "empty") {
                    EmptyStateView(
                        icon = Icons.Outlined.Group,
                        title = L("noMembersInList"),
                        message = if (own) null else L("noMembersInListDescription"),
                        actionTitle = if (own) L("exploreAddMembers") else null,
                        action = if (own) onAddMembers else null,
                    )
                }
            } else {
                item(key = "count") {
                    Text(
                        FollowSet.memberCountText(set.pubkeys.size),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = AppColors.textSecondary,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
                if (query.isNotEmpty() && members.isEmpty()) {
                    item(key = "no-results") {
                        EmptyStateView(icon = Icons.Outlined.Search, title = L("noResultsFound"), message = L("trySearchingDifferentTerm"))
                    }
                }
                items(members, key = { it }) { pubkey ->
                    MemberRow(pubkey, own, removing = pubkey in removing) { onRemove(pubkey) }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun MemberRow(pubkey: String, own: Boolean, removing: Boolean, onRemove: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart) onRemove()
        false
    })
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        enableDismissFromEndToStart = own,
        backgroundContent = {
            Row(
                Modifier.fillMaxSize().background(AppColors.error).padding(horizontal = 20.dp),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) { Icon(Icons.Outlined.PersonRemove, L("removeFromList"), tint = Color.White) }
        },
        modifier = Modifier.alpha(if (removing) 0.4f else 1f).testTag("followset-remove-$pubkey"),
    ) {
        Box(Modifier.background(AppColors.background)) {
            Box(
                Modifier.fillMaxWidth()
                    .combinedClickable(
                        onClick = { Router.push(Route.Profile(pubkey)) },
                        onLongClick = { haptics.performHapticFeedback(HapticFeedbackType.LongPress); menu = true },
                    )
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            ) {
                ExploreUserRow(ProfileCache.profiles[pubkey] ?: Profile(pubkey))
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                ExploreUserMenu(pubkey) { menu = false }
                if (own) {
                    HorizontalDivider()
                    MenuItem(L("removeFromList"), Icons.Outlined.PersonRemove, destructive = true) { menu = false; onRemove() }
                }
            }
        }
    }
}
