package me.untreu.qiqstr.ui.followsets

import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.qiqstr.core.dbSearchProfiles
import com.qiqstr.core.fetchEventsFromRelays
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.services.FollowSet
import me.untreu.qiqstr.data.services.FollowSetService
import me.untreu.qiqstr.data.services.RelayConfig
import me.untreu.qiqstr.data.services.SearchService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.explore.ExploreUserRow

sealed interface FollowSetEditorMode {
    val id: String

    object Create : FollowSetEditorMode { override val id get() = "create" }
    data class Details(val set: FollowSet) : FollowSetEditorMode { override val id get() = "details-${set.id}" }
    data class Members(val set: FollowSet) : FollowSetEditorMode { override val id get() = "members-${set.id}" }
}

private class MemberSearch {
    var query by mutableStateOf("")
    var results by mutableStateOf<List<Profile>>(emptyList())
        private set
    var isSearching by mutableStateOf(false)
        private set
    var hasSearched by mutableStateOf(false)
        private set
    private var job: Job? = null
    private val limit = 30

    val trimmedQuery: String get() = query.trim()

    fun update(text: String, scope: kotlinx.coroutines.CoroutineScope) {
        query = text
        job?.cancel()
        val trimmed = trimmedQuery
        if (trimmed.isEmpty()) {
            results = emptyList()
            isSearching = false
            hasSearched = false
            return
        }
        if (SearchService.looksSecret(trimmed)) {
            results = emptyList()
            ToastCenter.show(L("searchSecretBlocked"), ToastStyle.ERROR)
            return
        }
        isSearching = true
        job = scope.launch {
            delay(300)
            run(trimmed)
            isSearching = false
            hasSearched = true
        }
    }

    private suspend fun run(text: String) {
        pubkey(text)?.let { hex ->
            ProfileCache.refresh(hex)
            if (ProfileCache.profile(hex) == null) {
                SyncService.syncProfile(hex, force = true)
                ProfileCache.refresh(hex)
            }
            results = listOf(ProfileCache.profile(hex) ?: Profile(hex))
            return
        }
        val local = Json.array(runCatching { dbSearchProfiles(text, limit.toUInt()) }.getOrNull()).map { Profile.from(it) }.filter { it.pubkey.isNotEmpty() }
        results = local
        hasSearched = true
        val remote = remote(text)
        val seen = results.map { it.pubkey }.toMutableSet()
        val extra = remote.filter { seen.add(it.pubkey) }
        extra.forEach { if (ProfileCache.profile(it.pubkey) == null) ProfileCache.set(it) }
        results = (results + extra).take(limit)
    }

    private fun pubkey(input: String): String? {
        if (input.contains(" ")) return null
        val stripped = input.replace("https://njump.me/", "")
        Nip19.pubkeyHex(stripped)?.let { return it }
        val tlv = Nip19.decodeTLV(stripped) ?: return null
        return if (tlv.str("type") == "nprofile") tlv.str("pubkey") else null
    }

