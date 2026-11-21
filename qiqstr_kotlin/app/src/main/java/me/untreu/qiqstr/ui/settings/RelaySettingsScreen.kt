package me.untreu.qiqstr.ui.settings

import android.net.Uri
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.outlined.ArrowCircleDown
import androidx.compose.material.icons.outlined.ArrowCircleUp
import androidx.compose.material.icons.outlined.ArrowDownward
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.CellTower
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Hub
import androidx.compose.material.icons.outlined.ImportExport
import androidx.compose.material.icons.outlined.Speed
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.qiqstr.core.signRelayListEventWithMarkers
import com.qiqstr.core.addRelay
import com.qiqstr.core.addRelayWithFlags
import com.qiqstr.core.connectRelays
import com.qiqstr.core.getRelayStatus
import com.qiqstr.core.removeRelay
import com.qiqstr.core.streamBroadcastEvents
import com.qiqstr.core.streamRelayStatus
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.bool
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.objects
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.data.bridge.EventStream
import me.untreu.qiqstr.data.services.GossipMode
import me.untreu.qiqstr.data.services.ListError
import me.untreu.qiqstr.data.services.RelayConfig
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.ui.auth.SecureClipboard
import me.untreu.qiqstr.ui.auth.rememberHaptics
import org.json.JSONArray
import org.json.JSONObject

data class SettingsRelayFlags(val read: Boolean = true, val write: Boolean = true) {
    val marker: String get() = if (read && write) "" else if (read) "read" else "write"
}

data class SettingsRelayStatus(val status: String, val latencyMs: Int, val bytesSent: Long, val bytesReceived: Long)

data class PublishChanges(val added: Int, val removed: Int)

data class BroadcastProgress(val sent: Int, val total: Int)

val GossipMode.title: String
    get() = when (this) {
        GossipMode.NORMAL -> L("settingsGossipNormal")
        GossipMode.AGGRESSIVE -> L("settingsGossipAggressive")
        GossipMode.PSYCHO -> L("settingsGossipPsycho")
    }

val GossipMode.detail: String get() = L("settingsGossipDetail", "relays" to maxOutboxRelays, "frequency" to minRelayFrequency)

class RelaySettingsModel : ViewModel() {
    var relays by mutableStateOf<List<String>>(emptyList())
        private set
    var flags by mutableStateOf<Map<String, SettingsRelayFlags>>(emptyMap())
        private set
    var statuses by mutableStateOf<Map<String, SettingsRelayStatus>>(emptyMap())
        private set
    var isPublishing by mutableStateOf(false)
        private set
    var isFetching by mutableStateOf(false)
        private set
    var broadcastProgress by mutableStateOf<BroadcastProgress?>(null)
        private set
    var gossipMode by mutableStateOf(RelayConfig.gossipMode)
        private set
    var showAdd by mutableStateOf(false)
    var newRelayURL by mutableStateOf("")
    var showResetConfirm by mutableStateOf(false)
    var pendingBroadcast by mutableStateOf<List<String>>(emptyList())
    var showBroadcastPrompt by mutableStateOf(false)
    var feedback by mutableIntStateOf(0)
        private set
    var publishChanges by mutableStateOf<PublishChanges?>(null)
    private var statusJob: Job? = null

    val connectedCount: Int get() = relays.count { status(it)?.status == "connected" }
    val totalCount: Int get() = relays.size
    val totalBytes: Long get() = statuses.values.sumOf { it.bytesSent + it.bytesReceived }

    fun updateGossipMode(mode: GossipMode) {
        if (mode == gossipMode) return
        gossipMode = mode
        RelayConfig.gossipMode = mode
        ToastCenter.show(L("settingsGossipRestart"))
    }

    fun load() {
        relays = RelayConfig.mainRelays
        val stored = storedFlags().toMutableMap()
        for (relay in relays) if (relay !in stored) stored[relay] = SettingsRelayFlags()
        flags = stored
    }

    fun startStatus() {
        statusJob?.cancel()
        statusJob = viewModelScope.launch {
            while (isActive) {
                runCatching { EventStream.make { sink -> streamRelayStatus(sink) }.collect { apply(it) } }
                runCatching { getRelayStatus() }.getOrNull()?.let(::apply)
                delay(2000)
            }
        }
    }

