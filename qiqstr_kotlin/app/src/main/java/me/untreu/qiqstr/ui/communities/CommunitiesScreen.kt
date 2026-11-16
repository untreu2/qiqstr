package me.untreu.qiqstr.ui.communities

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Forum
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.*
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.*
import me.untreu.qiqstr.core.components.RemoteImage
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle

class CommunitiesViewModel(initialRelay: String?) : ViewModel() {
    var section by mutableStateOf(0)
    var query by mutableStateOf("")
    var relay by mutableStateOf(initialRelay ?: CommunityService.groupRelays.first())
    var groups by mutableStateOf<List<RelayGroup>>(emptyList())
        private set
    var communities by mutableStateOf<List<Community>>(emptyList())
        private set
    var channels by mutableStateOf<List<PublicChannel>>(emptyList())
        private set
    var busy by mutableStateOf(false)
        private set
    private var job: Job? = null
    fun load(refresh: Boolean = false) {
        job?.cancel()
        job = viewModelScope.launch {
            busy = true
            try {
                if (refresh || !CommunityService.hasLoaded) CommunityService.load()
                when (section) { 0 -> groups = CommunityService.discoverGroups(relay); 1 -> communities = CommunityService.discoverCommunities(); 2 -> channels = CommunityService.discoverChannels() }
            } catch (error: CancellationException) { throw error } catch (error: Throwable) { ToastCenter.error(error) } finally { busy = false }
        }
    }
    fun matches(vararg fields: String) = query.isBlank() || fields.any { it.contains(query.trim(), ignoreCase = true) }
    fun openLink(raw: String) {
        val text = raw.trim()
        RelayGroup.link(text)?.let { Router.push(Route.RelayGroup(it.id)); return }
        val link = NostrLink.fromText(text)
        if (link is NostrLink.Event) { Nip19.decode(link.entity)?.let { Router.push(Route.PublicChannel(it)) }; return }
        if (link is NostrLink.Address) {
            val tlv = Nip19.decodeTLV(link.entity)
            if (tlv?.int("kind") == 34550) { Router.push(Route.Community("34550:${tlv.str("pubkey")}:${tlv.text("identifier")}")); return }
        }
        normalizedRelay(text)?.let { section = 0; relay = it; return }
        ToastCenter.show(L("communityLinkInvalid"), ToastStyle.ERROR)
    }
}

