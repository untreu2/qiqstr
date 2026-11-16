package me.untreu.qiqstr.ui.dm

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Profile

class DMGroupViewModel : ViewModel() {
    var busy by mutableStateOf(false)
        private set
    fun create(name: String, members: Set<String>, onCreated: (String) -> Unit) = run { onCreated(DMService.createGroup(name, members.toList())) }
    fun add(key: String, members: Set<String>, onDone: () -> Unit) = run { DMService.addMembers(members.toList(), key); onDone() }
    fun remove(key: String, member: String) = run { DMService.removeMember(member, key) }
    fun rename(key: String, name: String, onDone: () -> Unit) = run { if (name.isNotBlank() && name.trim() != DMService.group(key)?.name) DMService.renameGroup(key, name); onDone() }
    fun leave(key: String, onDone: () -> Unit) = run { DMService.leaveGroup(key); onDone() }
    private fun run(work: suspend () -> Unit) {
        if (busy) return
        busy = true
        viewModelScope.launch { try { work() } catch (error: Throwable) { ToastCenter.error(error) } finally { busy = false } }
    }
}

@Composable
fun DMGroupAvatar(group: MarmotGroup?, size: Dp) {
    val others = group?.members.orEmpty().filter { it != Session.pubkey }.take(2)
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        if (others.size >= 2) {
            ProfileAvatar(others[1], size = size * 0.66f, modifier = Modifier.offset(x = size * 0.17f, y = size * -0.17f))
            ProfileAvatar(others[0], size = size * 0.66f, modifier = Modifier.offset(x = size * -0.17f, y = size * 0.17f))
        } else Box(Modifier.size(size).background(AppColors.tile, CircleShape), contentAlignment = Alignment.Center) {
            Icon(Icons.Outlined.Group, group?.displayName, Modifier.size(size * 0.5f), tint = AppColors.textPrimary)
        }
    }
}

@Composable
fun DMNewGroupScreen(onDismiss: () -> Unit, onCreated: (String) -> Unit) {
    val model: DMGroupViewModel = viewModel(key = "dm-new-group")
    var name by remember { mutableStateOf("") }
    var selected by remember { mutableStateOf<Set<String>>(emptySet()) }
    Scaffold(topBar = {
        TopAppBar(title = { Text(L("dmNewGroup")) }, navigationIcon = { IconButton(onClick = onDismiss) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } }, actions = {
            TextButton(onClick = { model.create(name, selected, onCreated) }, enabled = name.isNotBlank() && selected.isNotEmpty() && !model.busy, modifier = Modifier.testTag("dm-group-create")) { Text(L("dmGroupCreate")) }
        })
    }, modifier = Modifier.testTag("dm-new-group-view")) { padding ->
        Column(Modifier.padding(padding)) {
            OutlinedTextField(name, { name = it }, label = { Text(L("dmGroupName")) }, singleLine = true, enabled = !model.busy, modifier = Modifier.fillMaxWidth().padding(16.dp).testTag("dm-group-name"))
            Text(L("dmGroupFooter"), color = AppColors.textSecondary, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(horizontal = 16.dp))
            if (model.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            DMMemberPicker(selected, setOfNotNull(Session.pubkey), !model.busy) { selected = it }
        }
    }
}

@Composable
private fun DMMemberPicker(selected: Set<String>, excluded: Set<String>, enabled: Boolean, onChange: (Set<String>) -> Unit) {
    val picker: DMUserPickerViewModel = viewModel(key = "dm-group-members-${excluded.sorted().joinToString()}")
    LaunchedEffect(Unit) { picker.loadFollowing() }
    LaunchedEffect(picker.query) { picker.search() }
    Column {
        OutlinedTextField(picker.query, { picker.query = it }, placeholder = { Text(L("searchByNameOrNpub")) }, singleLine = true, modifier = Modifier.fillMaxWidth().padding(16.dp).testTag("dm-group-search"))
        val keys = (listOfNotNull(picker.directPubkey) + selected + picker.results.map { it.pubkey }).distinct().filter { it !in excluded }
        LazyColumn {
            items(keys, key = { it }) { key ->
                ListItem(
                    headlineContent = { Text(ProfileCache.profile(key)?.bestName ?: Profile.shortNpub(key)) },
                    leadingContent = { ProfileAvatar(key, size = 40.dp) },
                    trailingContent = { Checkbox(key in selected, onCheckedChange = null, enabled = enabled) },
                    modifier = Modifier.clickable(enabled = enabled) { onChange(if (key in selected) selected - key else selected + key) }.testTag("dm-group-member-$key"),
                )
            }
        }
    }
}