    fun stopStatus() {
        statusJob?.cancel()
        statusJob = null
    }

    private fun apply(raw: String) {
        val json = Json.obj(raw) ?: return
        val next = HashMap<String, SettingsRelayStatus>()
        for (relay in json.objects("relays")) {
            val url = relay.str("url") ?: continue
            next[normalize(url)] = SettingsRelayStatus(relay.str("status") ?: "disconnected", relay.int("latencyMs"), relay.long("bytesSent"), relay.long("bytesReceived"))
        }
        if (next != statuses) statuses = next
    }

    fun status(relay: String): SettingsRelayStatus? = statuses[normalize(relay)]

    fun flags(relay: String): SettingsRelayFlags = flags[relay] ?: SettingsRelayFlags()

    fun add() {
        val url = canonicalInput(newRelayURL)
        if (url.isEmpty()) { ToastCenter.show(L("pleaseEnterRelayUrl"), ToastStyle.ERROR); return }
        if (!isValid(url)) { ToastCenter.show(L("invalidRelayUrl"), ToastStyle.ERROR); return }
        val normalized = normalize(url)
        if (relays.any { normalize(it) == normalized }) {
            ToastCenter.show(L("relayAlreadyExistsInCategory"), ToastStyle.ERROR)
            return
        }
        newRelayURL = ""
        showAdd = false
        relays = relays + normalized
        flags = flags + (normalized to SettingsRelayFlags())
        persist()
        viewModelScope.launch {
            try {
                addRelay(normalized)
                App.scope.launch { runCatching { connectRelays() } }
                feedback += 1
                ToastCenter.show(L("relayAddedToMainList"), ToastStyle.SUCCESS)
                offerBroadcast(listOf(normalized))
            } catch (error: Throwable) {
                ToastCenter.show("${L("errorAddingRelay")}: ${coreErrorMessage(error)}", ToastStyle.ERROR)
            }
        }
    }

    fun remove(relay: String) {
        relays = relays - relay
        flags = flags - relay
        persist()
        viewModelScope.launch {
            runCatching { removeRelay(relay) }
            feedback += 1
            ToastCenter.show(L("relayRemovedSuccessfully"), ToastStyle.SUCCESS)
        }
    }

    fun move(index: Int, offset: Int) {
        val target = index + offset
        if (index !in relays.indices || target !in relays.indices) return
        relays = relays.toMutableList().apply { add(target, removeAt(index)) }
        persist()
    }

    fun setFlags(relay: String, read: Boolean, write: Boolean) {
        if (!read && !write) return
        flags = flags + (relay to SettingsRelayFlags(read, write))
        persist()
        viewModelScope.launch { runCatching { addRelayWithFlags(relay, read, write) } }
    }

    fun resetToDefaults() {
        viewModelScope.launch {
            val previous = relays.map(::normalize).toSet()
            val defaults = RelayConfig.defaultMainRelays
            for (relay in relays) if (defaults.none { normalize(it) == normalize(relay) }) runCatching { removeRelay(relay) }
            RelayConfig.resetRelays()
            relays = defaults
            flags = defaults.associateWith { SettingsRelayFlags() }
            persist()
            for (relay in defaults) runCatching { addRelayWithFlags(relay, true, true) }
            App.scope.launch { runCatching { connectRelays() } }
            feedback += 1
            ToastCenter.show(L("relaysResetToDefaults"), ToastStyle.SUCCESS)
            offerBroadcast(defaults.filter { normalize(it) !in previous })
        }
    }

