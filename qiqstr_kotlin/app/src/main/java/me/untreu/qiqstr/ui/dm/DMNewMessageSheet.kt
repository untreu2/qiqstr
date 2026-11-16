package me.untreu.qiqstr.ui.dm

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SearchBar
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.remember
import androidx.compose.material3.TextButton
import me.untreu.qiqstr.data.sync.Session
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.WindowInsets
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Profile

class DMUserPickerViewModel : ViewModel() {
    var query by mutableStateOf("")
    var followingProfiles by mutableStateOf<List<Profile>>(emptyList())
        private set
    var searchResults by mutableStateOf<List<Profile>>(emptyList())
        private set
    var isSearching by mutableStateOf(false)
        private set
    var isLoadingFollowing by mutableStateOf(true)
        private set
    private val service = DMService

    val trimmedQuery: String get() = query.trim()

    val directPubkey: String? get() = Nip19.pubkeyHex(trimmedQuery)

    val recentPeers: List<String> get() = service.conversations.filterNot { DMService.isGroup(it.peer) }.take(8).map { it.peer }

    val results: List<Profile>
        get() {
            if (trimmedQuery.isEmpty()) return followingProfiles.map(::resolved)
            if (directPubkey != null) return emptyList()
            val needle = trimmedQuery.lowercase()
            val localMatches = followingProfiles.map(::resolved).filter { profile ->
                profile.name.lowercase().contains(needle) || profile.displayName.lowercase().contains(needle) || profile.nip05.lowercase().contains(needle)
            }
            val seen = localMatches.map { it.pubkey }.toMutableSet()
            val merged = localMatches.toMutableList()
            for (profile in searchResults) if (seen.add(profile.pubkey)) merged.add(profile)
            return merged.sortedWith(
                compareBy<Profile> { !service.isFollowing(it.pubkey) }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.bestName },
            )
        }

    fun isFollowing(pubkey: String) = service.isFollowing(pubkey)

    private fun resolved(profile: Profile): Profile = ProfileCache.profile(profile.pubkey) ?: profile

    suspend fun loadFollowing() {
        val pubkeys = service.followingPubkeys()
        ProfileCache.load(pubkeys)
        followingProfiles = pubkeys.map { ProfileCache.profile(it) ?: Profile(it) }.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.bestName })
        isLoadingFollowing = false
    }

    suspend fun search() {
        val current = trimmedQuery
        if (current.isEmpty() || directPubkey != null) {
            searchResults = emptyList()
            isSearching = false
            return
        }
        isSearching = true
        delay(250)
        if (current != trimmedQuery) return
        val found = service.searchProfiles(current)
        if (current != trimmedQuery) return
        searchResults = found
        isSearching = false
    }

    fun paste(value: String?) {
        value?.trim()?.let { query = it }
    }
}

