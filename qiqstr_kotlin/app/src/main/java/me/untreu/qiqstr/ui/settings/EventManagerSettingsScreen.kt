package me.untreu.qiqstr.ui.settings

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Article
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Hub
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Repeat
import androidx.compose.material.icons.outlined.SettingsInputAntenna
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.qiqstr.core.deleteEvents
import com.qiqstr.core.fetchAllEventsForAuthor
import com.qiqstr.core.requestToVanish
import com.qiqstr.core.streamBroadcastEvents
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.core.bool
import me.untreu.qiqstr.core.components.QiqTextField
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.data.bridge.EventStream
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.ui.auth.rememberHaptics
import org.json.JSONArray
import org.json.JSONObject

class EventManagerModel : ViewModel() {
    var events by mutableStateOf<List<String>>(emptyList())
        private set
    val countsByKind = mutableStateMapOf<Int, Int>()
    var isScanning by mutableStateOf(false)
        private set
    var isBroadcasting by mutableStateOf(false)
        private set
    var broadcastSent by mutableIntStateOf(0)
        private set
    var broadcastFailed by mutableIntStateOf(0)
        private set
    var broadcastTotal by mutableIntStateOf(0)
        private set
    var isDeleting by mutableStateOf(false)
        private set
    var isExporting by mutableStateOf(false)
        private set
    var showDeleteConfirm by mutableStateOf(false)
    var showFinalConfirm by mutableStateOf(false)
    var confirmText by mutableStateOf("")
    var feedback by mutableIntStateOf(0)
        private set

    private val seen = HashSet<String>()
    private val replaceable = HashMap<String, Int>()
    private var scanJob: Job? = null
    private var broadcastJob: Job? = null

    val sortedKinds: List<Int> get() = countsByKind.keys.sortedWith(compareByDescending<Int> { countsByKind[it] ?: 0 }.thenBy { it })
    val isBusy: Boolean get() = isBroadcasting || isDeleting
    val confirmWord: String get() = L("settingsVanishConfirmWord")
    val canConfirmVanish: Boolean get() = confirmText.trim().equals(confirmWord, ignoreCase = true)
    val broadcastProgress: Float get() = if (broadcastTotal > 0) (broadcastSent + broadcastFailed).toFloat() / broadcastTotal else 0f

    fun scan() {
        val me = Session.pubkey ?: return
        scanJob?.cancel()
        events = emptyList()
        countsByKind.clear()
        seen.clear()
        replaceable.clear()
        isScanning = true
        scanJob = viewModelScope.launch {
            val list = mutableListOf<String>()
            try {
                EventStream.make { sink -> fetchAllEventsForAuthor(me, sink) }.collect { raw ->
                    val event = Json.obj(raw) ?: return@collect
                    val id = event.str("id") ?: return@collect
                    if (!seen.add(id)) return@collect
                    val key = replaceableKey(event)
                    if (key != null) {
                        val index = replaceable[key]
                        if (index != null) {
                            val current = Json.obj(list[index])?.int("created_at") ?: 0
                            if (event.int("created_at") > current) {
                                list[index] = raw
                                events = list.toList()
                            }
                            return@collect
                        }
                        replaceable[key] = list.size
                    }
                    list.add(raw)
                    events = list.toList()
                    val kind = event.int("kind")
                    countsByKind[kind] = (countsByKind[kind] ?: 0) + 1
                }
            } catch (error: kotlinx.coroutines.CancellationException) {
                throw error
            } catch (error: Throwable) {
                ToastCenter.error(error)
            }
            isScanning = false
        }
    }

    fun stop() {
        scanJob?.cancel()
        broadcastJob?.cancel()
        isScanning = false
    }

    fun rebroadcast() {
        if (events.isEmpty()) {
            ToastCenter.show(L("noEventsToRebroadcast"))
            return
        }
        if (isBroadcasting) return
        val payload = "[${events.joinToString(",")}]"
        isBroadcasting = true
        broadcastSent = 0
        broadcastFailed = 0
        broadcastTotal = events.size
        broadcastJob = viewModelScope.launch {
            var finished = false
            try {
                EventStream.make { sink -> streamBroadcastEvents(payload, null, sink) }.collect { raw ->
                    val progress = Json.obj(raw) ?: return@collect
                    broadcastSent = progress.int("sent")
                    broadcastFailed = progress.int("failed")
                    broadcastTotal = maxOf(broadcastTotal, progress.int("total"))
                    if (progress.bool("done")) finished = true
                }
                if (finished) {
                    feedback += 1
                    val message = if (broadcastFailed > 0) {
                        L("broadcastedEventsWithFailed", "sent" to broadcastSent, "failed" to broadcastFailed)
                    } else {
                        L("broadcastedEvents", "sent" to broadcastSent)
                    }
                    ToastCenter.show(message, ToastStyle.SUCCESS)
                }
            } catch (error: kotlinx.coroutines.CancellationException) {
                throw error
            } catch (error: Throwable) {
                ToastCenter.show(L("errorRebroadcastingEventsDetail", "error" to coreErrorMessage(error)), ToastStyle.ERROR)
            } finally {
                isBroadcasting = false
            }
        }
    }