@Composable
fun DMGroupInfoSheet(key: String, onDismiss: () -> Unit, onLeft: () -> Unit) {
    val model: DMGroupViewModel = viewModel(key = "dm-group-info-$key")
    val group = DMService.group(key)
    val admin = DMService.isAdmin(key)
    var name by remember(group?.name) { mutableStateOf(group?.name ?: "") }
    var adding by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf<Set<String>>(emptySet()) }
    var leave by remember { mutableStateOf(false) }
    if (leave) AlertDialog(onDismissRequest = { leave = false }, title = { Text(L("dmGroupLeaveConfirm")) }, text = { Text(L("dmGroupLeaveMessage")) }, confirmButton = {
        TextButton(onClick = { leave = false; model.leave(key) { onDismiss(); onLeft() } }, modifier = Modifier.testTag("dm-group-leave-confirm")) { Text(L("dmGroupLeave"), color = AppColors.error) }
    }, dismissButton = { TextButton(onClick = { leave = false }) { Text(L("cancel")) } })
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().testTag("dm-group-info")) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(L(if (adding) "dmGroupAddPeople" else "dmGroupInfo"), style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                TextButton(onClick = {
                    if (adding) model.add(key, selected) { adding = false; selected = emptySet() }
                    else if (admin) model.rename(key, name, onDismiss) else onDismiss()
                }, enabled = !model.busy && (!adding || selected.isNotEmpty()), modifier = Modifier.testTag(if (adding) "dm-group-add-confirm" else "dm-group-info-done")) { Text(L(if (adding) "settingsAdd" else "done")) }
            }
            if (model.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            if (adding) DMMemberPicker(selected, group?.members.orEmpty().toSet(), !model.busy) { selected = it }
            else {
                if (admin) OutlinedTextField(name, { name = it }, label = { Text(L("dmGroupName")) }, singleLine = true, enabled = !model.busy, modifier = Modifier.fillMaxWidth().padding(16.dp).testTag("dm-group-info-name"))
                else Text(group?.displayName ?: "", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(16.dp))
                Text(L("dmGroupMembersCount", "count" to group?.members.orEmpty().size), modifier = Modifier.padding(horizontal = 16.dp), color = AppColors.textSecondary)
                LazyColumn(Modifier.weight(1f, fill = false)) {
                    items(group?.members.orEmpty().sortedBy { if (it == Session.pubkey) "" else it }, key = { it }) { member ->
                        ListItem(headlineContent = { Text(if (member == Session.pubkey) L("dmGroupYou") else ProfileCache.profile(member)?.bestName ?: Profile.shortNpub(member)) },
                            supportingContent = { if (group?.isAdmin(member) == true) Text(L("dmGroupAdmin")) },
                            leadingContent = { ProfileAvatar(member, size = 36.dp) },
                            trailingContent = { if (admin && member != Session.pubkey) TextButton(onClick = { model.remove(key, member) }, enabled = !model.busy) { Text(L("dmGroupRemove"), color = AppColors.error) } },
                            modifier = Modifier.clickable { if (member != Session.pubkey) { onDismiss(); Router.push(Route.Profile(member)) } }.testTag("dm-group-member-row"))
                    }
                    if (admin) item { TextButton(onClick = { adding = true }, enabled = !model.busy, modifier = Modifier.testTag("dm-group-add")) { Text(L("dmGroupAddPeople")) } }
                    item { TextButton(onClick = { leave = true }, enabled = !model.busy, modifier = Modifier.testTag("dm-group-leave")) { Text(L("dmGroupLeave"), color = AppColors.error) } }
                    item { Text(L("dmGroupEncryption"), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, modifier = Modifier.padding(16.dp)) }
                }
            }
        }
    }
}