    fun publish(confirmed: Boolean = false) {
        val me = Session.pubkey
        if (!Session.canSign || me == null) {
            ToastCenter.show(L("privateKeyNotFound"), ToastStyle.ERROR)
            return
        }
        isPublishing = true
        viewModelScope.launch {
            try {
                val base = try {
                    SyncService.latestEditableEvent(10002, me)
                } catch (error: ListError) {
                    return@launch
                } catch (error: Throwable) {
                    ToastCenter.show("${L("errorPublishingRelayList")}: ${coreErrorMessage(error)}", ToastStyle.ERROR)
                    return@launch
                }
                val published = base?.tags().orEmpty().filter { it.size > 1 && it[0] == "r" }.map { normalize(it[1]) }.toSet()
                val local = relays.map(::normalize).toSet()
                if (!confirmed && base != null && published != local) {
                    publishChanges = PublishChanges((local - published).size, (published - local).size)
                    return@launch
                }
                val configs = relays.mapNotNull { relay ->
                    val f = flags(relay)
                    when {
                        f.read && f.write -> relay
                        f.read -> "$relay|read"
                        f.write -> "$relay|write"
                        else -> null
                    }
                }
                try {
                    val event = signRelayListEventWithMarkers(configs)
                    SyncService.publish(event)
                    Prefs.set("published_relay_list", event)
                    feedback += 1
                    ToastCenter.show("${L("relayListPublishedSuccessfully")} (${configs.size})", ToastStyle.SUCCESS)
                } catch (error: Throwable) {
                    ToastCenter.show("${L("errorPublishingRelayList")}: ${coreErrorMessage(error)}", ToastStyle.ERROR)
                }
            } finally {
                isPublishing = false
            }
        }
    }

    fun fetchFromProfile() {
        val me = Session.pubkey ?: return
        isFetching = true
        viewModelScope.launch {
            try {
                val events = SyncService.fetchEvents(mapOf("authors" to listOf(me), "kinds" to listOf(10002), "limit" to 1))
                val event = events.maxByOrNull { it.long("created_at") }
                if (event == null) {
                    ToastCenter.show(L("noRelayListFoundInYourProfile"))
                    return@launch
                }
                val urls = mutableListOf<String>()
                val newFlags = HashMap<String, SettingsRelayFlags>()
                for (tag in event.tags()) {
                    if (tag.size < 2 || tag[0] != "r" || !isValid(tag[1])) continue
                    val url = normalize(tag[1])
                    if (url in urls) continue
                    val marker = if (tag.size >= 3) tag[2] else ""
                    urls.add(url)
                    newFlags[url] = when (marker) {
                        "read" -> SettingsRelayFlags(read = true, write = false)
                        "write" -> SettingsRelayFlags(read = false, write = true)
                        else -> SettingsRelayFlags()
                    }
                }
                if (urls.isEmpty()) {
                    ToastCenter.show(L("noRelayListFoundInYourProfile"))
                    return@launch
                }
                Prefs.set("user_relays", Json.string(urls.map { mapOf("url" to it, "marker" to (newFlags[it]?.marker ?: "")) }))
                val previous = relays.map(::normalize).toSet()
                for (relay in relays) if (normalize(relay) !in urls) runCatching { removeRelay(relay) }
                relays = urls
                flags = newFlags
                persist()
                for (url in urls) {
                    val f = newFlags[url] ?: SettingsRelayFlags()
                    runCatching { addRelayWithFlags(url, f.read, f.write) }
                }
                App.scope.launch { runCatching { connectRelays() } }
                Prefs.set("using_user_relays", true)
                feedback += 1
                ToastCenter.show(L("usingPersonalRelays", "count" to urls.size), ToastStyle.SUCCESS)
                offerBroadcast(urls.filter { it !in previous })
            } finally {
                isFetching = false
            }
        }
    }

    private fun offerBroadcast(urls: List<String>) {
        if (urls.isEmpty()) return
        pendingBroadcast = urls
        showBroadcastPrompt = true
    }