    val exportFileName: String
        get() {
            val format = SimpleDateFormat("yyyy-MM-dd'T'HH-mm-ss'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }
            return "nostr-export-${(Session.pubkey ?: "unknown").take(8)}-${format.format(Date())}.json"
        }

    fun export(uri: Uri) {
        if (events.isEmpty()) {
            ToastCenter.show(L("noEventsToExport"))
            return
        }
        isExporting = true
        val snapshot = events
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    val array = JSONArray()
                    snapshot.forEach { raw -> Json.obj(raw)?.let(array::put) }
                    val text = array.toString(2).replace("\\/", "/")
                    App.context.contentResolver.openOutputStream(uri)?.use { it.write(text.toByteArray()) } ?: throw IllegalStateException(uri.toString())
                }
                feedback += 1
            } catch (error: Throwable) {
                ToastCenter.show(L("exportFailed", "error" to coreErrorMessage(error)), ToastStyle.ERROR)
            } finally {
                isExporting = false
            }
        }
    }

    fun askFinalConfirmation() {
        confirmText = ""
        showFinalConfirm = true
    }

    fun deleteAccount() {
        if (!canConfirmVanish || isDeleting) return
        val ids = events.mapNotNull { Json.obj(it)?.str("id") }
        isDeleting = true
        val reason = "User requested account deletion"
        App.scope.launch {
            try {
                if (ids.isNotEmpty()) {
                    var deleteSuccess = 0
                    for (chunk in ids.chunked(200)) {
                        val deletion = Json.obj(runCatching { deleteEvents(chunk, reason) }.getOrNull()) ?: JSONObject()
                        deleteSuccess = maxOf(deleteSuccess, deletion.int("totalSuccess"))
                    }
                    if (deleteSuccess > 0) {
                        val key = if (deleteSuccess == 1) "deletionRequestSent" else "deletionRequestSentPlural"
                        ToastCenter.show(L(key, "count" to ids.size, "relays" to deleteSuccess), ToastStyle.SUCCESS)
                    }
                    delay(500)
                }
                val vanish = Json.obj(requestToVanish(listOf("ALL_RELAYS"), reason)) ?: JSONObject()
                val vanishSuccess = vanish.int("totalSuccess")
                if (vanishSuccess > 0) {
                    val key = if (vanishSuccess == 1) "accountDeletionRequestSent" else "accountDeletionRequestSentPlural"
                    ToastCenter.show(L(key, "relays" to vanishSuccess), ToastStyle.SUCCESS)
                    feedback += 1
                } else {
                    val failed = vanish.int("totalFailed")
                    val key = if (failed == 1) "vanishRequestFailed" else "vanishRequestFailedPlural"
                    ToastCenter.show(L(key, "relays" to failed), ToastStyle.ERROR)
                }
                delay(2000)
                stop()
                Session.logout(erasingData = true)
            } catch (error: Throwable) {
                ToastCenter.show(L("errorDeletingAccount", "error" to coreErrorMessage(error)), ToastStyle.ERROR)
            } finally {
                isDeleting = false
            }
        }
    }

    companion object {
        fun replaceableKey(event: JSONObject): String? {
            val kind = event.int("kind")
            if (kind == 0 || kind == 3 || kind in 10000 until 20000) return "$kind"
            if (kind !in 30000 until 40000) return null
            val d = event.tags().firstOrNull { it.firstOrNull() == "d" }?.let { if (it.size > 1) it[1] else null } ?: ""
            return "$kind:$d"
        }

        fun kindName(kind: Int): String = when (kind) {
            0 -> L("kindProfileMetadata")
            1 -> L("kindTextNote")
            3 -> L("kindFollows")
            4 -> L("kindEncryptedDM")
            5 -> L("kindEventDeletion")
            6, 16 -> L("kindRepost")
            7 -> L("kindReaction")
            9735 -> L("kindZap")
            10000 -> L("kindMuteList")
            10002 -> L("kindRelayList")
            10050 -> L("kindDMRelays")
            10051 -> L("kindKeyPackageRelays")
            443, 30443 -> L("kindKeyPackage")
            1111 -> L("kindComment")
            1068 -> L("kindPoll")
            1018 -> L("kindPollVote")
            9802 -> L("kindHighlight")
            10015 -> L("kindInterests")
            10063 -> L("kindMediaServers")
            30000 -> L("kindFollowSet")
            30001, 30003 -> L("kindListSet")
            30023 -> L("kindArticle")
            30024 -> L("kindArticleDraft")
            in 10001..10010 -> L("kindList", "kind" to kind)
            else -> L("kindUnknown", "kind" to kind)
        }

        fun kindIcon(kind: Int): ImageVector = when (kind) {
            0 -> Icons.Outlined.Person
            1 -> Icons.Outlined.Description
            3 -> Icons.Outlined.People
            4 -> Icons.Outlined.Lock
            5 -> Icons.Outlined.Delete
            6 -> Icons.Outlined.Repeat
            7 -> Icons.Outlined.FavoriteBorder
            9735 -> Icons.Outlined.Bolt
            10000 -> Icons.Outlined.NotificationsOff
            10002 -> Icons.Outlined.Hub
            10050, 10051 -> Icons.Outlined.Inbox
            443, 30443 -> Icons.Outlined.Key
            else -> Icons.AutoMirrored.Outlined.Article
        }
    }
}