@Composable
fun DMNewMessageSheet(onDismiss: () -> Unit, onSelect: (String) -> Unit) {
    val model: DMUserPickerViewModel = viewModel()
    var newGroup by remember { mutableStateOf(false) }
    if (newGroup) { DMNewGroupScreen(onDismiss = { newGroup = false }, onCreated = onSelect); return }
    val clipboard = LocalClipboardManager.current
    LaunchedEffect(Unit) { model.loadFollowing() }
    LaunchedEffect(model.query) { model.search() }
    DisposableEffect(Unit) { onDispose { model.query = "" } }

    Column(Modifier.fillMaxSize().imePadding().testTag("dm-picker")) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onDismiss, modifier = Modifier.testTag("dm-picker-cancel")) { Icon(Icons.Outlined.Close, L("cancel")) }
            Text(L("newMessage"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
            IconButton(onClick = { model.paste(clipboard.getText()?.text) }, modifier = Modifier.testTag("dm-picker-paste")) {
                Icon(Icons.Outlined.ContentPaste, L("dmPaste"))
            }
        }
        SearchBar(
            inputField = {
                SearchBarDefaults.InputField(
                    query = model.query,
                    onQueryChange = { model.query = it },
                    onSearch = {},
                    expanded = false,
                    onExpandedChange = {},
                    placeholder = { Text(L("searchByNameOrNpub")) },
                    leadingIcon = { Icon(Icons.Outlined.Search, null) },
                    trailingIcon = {
                        if (model.query.isNotEmpty()) IconButton(onClick = { model.query = "" }) { Icon(Icons.Outlined.Close, L("cancel")) }
                    },
                    modifier = Modifier.testTag("dm-picker-search"),
                )
            },
            expanded = false,
            onExpandedChange = {},
            windowInsets = WindowInsets(0),
            colors = SearchBarDefaults.colors(containerColor = AppColors.inputFill),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 8.dp),
        ) {}
        Box(Modifier.fillMaxSize()) {
            val direct = model.directPubkey
            val results = model.results
            val recent = model.recentPeers
            LazyColumn(Modifier.fillMaxSize()) {
                if (model.trimmedQuery.isEmpty() && Session.canSign) item("new-group") {
                    TextButton(onClick = { newGroup = true }, modifier = Modifier.fillMaxWidth().testTag("dm-new-group")) { Icon(Icons.Outlined.Group, null); Text(L("dmNewGroup"), Modifier.padding(12.dp)) }
                }
                if (direct != null) {
                    item(key = "direct-header") { SectionLabel(L("dmStartChat")) }
                    item(key = "direct") {
                        DMUserRow(direct, Profile.shortNpub(direct), model.isFollowing(direct), Modifier.clickable { onSelect(direct) }.testTag("dm-picker-direct"))
                    }
                }
                if (model.trimmedQuery.isEmpty() && recent.isNotEmpty()) {
                    item(key = "recent-header") { SectionLabel(L("dmRecent")) }
                    item(key = "recent") {
                        LazyRow(contentPadding = PaddingValues(horizontal = 20.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                            items(recent, key = { it }) { peer -> DMRecentChip(peer) { onSelect(peer) } }
                        }
                    }
                }
                if (results.isNotEmpty()) {
                    item(key = "results-header") { SectionLabel(if (model.trimmedQuery.isEmpty()) L("following") else L("users")) }
                    items(results, key = { "user-${it.pubkey}" }) { profile ->
                        DMUserRow(
                            profile.pubkey,
                            profile.nip05.ifEmpty { Profile.shortNpub(profile.pubkey) },
                            model.isFollowing(profile.pubkey),
                            Modifier.clickable { onSelect(profile.pubkey) }.testTag("dm-picker-user-${profile.pubkey}"),
                        )
                    }
                }
                item(key = "bottom") { Spacer(Modifier.height(24.dp)) }
            }
            if (direct == null && results.isEmpty()) {
                val overlay = Modifier.align(Alignment.TopCenter).padding(top = 108.dp)
                when {
                    model.trimmedQuery.isEmpty() && model.isLoadingFollowing -> CircularProgressIndicator(overlay, color = AppColors.textPrimary)
                    model.trimmedQuery.isEmpty() && recent.isEmpty() -> EmptyStateView(Icons.Outlined.Group, L("startConversationBy"), L("searchByNameOrNpub"), modifier = overlay)
                    model.trimmedQuery.isEmpty() -> Unit
                    model.isSearching -> Column(overlay, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        CircularProgressIndicator(color = AppColors.textPrimary)
                        Text(L("searchingForUsers"), color = AppColors.textSecondary, style = MaterialTheme.typography.bodyMedium)
                    }
                    else -> EmptyStateView(Icons.Outlined.Search, L("noUsersFound"), L("dmPasteNpubHint"), modifier = overlay)
                }
            }
        }
    }
}

@Composable
private fun SectionLabel(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.labelLarge,
        color = AppColors.textSecondary,
        modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 16.dp, bottom = 6.dp),
    )
}

@Composable
private fun DMUserRow(pubkey: String, subtitle: String, isFollowing: Boolean, modifier: Modifier = Modifier) {
    val profile = ProfileCache.profiles[pubkey]
    Row(
        modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        ProfileAvatar(pubkey, size = 42.dp)
        Column(Modifier.weight(1f)) {
            Text(profile?.bestName ?: Profile.shortNpub(pubkey), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (isFollowing) {
            Text(
                L("following"),
                style = MaterialTheme.typography.labelMedium,
                color = AppColors.textSecondary,
                modifier = Modifier.background(AppColors.tile, CircleShape).padding(horizontal = 8.dp, vertical = 4.dp),
            )
        }
    }
}

@Composable
private fun DMRecentChip(pubkey: String, onClick: () -> Unit) {
    val profile = ProfileCache.profiles[pubkey]
    Column(
        Modifier.width(64.dp).clickable(onClick = onClick).testTag("dm-picker-recent-$pubkey"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        ProfileAvatar(pubkey, size = 56.dp)
        Text(
            profile?.bestName ?: Profile.shortNpub(pubkey),
            style = MaterialTheme.typography.labelMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
    }
}