    fun broadcastPending() {
        val targets = pendingBroadcast
        pendingBroadcast = emptyList()
        val me = Session.pubkey ?: return
        if (targets.isEmpty() || broadcastProgress != null) return
        broadcastProgress = BroadcastProgress(0, 0)
        viewModelScope.launch {
            try {
                ToastCenter.show(L("fetchingYourEvents"))
                val events = SyncService.fetchEvents(mapOf("authors" to listOf(me)), timeout = 30)
                val seen = HashSet<String>()
                val unique = events.filter { event -> event.str("id")?.let(seen::add) ?: false }
                if (unique.isEmpty()) {
                    ToastCenter.show(L("noEventsFoundToBroadcast"))
                    return@launch
                }
                broadcastProgress = BroadcastProgress(0, unique.size)
                ToastCenter.show(L("broadcastingEvents", "count" to unique.size, "relayCount" to targets.size))
                val payload = JSONArray(unique).toString()
                var sent = 0
                try {
                    EventStream.make { sink -> streamBroadcastEvents(payload, targets, sink) }.collect { raw ->
                        val progress = Json.obj(raw) ?: return@collect
                        sent = progress.int("sent")
                        broadcastProgress = BroadcastProgress(sent + progress.int("failed"), maxOf(unique.size, progress.int("total")))
                    }
                    if (sent > 0) {
                        feedback += 1
                        ToastCenter.show(L("eventsSuccessfullyBroadcast", "count" to unique.size, "relayCount" to targets.size), ToastStyle.SUCCESS)
                    } else {
                        ToastCenter.show(L("errorBroadcastingEvents"), ToastStyle.ERROR)
                    }
                } catch (error: Throwable) {
                    ToastCenter.show("${L("errorBroadcastingEvents")}: ${coreErrorMessage(error)}", ToastStyle.ERROR)
                }
            } finally {
                broadcastProgress = null
            }
        }
    }

    private fun persist() {
        RelayConfig.mainRelays = relays
        val json = JSONObject()
        flags.filterKeys { it in relays }.forEach { (url, f) -> json.put(url, JSONObject().put("read", f.read).put("write", f.write)) }
        Prefs.set(FLAGS_KEY, json.toString())
    }

    private fun storedFlags(): Map<String, SettingsRelayFlags> {
        val json = Json.obj(Prefs.string(FLAGS_KEY)) ?: return emptyMap()
        return json.keys().asSequence().mapNotNull { url ->
            val f = json.optJSONObject(url) ?: return@mapNotNull null
            url to SettingsRelayFlags(if (f.has("read")) f.bool("read") else true, if (f.has("write")) f.bool("write") else true)
        }.toMap()
    }

