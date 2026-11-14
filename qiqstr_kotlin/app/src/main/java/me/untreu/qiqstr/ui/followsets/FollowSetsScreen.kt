package me.untreu.qiqstr.ui.followsets

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.ListAlt
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.PersonAdd
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.LoadingView
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.services.FollowSet
import me.untreu.qiqstr.data.services.FollowSetService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.ui.profile.ProfileSearchField

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FollowSetsScreen() {
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    var editor by remember { mutableStateOf<FollowSetEditorMode?>(null) }
    var pendingDelete by remember { mutableStateOf<FollowSet?>(null) }
    var query by rememberSaveable { mutableStateOf("") }
    var refreshing by remember { mutableStateOf(false) }
    val scroll = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    LaunchedEffect(Unit) { if (!FollowSetService.isLoaded) FollowSetService.load() else FollowSetService.refresh() }

    fun filtered(sets: List<FollowSet>): List<FollowSet> {
        val q = query.trim()
        if (q.isEmpty()) return sets
        return sets.filter { it.displayTitle.contains(q, ignoreCase = true) || it.description.contains(q, ignoreCase = true) }
    }

    fun toggleFavorite(set: FollowSet) {
        FollowSetService.toggleFavorite(set.id)
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
    }

    fun delete(set: FollowSet) {
        scope.launch {
            try {
                FollowSetService.delete(set.id)
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
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
                title = { Text(L("listsTitle")) },
                navigationIcon = {
                    IconButton(onClick = { Router.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) }
                },
                actions = {
                    IconButton(onClick = { editor = FollowSetEditorMode.Create }, modifier = Modifier.testTag("followsets-create")) {
                        Icon(Icons.Outlined.Add, L("createList"))
                    }
                },
                scrollBehavior = scroll,
                colors = TopAppBarDefaults.largeTopAppBarColors(containerColor = AppColors.background),
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            ProfileSearchField(query, { query = it }, L("exploreSearchLists"), tag = "followsets-search")
            val own = filtered(FollowSetService.sets)
            val followed = filtered(FollowSetService.followedSets)
            PullToRefreshBox(
                isRefreshing = refreshing,
                onRefresh = { refreshing = true; scope.launch { FollowSetService.refresh(); refreshing = false } },
                modifier = Modifier.fillMaxSize(),
            ) {
                when {
                    query.isNotEmpty() && own.isEmpty() && followed.isEmpty() ->
                        EmptyStateView(icon = Icons.Outlined.Search, title = L("noResultsFound"), message = L("trySearchingDifferentTerm"))
                    FollowSetService.sets.isEmpty() && FollowSetService.followedSets.isEmpty() -> {
                        if (!FollowSetService.isLoaded || FollowSetService.isSyncing) LoadingView()
                        else EmptyStateView(
                            icon = Icons.AutoMirrored.Outlined.ListAlt,
                            title = L("noLists"),
                            message = L("noListsDescription"),
                            actionTitle = L("createList"),
                        ) { editor = FollowSetEditorMode.Create }
                    }
                    else -> LazyColumn(Modifier.fillMaxSize().testTag("followsets-list")) {
                        if (own.isNotEmpty()) {
                            header(L("exploreMyLists"))
                            items(own, key = { "own-${it.id}" }) { set ->
                                OwnRow(
                                    set,
                                    onFavorite = { toggleFavorite(set) },
                                    onEdit = { editor = FollowSetEditorMode.Details(set) },
                                    onMembers = { editor = FollowSetEditorMode.Members(set) },
                                    onDelete = { pendingDelete = set },
                                )
                            }
                            if (query.isEmpty()) {
                                item(key = "own-footer") {
                                    Text(
                                        L("listsSubtitle"),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = AppColors.textSecondary,
                                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                                    )
                                }
                            }
                        }
                        if (followed.isNotEmpty()) {
                            header(L("listsFromFollows"))
                            items(followed, key = { "followed-${it.id}" }) { set -> FollowedRow(set) { toggleFavorite(set) } }
                        }
                    }
                }
            }
        }
    }

    editor?.let { mode ->
        FollowSetEditorSheet(mode, onDismiss = { editor = null }) { created -> Router.push(Route.FollowSet(created.id)) }
    }
    pendingDelete?.let { set ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text("${L("deleteList")}?") },
            text = { Text(L("exploreDeleteListConfirm", "title" to set.displayTitle)) },
            confirmButton = {
                Box(Modifier.testTag("followsets-confirm-delete")) {
                    TextAction(L("deleteList"), { pendingDelete = null; delete(set) }, color = AppColors.error)
                }
            },
            dismissButton = { TextAction(L("cancel"), { pendingDelete = null }) },
        )
    }
}