    private suspend fun remote(text: String): List<Profile> {
        val filter = Json.string(mapOf("kinds" to listOf(0), "search" to text, "limit" to 20))
        val events = Json.array(runCatching { fetchEventsFromRelays(filter, listOf(RelayConfig.vertexRelayUrl), 9u) }.getOrNull())
        val seen = HashSet<String>()
        return events.mapNotNull { event ->
            if (event.int("kind") != 0) return@mapNotNull null
            val pubkey = event.str("pubkey") ?: return@mapNotNull null
            if (!seen.add(pubkey)) return@mapNotNull null
            val metadata = Json.obj(event.text("content")) ?: return@mapNotNull null
            Profile.from(metadata, pubkey).copy(pubkey = pubkey)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FollowSetEditorSheet(mode: FollowSetEditorMode, onDismiss: () -> Unit, onCreated: ((FollowSet) -> Unit)? = null) {
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    val showsDetails = mode !is FollowSetEditorMode.Members
    val showsMembers = mode !is FollowSetEditorMode.Details
    var title by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }
    var selected by remember { mutableStateOf<List<String>>(emptyList()) }
    var saving by remember { mutableStateOf(false) }
    var followingProfiles by remember { mutableStateOf<List<Profile>>(emptyList()) }
    val search = remember { MemberSearch() }
    val titleFocus = remember { FocusRequester() }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = showsMembers, confirmValueChange = { !saving })
    val navigationTitle = when (mode) {
        FollowSetEditorMode.Create -> L("createList")
        is FollowSetEditorMode.Details -> L("exploreEditList")
        is FollowSetEditorMode.Members -> L("exploreAddMembers")
    }
    val canSave = !saving && (!showsDetails || title.isNotBlank())

    LaunchedEffect(mode.id) {
        when (mode) {
            FollowSetEditorMode.Create -> Unit
            is FollowSetEditorMode.Details -> { title = mode.set.title; description = mode.set.description }
            is FollowSetEditorMode.Members -> selected = mode.set.pubkeys
        }
        if (showsDetails) runCatching { titleFocus.requestFocus() }
        val me = Session.pubkey ?: return@LaunchedEffect
        if (!showsMembers) return@LaunchedEffect
        val follows = SyncService.followingList(me).filter { it != me }.take(200)
        ProfileCache.load(follows)
        followingProfiles = follows.map { ProfileCache.profile(it) ?: Profile(it) }.sortedBy { it.bestName.lowercase() }
    }

    fun toggle(pubkey: String) {
        selected = if (pubkey in selected) selected - pubkey else selected + pubkey
    }

    fun save() {
        saving = true
        scope.launch {
            try {
                when (mode) {
                    FollowSetEditorMode.Create -> {
                        val created = FollowSetService.create(title, description, selected)
                        ToastCenter.show(L("exploreListCreated"), ToastStyle.SUCCESS)
                        onCreated?.invoke(created)
                    }
                    is FollowSetEditorMode.Details -> {
                        FollowSetService.update(mode.set.id, title, description)
                        ToastCenter.show(L("exploreListUpdated"), ToastStyle.SUCCESS)
                    }
                    is FollowSetEditorMode.Members -> {
                        FollowSetService.setMembers(selected, mode.set.id)
                        ToastCenter.show(L("exploreListUpdated"), ToastStyle.SUCCESS)
                    }
                }
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                saving = false
                onDismiss()
            } catch (error: Throwable) {
                saving = false
                ToastCenter.error(error)
            }
        }
    }

    val candidates = if (search.trimmedQuery.isEmpty()) followingProfiles else search.results
    ModalBottomSheet(onDismissRequest = { if (!saving) onDismiss() }, sheetState = sheetState, containerColor = AppColors.background) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.testTag("followset-cancel")) { TextAction(L("cancel"), onDismiss, enabled = !saving) }
            Text(navigationTitle, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
            Box(Modifier.testTag("followset-save")) {
                AnimatedContent(saving, label = "followset-save") { busy ->
                    if (busy) {
                        CircularProgressIndicator(Modifier.padding(horizontal = 20.dp).size(20.dp), strokeWidth = 2.dp, color = AppColors.textPrimary)
                    } else {
                        TextAction(if (mode == FollowSetEditorMode.Create) L("create") else L("save"), ::save, enabled = canSave)
                    }
                }
            }
        }
        LazyColumn(Modifier.fillMaxWidth().imePadding()) {
            if (showsDetails) {
                item(key = "details") {
                    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        OutlinedTextField(
                            value = title,
                            onValueChange = { title = it },
                            label = { Text(L("listNameHint")) },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth().focusRequester(titleFocus).testTag("followset-name-field"),
                        )
                        OutlinedTextField(
                            value = description,
                            onValueChange = { description = it },
                            label = { Text(L("listDescriptionHint")) },
                            minLines = 1,
                            maxLines = 4,
                            modifier = Modifier.fillMaxWidth().testTag("followset-description-field"),
                        )
                    }
                }
            }
            if (showsMembers) {
                if (selected.isNotEmpty()) {
                    item(key = "selected-header") { SectionLabel("${L("exploreSelected")} · ${selected.size}") }
                    item(key = "selected") {
                        LazyRow(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                        ) {
                            items(selected, key = { it }) { pubkey -> SelectedMemberChip(pubkey) { toggle(pubkey) } }
                        }
                    }
                }
                item(key = "search-header") { SectionLabel(if (search.trimmedQuery.isEmpty()) L("following") else L("users")) }
                item(key = "search") {
                    OutlinedTextField(
                        value = search.query,
                        onValueChange = { search.update(it, scope) },
                        placeholder = { Text(L("searchUsers")) },
                        leadingIcon = { Icon(Icons.Outlined.Search, null) },
                        trailingIcon = { if (search.isSearching) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = AppColors.textPrimary) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp).testTag("followset-member-search"),
                    )
                }
                items(candidates, key = { "candidate-${it.pubkey}" }) { profile ->
                    val isSelected = profile.pubkey in selected
                    Row(
                        Modifier.fillMaxWidth().clickable { toggle(profile.pubkey) }.padding(horizontal = 16.dp, vertical = 6.dp)
                            .testTag("followset-candidate-${profile.pubkey}"),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        ExploreUserRow(profile, Modifier.weight(1f), showsFollowButton = false, avatarSize = 38.dp)
                        AnimatedContent(isSelected, label = "candidate-check") { on ->
                            Icon(
                                if (on) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                                null,
                                Modifier.size(26.dp),
                                tint = if (on) AppColors.textPrimary else AppColors.textSecondary,
                            )
                        }
                    }
                }
                if (search.trimmedQuery.isNotEmpty() && search.hasSearched && !search.isSearching && search.results.isEmpty()) {
                    item(key = "no-users") {
                        Text(L("noUsersFound"), color = AppColors.textSecondary, modifier = Modifier.padding(16.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.SemiBold,
        color = AppColors.textSecondary,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
    )
}

@Composable
private fun SelectedMemberChip(pubkey: String, onRemove: () -> Unit) {
    val name = ProfileCache.profiles[pubkey]?.bestName ?: Profile.shortNpub(pubkey)
    val label = "${L("removeFromList")} $name"
    Column(
        Modifier.width(60.dp).clickable(onClick = onRemove).semantics { contentDescription = label }.testTag("followset-selected-$pubkey"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box {
            ProfileAvatar(pubkey, size = 44.dp)
            Icon(
                Icons.Filled.Cancel,
                null,
                tint = AppColors.textPrimary,
                modifier = Modifier.align(Alignment.TopEnd).offset(x = 4.dp, y = (-4).dp).size(18.dp).background(AppColors.background, CircleShape),
            )
        }
        Text(name, style = MaterialTheme.typography.labelSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}