    companion object {
        private const val FLAGS_KEY = "relay_flags"

        fun isValid(url: String): Boolean {
            val trimmed = url.trim().lowercase()
            if (!trimmed.startsWith("wss://") && !trimmed.startsWith("ws://")) return false
            val host = runCatching { Uri.parse(trimmed).host }.getOrNull()
            if (host.isNullOrEmpty()) return false
            return (host.contains(".") || host == "localhost") && RelayConfig.isUsableRelayURL(url.trim())
        }

        fun canonicalInput(raw: String): String {
            var value = raw.trim()
            if (value.isEmpty()) return value
            val index = value.lastIndexOf("://")
            value = if (index >= 0) {
                val scheme = value.substring(0, index).split("/").lastOrNull()?.lowercase() ?: "wss"
                (if (scheme == "ws") "ws://" else "wss://") + value.substring(index + 3)
            } else {
                "wss://$value"
            }
            return value
        }

        fun normalize(url: String): String {
            var trimmed = url.trim()
            while (trimmed.endsWith("/") && !trimmed.endsWith("://")) trimmed = trimmed.dropLast(1)
            return trimmed
        }

        fun host(url: String): String = runCatching { Uri.parse(url).host }.getOrNull() ?: url
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RelaySettingsScreen() {
    val model: RelaySettingsModel = viewModel()
    val haptics = rememberHaptics()
    var editing by remember { mutableStateOf(false) }
    var showGossip by remember { mutableStateOf(false) }
    DisposableEffect(Unit) {
        model.load()
        model.startStatus()
        onDispose { model.stopStatus() }
    }
    LaunchedEffect(model.feedback) { if (model.feedback > 0) haptics.success() }

    SettingsScaffold(
        L("relays"),
        actions = {
            TextButton(onClick = { editing = !editing }, modifier = Modifier.testTag("relays-edit")) {
                Text(if (editing) L("done") else L("edit"), color = AppColors.textPrimary)
            }
            IconButton(onClick = { model.showAdd = true }, modifier = Modifier.testTag("relays-add")) { Icon(Icons.Filled.Add, L("addRelay")) }
        },
    ) {
        settingsSection("summary", footer = L("manageYourRelayConnections")) {
            SettingsRow(
                L("connected"),
                Icons.Outlined.CellTower,
                tint = if (model.connectedCount > 0) AppColors.success else AppColors.warning,
                value = "${model.connectedCount}/${model.totalCount}",
                modifier = Modifier.testTag("relays-summary"),
            )
            SettingsRow(L("settingsRelayTraffic"), Icons.Outlined.ImportExport, value = SettingsByteFormat.string(model.totalBytes))
            model.broadcastProgress?.let { progress ->
                Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp).testTag("relays-broadcast-progress"), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    LinearProgressIndicator(
                        progress = { if (progress.total > 0) progress.sent.toFloat() / progress.total else 0f },
                        modifier = Modifier.fillMaxWidth(),
                        color = AppColors.textPrimary,
                    )
                    Text(
                        if (progress.total > 0) L("broadcastProgress", "sent" to progress.sent, "total" to progress.total) else L("fetchingYourEvents"),
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textSecondary,
                    )
                }
            }
        }
        settingsSection("sync") {
            SettingsRow(
                if (model.isFetching) L("fetching") else L("fetch"),
                Icons.Outlined.ArrowCircleDown,
                enabled = !model.isFetching,
                modifier = Modifier.testTag("relays-fetch"),
                trailing = if (model.isFetching) ({ CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) }) else null,
            ) { model.fetchFromProfile() }
            SettingsRow(
                if (model.isPublishing) L("publishing") else L("publish"),
                Icons.Outlined.ArrowCircleUp,
                enabled = !model.isPublishing && model.relays.isNotEmpty(),
                modifier = Modifier.testTag("relays-publish"),
                trailing = if (model.isPublishing) ({ CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) }) else null,
            ) { model.publish() }
        }
        settingsSection("relays", L("relays")) {
            if (model.relays.isEmpty()) {
                Text(L("noRelaysInCategory"), color = AppColors.textSecondary, modifier = Modifier.padding(16.dp))
            } else {
                model.relays.forEachIndexed { index, relay ->
                    key(relay) {
                        RelayRow(model, relay, index, editing)
                    }
                }
            }
        }
        settingsSection("gossip", footer = L("gossipModeDescription")) {
            SettingsRow(
                L("gossipMode"),
                Icons.Outlined.Hub,
                modifier = Modifier.testTag("relays-gossip-mode"),
                trailing = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(model.gossipMode.title, color = AppColors.textSecondary)
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = AppColors.textTertiary)
                    }
                },
            ) { showGossip = true }
        }
        settingsSection("reset") {
            SettingsCenteredAction(L("resetToDefaults"), AppColors.error, Modifier.testTag("relays-reset")) { model.showResetConfirm = true }
        }
    }

    if (showGossip) {
        AlertDialog(
            onDismissRequest = { showGossip = false },
            title = { Text(L("gossipMode")) },
            text = {
                Column {
                    GossipMode.entries.forEach { mode ->
                        Row(
                            Modifier.fillMaxWidth().selectable(mode == model.gossipMode, role = Role.RadioButton) {
                                model.updateGossipMode(mode)
                                showGossip = false
                            }.padding(vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = mode == model.gossipMode, onClick = null)
                            Column(Modifier.padding(start = 12.dp)) {
                                Text(mode.title)
                                Text(mode.detail, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
                            }
                        }
                    }
                }
            },
            confirmButton = { TextAction(L("done"), { showGossip = false }) },
        )
    }
    if (model.showAdd) AddRelaySheet(model)
    model.publishChanges?.let { changes ->
        AlertDialog(
            onDismissRequest = { model.publishChanges = null },
            title = { Text(L("relayPublishReplaceTitle")) },
            text = { Text(L("relayPublishReplaceMessage", "added" to changes.added, "removed" to changes.removed)) },
            confirmButton = {
                Box(Modifier.testTag("relays-publish-confirm")) {
                    TextAction(L("publish"), { model.publishChanges = null; model.publish(confirmed = true) }, color = AppColors.error)
                }
            },
            dismissButton = { TextAction(L("cancel"), { model.publishChanges = null }) },
        )
    }
    if (model.showResetConfirm) {
        AlertDialog(
            onDismissRequest = { model.showResetConfirm = false },
            title = { Text(L("resetToDefaults")) },
            text = { Text(L("resetRelaysConfirm")) },
            confirmButton = {
                Box(Modifier.testTag("relays-reset-confirm")) {
                    TextAction(L("reset"), { model.showResetConfirm = false; model.resetToDefaults() }, color = AppColors.error)
                }
            },
            dismissButton = { TextAction(L("cancel"), { model.showResetConfirm = false }) },
        )
    }
    if (model.showBroadcastPrompt) {
        AlertDialog(
            onDismissRequest = { model.showBroadcastPrompt = false; model.pendingBroadcast = emptyList() },
            title = { Text(L("settingsBroadcastTitle")) },
            text = { Text(if (model.pendingBroadcast.size == 1) L("settingsBroadcastOne") else L("settingsBroadcastMany", "count" to model.pendingBroadcast.size)) },
            confirmButton = {
                Box(Modifier.testTag("relays-broadcast-confirm")) {
                    TextAction(L("settingsYes"), { model.showBroadcastPrompt = false; model.broadcastPending() })
                }
            },
            dismissButton = { TextAction(L("settingsNo"), { model.showBroadcastPrompt = false; model.pendingBroadcast = emptyList() }) },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun RelayRow(model: RelaySettingsModel, relay: String, index: Int, editing: Boolean) {
    var menu by remember { mutableStateOf(false) }
    val status = model.status(relay)
    val flags = model.flags(relay)
    val dismissState = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart) model.remove(relay)
        false
    })
    SwipeToDismissBox(
        state = dismissState,
        enableDismissFromStartToEnd = false,
        gesturesEnabled = !editing,
        backgroundContent = {
            Box(Modifier.fillMaxSize().background(AppColors.error).padding(horizontal = 20.dp), contentAlignment = Alignment.CenterEnd) {
                Icon(Icons.Outlined.Delete, L("delete"), tint = MaterialTheme.colorScheme.onError)
            }
        },
        modifier = Modifier.testTag("relay-row-${RelaySettingsModel.host(relay)}"),
    ) {
        Box {
            Row(
                Modifier.fillMaxWidth().background(AppColors.background)
                    .combinedClickable(onClick = { menu = true }, onLongClick = { menu = true })
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Box {
                    SettingsIcon(Icons.Outlined.Dns)
                    Box(
                        Modifier.align(Alignment.BottomEnd).offset(x = 3.dp, y = 3.dp).size(11.dp).clip(CircleShape)
                            .background(statusColor(status)).border(2.dp, AppColors.background, CircleShape),
                    )
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(RelaySettingsModel.host(relay), maxLines = 1)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        val small = MaterialTheme.typography.bodySmall
                        Text(statusText(status), style = small, color = statusColor(status), maxLines = 1)
                        if (status != null && status.latencyMs > 0) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                                Icon(Icons.Outlined.Speed, null, Modifier.size(12.dp), tint = latencyColor(status.latencyMs))
                                Text("${status.latencyMs}ms", style = small, color = latencyColor(status.latencyMs), fontFamily = FontFamily.Monospace, maxLines = 1)
                            }
                        }
                        if (status != null && status.bytesReceived > 0) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                                Icon(Icons.Outlined.ArrowDownward, null, Modifier.size(12.dp), tint = AppColors.textSecondary)
                                Text(SettingsByteFormat.string(status.bytesReceived), style = small, color = AppColors.textSecondary, maxLines = 1)
                            }
                        }
                        if (!(flags.read && flags.write)) {
                            Text(if (flags.read) L("settingsRelayReadOnly") else L("settingsRelayWriteOnly"), style = small, color = AppColors.textSecondary, maxLines = 1)
                        }
                    }
                }
                if (editing) {
                    IconButton(onClick = { model.move(index, -1) }, enabled = index > 0) { Icon(Icons.Filled.KeyboardArrowUp, L("settingsMoveUp")) }
                    IconButton(onClick = { model.move(index, 1) }, enabled = index < model.relays.lastIndex) { Icon(Icons.Filled.KeyboardArrowDown, L("settingsMoveDown")) }
                }
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(
                    text = { Text(L("copy")) },
                    leadingIcon = { Icon(Icons.Outlined.ContentCopy, null) },
                    onClick = {
                        menu = false
                        SecureClipboard.copy(relay, sensitive = false)
                        ToastCenter.show(L("copiedToClipboard"), ToastStyle.SUCCESS)
                    },
                )
                HorizontalDivider()
                Text(L("settingsRelayUsage"), style = MaterialTheme.typography.labelMedium, color = AppColors.textSecondary, modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp))
                UsageItem(L("settingsRelayReadWrite"), Icons.Outlined.ImportExport, flags.read && flags.write) { menu = false; model.setFlags(relay, true, true) }
                UsageItem(L("settingsRelayReadOnly"), Icons.Outlined.ArrowDownward, flags.read && !flags.write) { menu = false; model.setFlags(relay, true, false) }
                UsageItem(L("settingsRelayWriteOnly"), Icons.Outlined.ArrowUpward, !flags.read && flags.write) { menu = false; model.setFlags(relay, false, true) }
                HorizontalDivider()
                DropdownMenuItem(
                    text = { Text(L("delete"), color = AppColors.error) },
                    leadingIcon = { Icon(Icons.Outlined.Delete, null, tint = AppColors.error) },
                    onClick = { menu = false; model.remove(relay) },
                )
            }
        }
    }
}