@Composable
fun CommunitiesScreen(initialRelay: String? = null) {
    val model: CommunitiesViewModel = viewModel { CommunitiesViewModel(initialRelay) }
    var showsLink by remember { mutableStateOf(false) }
    var link by remember { mutableStateOf("") }
    LaunchedEffect(model.section, model.relay) { model.load() }
    if (showsLink) AlertDialog(onDismissRequest = { showsLink = false }, title = { Text(L("communityOpenLink")) }, text = {
        Column { Text(L("communityLinkMessage")); OutlinedTextField(link, { link = it }, placeholder = { Text(L("communityLinkPlaceholder")) }, modifier = Modifier.testTag("communities-link")) }
    }, confirmButton = { TextButton(onClick = { showsLink = false; model.openLink(link); link = "" }) { Text(L("communityOpen")) } }, dismissButton = { TextButton(onClick = { showsLink = false }) { Text(L("cancel")) } })
    Scaffold(topBar = { TopAppBar(title = { Text(L("communities")) }, navigationIcon = { IconButton(onClick = { Router.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } }, actions = { IconButton(onClick = { showsLink = true }, modifier = Modifier.testTag("communities-open-link")) { Icon(Icons.Outlined.Link, L("communityOpenLink")) } }) }, modifier = Modifier.testTag("communities")) { padding ->
        Column(Modifier.padding(padding)) {
            val sections = listOf("communityGroups", "communityCommunities", "communityChannels")
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp).testTag("communities-section")) { sections.forEachIndexed { index, key -> SegmentedButton(selected = model.section == index, onClick = { model.section = index }, shape = SegmentedButtonDefaults.itemShape(index, 3)) { Text(L(key), maxLines = 1) } } }
            Text(L(listOf("communityGroupsAbout", "communityCommunitiesAbout", "communityChannelsAbout")[model.section]), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, modifier = Modifier.padding(16.dp))
            OutlinedTextField(model.query, { model.query = it }, placeholder = { Text(L("communitySearch")) }, singleLine = true, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp))
            if (model.section == 0) {
                var expanded by remember { mutableStateOf(false) }
                Box {
                    TextButton(onClick = { expanded = true }, modifier = Modifier.testTag("communities-relay")) { Text(model.relay) }
                    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) { (listOf(model.relay) + CommunityService.groupRelays + CommunityService.groups.map { it.relay }).distinct().forEach { relay -> DropdownMenuItem(text = { Text(relay) }, onClick = { expanded = false; model.relay = relay }) } }
                }
            }
            PullToRefreshBox(model.busy, onRefresh = { model.load(true) }, modifier = Modifier.weight(1f)) {
                LazyColumn(Modifier.fillMaxSize()) {
                    val joinedGroups = CommunityService.groups.filter { model.matches(it.displayName, it.about, it.relayHost) }
                    val joinedCommunities = CommunityService.communities.filter { model.matches(it.displayName, it.summary) }
                    val joinedChannels = CommunityService.channels.filter { model.matches(it.displayName, it.about) }
                    val hasJoined = when (model.section) { 0 -> joinedGroups.isNotEmpty(); 1 -> joinedCommunities.isNotEmpty(); else -> joinedChannels.isNotEmpty() }
                    if (hasJoined) item("joined") { SectionLabel(L("communityJoined")) }
                    when (model.section) {
                        0 -> items(joinedGroups, key = { "joined-${it.id}" }) { GroupRow(it) }
                        1 -> items(joinedCommunities, key = { "joined-${it.id}" }) { CommunityRow(it) }
                        2 -> items(joinedChannels, key = { "joined-${it.id}" }) { ChannelRow(it) }
                    }
                    item("discover") { SectionLabel(L("communityDiscover")) }
                    when (model.section) {
                        0 -> {
                            val found = model.groups.filter { !CommunityService.isJoined(it) && CommunityService.allows(it.name, it.about) && model.matches(it.displayName, it.about) }
                            if (!model.busy && found.isEmpty()) item("empty") { SectionLabel(L("communityNoGroups")) }
                            items(found, key = { it.id }) { GroupRow(it) }
                        }
                        1 -> {
                            val found = model.communities.filter { !CommunityService.isJoined(it) && CommunityService.allows(it.name, it.summary, it.rules) && model.matches(it.displayName, it.summary) }
                            if (!model.busy && found.isEmpty()) item("empty") { SectionLabel(L("communityNoCommunities")) }
                            items(found, key = { it.id }) { CommunityRow(it) }
                        }
                        2 -> {
                            val found = model.channels.filter { !CommunityService.isJoined(it) && CommunityService.allows(it.name, it.about) && model.matches(it.displayName, it.about) }
                            if (!model.busy && found.isEmpty()) item("empty") { SectionLabel(L("communityNoChannels")) }
                            items(found, key = { it.id }) { ChannelRow(it) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SectionLabel(text: String) { Text(text, style = MaterialTheme.typography.labelLarge, color = AppColors.textSecondary, modifier = Modifier.padding(16.dp)) }
@Composable
private fun GroupRow(group: RelayGroup) = RoomRow(group.displayName, group.about.ifEmpty { group.relayHost }, group.picture, "community-group-row", if (group.isClosed) L("communityClosed") else null) { Router.push(Route.RelayGroup(group.id)) }
@Composable
private fun CommunityRow(community: Community) = RoomRow(community.displayName, community.summary, community.image, "community-row") { Router.push(Route.Community(community.id)) }
@Composable
private fun ChannelRow(channel: PublicChannel) = RoomRow(channel.displayName, channel.about, channel.picture, "community-channel-row") { Router.push(Route.PublicChannel(channel.id)) }
@Composable
fun RoomRow(title: String, subtitle: String, picture: String, tag: String, badge: String? = null, onClick: () -> Unit) {
    ListItem(headlineContent = { Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { Text(title, maxLines = 1); if (badge != null) Text(badge, style = MaterialTheme.typography.labelSmall) } }, supportingContent = { if (subtitle.isNotEmpty()) Text(subtitle, maxLines = 2) }, leadingContent = { if (picture.isNotEmpty()) RemoteImage(picture, Modifier.size(44.dp)) else Icon(Icons.Outlined.Forum, null, Modifier.size(44.dp)) }, modifier = Modifier.clickable(onClick = onClick).testTag(tag))
}
