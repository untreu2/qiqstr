package me.untreu.qiqstr.ui.profile

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.FollowListMode
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.core.components.BackTopBar
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.LoadingView
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.SyncService

class FollowListViewModel(val pubkey: String, val mode: FollowListMode) : ViewModel() {
    var pubkeys by mutableStateOf<List<String>>(emptyList())
        private set
    var isLoading by mutableStateOf(true)
        private set
    var hasLoaded by mutableStateOf(false)
        private set
    var isRefreshing by mutableStateOf(false)
        private set
    var query by mutableStateOf("")

    fun filtered(): List<String> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return pubkeys
        Nip19.pubkeyHex(q)?.let { hex -> return pubkeys.filter { it == hex } }
        return pubkeys.filter { pk ->
            val p = ProfileCache.profiles[pk] ?: return@filter pk.startsWith(q)
            p.name.lowercase().contains(q) || p.displayName.lowercase().contains(q) ||
                p.nip05.lowercase().contains(q) || p.lud16.lowercase().contains(q)
        }
    }

    fun start() {
        viewModelScope.launch {
            if (ProfileCache.profile(pubkey) == null) ProfileCache.load(listOf(pubkey))
            loadLocal()
            refresh()
        }
    }

    fun pullRefresh() {
        if (isRefreshing) return
        isRefreshing = true
        viewModelScope.launch {
            refresh()
            isRefreshing = false
        }
    }

    suspend fun loadLocal() {
        if (mode != FollowListMode.FOLLOWING) return
        val local = ProfileDataSource.following(pubkey)
        if (local.isNotEmpty() || !hasLoaded) apply(local, final = false)
    }

    suspend fun refresh() {
        when (mode) {
            FollowListMode.FOLLOWING -> {
                SyncService.syncFollowingList(pubkey, force = true)
                apply(ProfileDataSource.following(pubkey), final = true)
            }
            FollowListMode.FOLLOWERS -> {
                val found = ProfileDataSource.followers(pubkey)
                apply(if (found.isEmpty() && pubkeys.isNotEmpty()) pubkeys else found, final = true)
            }
        }
        pubkeys.chunked(400).forEach { ProfileCache.load(it) }
    }

    private fun apply(list: List<String>, final: Boolean) {
        val seen = HashSet<String>()
        pubkeys = list.filter { it.isNotEmpty() && seen.add(it) }
        if (final || pubkeys.isNotEmpty()) {
            isLoading = false
            hasLoaded = true
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FollowListScreen(pubkey: String, mode: FollowListMode) {
    val model = viewModel(key = "follows-$pubkey-$mode") { FollowListViewModel(pubkey, mode) }
    LaunchedEffect(Unit) { model.start() }
    LaunchedEffect(DataBus.feedVersion) { if (model.hasLoaded) model.loadLocal() }
    val scroll = TopAppBarDefaults.pinnedScrollBehavior()
    val title = if (mode == FollowListMode.FOLLOWING) L("following") else L("followers").replaceFirstChar { it.titlecase() }
    val subtitle = ProfileCache.profiles[pubkey]?.bestName.orEmpty()
    Scaffold(
        modifier = Modifier.nestedScroll(scroll.nestedScrollConnection),
        containerColor = AppColors.background,
        topBar = {
            BackTopBar(title = if (subtitle.isEmpty()) title else "$title · $subtitle", scrollBehavior = scroll)
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            ProfileSearchField(model.query, { model.query = it }, L("searchByNameOrNpub"), tag = "follow-list-search")
            val items = model.filtered()
            PullToRefreshBox(isRefreshing = model.isRefreshing, onRefresh = model::pullRefresh, modifier = Modifier.fillMaxSize()) {
                when {
                    model.isLoading && model.pubkeys.isEmpty() -> LoadingView()
                    model.pubkeys.isEmpty() -> Box(Modifier.fillMaxSize()) {
                        EmptyStateView(
                            icon = Icons.Outlined.Group,
                            title = if (mode == FollowListMode.FOLLOWING) L("noFollowingUsers") else L("profileNoFollowers"),
                            actionTitle = L("retry"),
                            action = model::pullRefresh,
                        )
                    }
                    items.isEmpty() -> Box(Modifier.fillMaxSize()) {
                        EmptyStateView(icon = Icons.Outlined.Search, title = L("noResultsFound"), message = L("trySearchingDifferentTerm"))
                    }
                    else -> LazyColumn(Modifier.fillMaxSize().testTag("follow-list")) {
                        item {
                            Text(
                                "${Sats.compact(model.pubkeys.size.toLong())} ${if (mode == FollowListMode.FOLLOWING) L("followingCount") else L("followers")}",
                                style = MaterialTheme.typography.labelLarge,
                                fontWeight = FontWeight.SemiBold,
                                color = AppColors.textSecondary,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                            )
                        }
                        items(items, key = { it }) { pk -> UserRow(pk, showFollow = true) }
                    }
                }
            }
        }
    }
}