@Composable
private fun UsageItem(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, selected: Boolean, onClick: () -> Unit) {
    DropdownMenuItem(text = { Text(title) }, leadingIcon = { Icon(if (selected) Icons.Filled.Check else icon, null) }, onClick = onClick)
}

@Composable
private fun statusText(status: SettingsRelayStatus?) = when (status?.status) {
    "connected" -> L("connected")
    "connecting", "pending", "initialized" -> L("connecting")
    "sleeping" -> L("settingsRelaySleeping")
    else -> L("disconnected")
}

@Composable
private fun statusColor(status: SettingsRelayStatus?): Color = when (status?.status) {
    "connected" -> AppColors.success
    "connecting", "pending", "initialized", "sleeping" -> AppColors.warning
    else -> AppColors.error
}

@Composable
private fun latencyColor(ms: Int): Color = when {
    ms < 300 -> AppColors.success
    ms < 800 -> AppColors.warning
    else -> AppColors.error
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddRelaySheet(model: RelaySettingsModel) {
    val focus = remember { FocusRequester() }
    var field by remember { mutableStateOf(TextFieldValue(model.newRelayURL.ifEmpty { "wss://" }, TextRange(model.newRelayURL.ifEmpty { "wss://" }.length))) }
    LaunchedEffect(Unit) {
        model.newRelayURL = field.text
        runCatching { focus.requestFocus() }
    }
    val isValid = RelaySettingsModel.isValid(RelaySettingsModel.canonicalInput(model.newRelayURL))
    ModalBottomSheet(onDismissRequest = { model.showAdd = false }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = AppColors.background) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().imePadding().padding(bottom = 16.dp)) {
            TopAppBar(
                title = { Text(L("addRelay")) },
                navigationIcon = { IconButton(onClick = { model.showAdd = false }) { Icon(Icons.Filled.Close, L("cancel")) } },
                actions = {
                    IconButton(onClick = { model.add() }, enabled = isValid, modifier = Modifier.testTag("relays-add-confirm")) { Icon(Icons.Filled.Check, L("done")) }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.background),
            )
            Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                androidx.compose.material3.TextField(
                    value = field,
                    onValueChange = {
                        field = it
                        model.newRelayURL = it.text
                    },
                    placeholder = { Text(L("relayUrlHint")) },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Done, autoCorrectEnabled = false),
                    keyboardActions = androidx.compose.foundation.text.KeyboardActions(onDone = { model.add() }),
                    modifier = Modifier.fillMaxWidth().focusRequester(focus).testTag("relays-add-field"),
                )
                if (model.newRelayURL !in listOf("", "wss://", "ws://") && !isValid) {
                    Text(L("invalidRelayUrl"), color = AppColors.error, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}