@Composable
fun EventManagerSettingsScreen() {
    val model: EventManagerModel = viewModel()
    val haptics = rememberHaptics()
    val exporter = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri -> uri?.let(model::export) }
    DisposableEffect(Unit) {
        if (model.events.isEmpty() && !model.isScanning) model.scan()
        onDispose { if (!model.isBroadcasting && !model.isDeleting) model.stop() }
    }
    LaunchedEffect(model.feedback) { if (model.feedback > 0) haptics.success() }

    SettingsScaffold(L("yourDataOnRelays")) {
        settingsSection("summary", footer = L("yourDataOnRelaysDescription")) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).testTag("events-summary"), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(32.dp), contentAlignment = Alignment.Center) {
                    if (model.isScanning) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) else SettingsIcon(Icons.Outlined.Check, AppColors.success)
                }
                Text(
                    if (model.isScanning) L("scanningEventsFound", "count" to model.events.size) else L("eventsOnRelays", "count" to model.events.size),
                    modifier = Modifier.weight(1f).padding(start = 16.dp),
                )
                if (!model.isScanning) {
                    IconButton(onClick = { model.scan() }, modifier = Modifier.testTag("events-rescan")) { Icon(Icons.Outlined.Refresh, L("retry")) }
                }
            }
            if (model.isBroadcasting) {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp).testTag("events-broadcast-progress"), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    LinearProgressIndicator(progress = { model.broadcastProgress }, modifier = Modifier.fillMaxWidth(), color = AppColors.textPrimary)
                    Text(L("broadcastProgress", "sent" to model.broadcastSent, "total" to model.broadcastTotal), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
                }
            }
        }
        settingsSection("actions") {
            SettingsRow(
                if (model.isBroadcasting) L("broadcastProgress", "sent" to model.broadcastSent, "total" to model.broadcastTotal) else L("rebroadcast"),
                Icons.Outlined.SettingsInputAntenna,
                enabled = !model.isBusy && model.events.isNotEmpty(),
                modifier = Modifier.testTag("events-rebroadcast"),
            ) { model.rebroadcast() }
            SettingsRow(
                if (model.isExporting) L("exporting") else L("exportData"),
                Icons.Outlined.IosShare,
                enabled = !model.isExporting && model.events.isNotEmpty(),
                modifier = Modifier.testTag("events-export"),
                trailing = if (model.isExporting) ({ CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) }) else null,
            ) {
                if (model.events.isEmpty()) ToastCenter.show(L("noEventsToExport")) else exporter.launch(model.exportFileName)
            }
        }
        if (model.sortedKinds.isNotEmpty()) {
            settingsSection("kinds") {
                model.sortedKinds.forEach { kind ->
                    SettingsRow(
                        EventManagerModel.kindName(kind),
                        EventManagerModel.kindIcon(kind),
                        subtitle = "kind $kind",
                        value = Sats.compact((model.countsByKind[kind] ?: 0).toLong()),
                        modifier = Modifier.testTag("events-kind-$kind"),
                    )
                }
            }
        }
        if (Session.canSign) {
            settingsSection("delete", footer = L("settingsVanishFooter")) {
                SettingsCenteredAction(L("deleteAccount"), AppColors.error, Modifier.testTag("events-delete-account"), enabled = !model.isBusy, loading = model.isDeleting) {
                    model.showDeleteConfirm = true
                }
            }
        }
    }

    if (model.showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { model.showDeleteConfirm = false },
            title = { Text(L("deleteAccountTitle")) },
            text = { Text(L("deleteAccountConfirmation")) },
            confirmButton = {
                Box(Modifier.testTag("events-delete-continue")) {
                    TextAction(L("delete"), { model.showDeleteConfirm = false; model.askFinalConfirmation() }, color = AppColors.error)
                }
            },
            dismissButton = { TextAction(L("cancel"), { model.showDeleteConfirm = false }) },
        )
    }
    if (model.showFinalConfirm) {
        AlertDialog(
            onDismissRequest = { model.showFinalConfirm = false },
            title = { Text(L("deleteAccountTitle")) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(L("settingsVanishTypeToConfirm", "word" to model.confirmWord))
                    QiqTextField(model.confirmText, { model.confirmText = it }, model.confirmWord, Modifier.testTag("events-delete-confirm-field"))
                }
            },
            confirmButton = {
                Box(Modifier.testTag("events-delete-confirm")) {
                    TextAction(L("deleteAccount"), { model.showFinalConfirm = false; model.deleteAccount() }, enabled = model.canConfirmVanish, color = AppColors.error)
                }
            },
            dismissButton = { TextAction(L("cancel"), { model.showFinalConfirm = false }) },
        )
    }
}