private fun LazyListScope.header(title: String) {
    item(key = "header-$title") {
        Text(
            title,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            color = AppColors.textSecondary,
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp),
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun OwnRow(set: FollowSet, onFavorite: () -> Unit, onEdit: () -> Unit, onMembers: () -> Unit, onDelete: () -> Unit) {
    val favorite = FollowSetService.isFavorite(set.id)
    var menu by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        when (value) {
            SwipeToDismissBoxValue.EndToStart -> onDelete()
            SwipeToDismissBoxValue.StartToEnd -> onFavorite()
            SwipeToDismissBoxValue.Settled -> Unit
        }
        false
    })
    SwipeToDismissBox(
        state = state,
        backgroundContent = {
            val toDelete = state.dismissDirection == SwipeToDismissBoxValue.EndToStart
            SwipeBackground(
                icon = if (toDelete) Icons.Outlined.Delete else Icons.Outlined.PushPin,
                label = if (toDelete) L("delete") else if (favorite) L("removeFromFeed") else L("addToFeed"),
                color = if (toDelete) AppColors.error else AppColors.settingsTile,
                alignEnd = toDelete,
            )
        },
        modifier = Modifier.testTag("followset-row-${set.dTag}"),
    ) {
        Box(Modifier.background(AppColors.background)) {
            FollowSetRow(
                set,
                isFavorite = favorite,
                modifier = Modifier.combinedClickable(
                    onClick = { Router.push(Route.FollowSet(set.id)) },
                    onLongClick = { haptics.performHapticFeedback(HapticFeedbackType.LongPress); menu = true },
                ),
            )
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                FavoriteItem(favorite) { menu = false; onFavorite() }
                MenuItem(L("exploreEditList"), Icons.Outlined.Edit) { menu = false; onEdit() }
                MenuItem(L("exploreAddMembers"), Icons.Outlined.PersonAdd) { menu = false; onMembers() }
                HorizontalDivider()
                MenuItem(L("deleteList"), Icons.Outlined.Delete, destructive = true) { menu = false; onDelete() }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun FollowedRow(set: FollowSet, onFavorite: () -> Unit) {
    val favorite = FollowSetService.isFavorite(set.id)
    var menu by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.StartToEnd) onFavorite()
        false
    })
    SwipeToDismissBox(
        state = state,
        enableDismissFromEndToStart = false,
        backgroundContent = {
            SwipeBackground(Icons.Outlined.PushPin, if (favorite) L("removeFromFeed") else L("addToFeed"), AppColors.settingsTile, alignEnd = false)
        },
        modifier = Modifier.testTag("followset-row-${set.pubkey}-${set.dTag}"),
    ) {
        Box(Modifier.background(AppColors.background)) {
            FollowSetRow(
                set,
                showsOwner = true,
                isFavorite = favorite,
                modifier = Modifier.combinedClickable(
                    onClick = { Router.push(Route.FollowSet(set.id)) },
                    onLongClick = { haptics.performHapticFeedback(HapticFeedbackType.LongPress); menu = true },
                ),
            )
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                FavoriteItem(favorite) { menu = false; onFavorite() }
                MenuItem(L("exploreViewAuthor"), Icons.Outlined.AccountCircle) { menu = false; Router.push(Route.Profile(set.pubkey)) }
            }
        }
    }
}

@Composable
private fun SwipeBackground(icon: ImageVector, label: String, color: Color, alignEnd: Boolean) {
    Row(
        Modifier.fillMaxSize().background(color).padding(horizontal = 20.dp),
        horizontalArrangement = if (alignEnd) Arrangement.End else Arrangement.Start,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, label, tint = Color.White)
    }
}

@Composable
internal fun FavoriteItem(favorite: Boolean, onClick: () -> Unit) {
    MenuItem(if (favorite) L("removeFromFeed") else L("addToFeed"), Icons.Outlined.PushPin, onClick = onClick)
}

@Composable
internal fun MenuItem(title: String, icon: ImageVector, destructive: Boolean = false, onClick: () -> Unit) {
    val color = if (destructive) AppColors.error else AppColors.textPrimary
    DropdownMenuItem(text = { Text(title, color = color) }, leadingIcon = { Icon(icon, null, tint = color) }, onClick = onClick)
}
