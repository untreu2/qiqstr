package me.untreu.qiqstr.ui.settings

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Article
import androidx.compose.material.icons.automirrored.outlined.Notes
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Repeat
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.qiqstr.core.dbGetDatabaseStats
import com.qiqstr.core.dbSmartCleanup
import com.qiqstr.core.dbWipe
import com.qiqstr.core.dbWipeDirectory
import com.qiqstr.core.getDatabaseSizeMb
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.ui.auth.rememberHaptics
import org.json.JSONObject

data class DatabaseKindStat(val id: String, val title: String, val icon: ImageVector, val count: Int)

class DatabaseSettingsModel : ViewModel() {
    var stats by mutableStateOf<List<DatabaseKindStat>>(emptyList())
        private set
    var totalEvents by mutableIntStateOf(0)
        private set
    var sizeMB by mutableLongStateOf(0)
        private set
    var isLoading by mutableStateOf(false)
        private set
    var isCleaning by mutableStateOf(false)
        private set
    var isWiping by mutableStateOf(false)
        private set
    var hasLoaded by mutableStateOf(false)
        private set
    var showWipeConfirm by mutableStateOf(false)
    var showCleanupConfirm by mutableStateOf(false)
    var feedback by mutableIntStateOf(0)
        private set

    fun load() {
        viewModelScope.launch { reload() }
    }

    private suspend fun reload() {
        isLoading = true
        try {
            val json = Json.obj(dbGetDatabaseStats()) ?: JSONObject()
            sizeMB = runCatching { getDatabaseSizeMb().toLong() }.getOrDefault(0)
            totalEvents = json.int("totalEvents")
            stats = listOf(
                DatabaseKindStat("textNotes", L("textNotes"), Icons.AutoMirrored.Outlined.Notes, json.int("textNotes")),
                DatabaseKindStat("metadata", L("profiles"), Icons.Outlined.Person, json.int("metadata")),
                DatabaseKindStat("contacts", L("contactLists"), Icons.Outlined.People, json.int("contacts")),
                DatabaseKindStat("reactions", L("reactions"), Icons.Outlined.FavoriteBorder, json.int("reactions")),
                DatabaseKindStat("reposts", L("reposts"), Icons.Outlined.Repeat, json.int("reposts")),
                DatabaseKindStat("zaps", L("zaps"), Icons.Outlined.Bolt, json.int("zaps")),
                DatabaseKindStat("articles", L("articles"), Icons.AutoMirrored.Outlined.Article, json.int("articles")),
            )
        } catch (error: Throwable) {
            ToastCenter.error(error)
        } finally {
            isLoading = false
            hasLoaded = true
        }
    }

    fun smartCleanup() {
        val me = Session.pubkey ?: return
        if (isCleaning) return
        isCleaning = true
        viewModelScope.launch {
            try {
                val result = Json.obj(dbSmartCleanup(me, 7u, 7u)) ?: JSONObject()
                feedback += 1
                ToastCenter.show(L("settingsCleanupResult", "count" to result.int("totalDeleted")), ToastStyle.SUCCESS)
                DataBus.everythingChanged()
                reload()
            } catch (error: Throwable) {
                ToastCenter.error(error)
            } finally {
                isCleaning = false
            }
        }
    }

    fun wipe() {
        if (isWiping) return
        isWiping = true
        viewModelScope.launch {
            try {
                try { dbWipeDirectory() } catch (error: Throwable) { dbWipe() }
                feedback += 1
                ToastCenter.show("${L("cleanupCompleted")} — ${L("eventsDeleted")}", ToastStyle.SUCCESS)
                reload()
                DataBus.everythingChanged()
                App.scope.launch { resync() }
            } catch (error: Throwable) {
                ToastCenter.error(error)
            } finally {
                isWiping = false
            }
        }
    }

    private suspend fun resync() {
        val me = Session.pubkey ?: return
        coroutineScope {
            launch { SyncService.syncFollowingList(me, force = true) }
            launch { SyncService.syncProfile(me, force = true) }
        }
        SyncService.syncFeed(force = true)
        SyncService.syncNotifications(force = true)
    }
}

@Composable
fun DatabaseSettingsScreen() {
    val model: DatabaseSettingsModel = viewModel()
    val haptics = rememberHaptics()
    LaunchedEffect(Unit) { model.load() }
    LaunchedEffect(model.feedback) { if (model.feedback > 0) haptics.success() }
    val busy = model.isCleaning || model.isWiping
    SettingsScaffold(L("databaseCache"), isRefreshing = model.isLoading && model.hasLoaded, onRefresh = { model.load() }) {
        settingsSection("summary", footer = L("databaseCacheSubtitle")) {
            Box(Modifier.alpha(if (model.hasLoaded) 1f else 0.4f)) {
                androidx.compose.foundation.layout.Column {
                    SettingsRow(L("databaseSize"), Icons.Outlined.Storage, value = "${model.sizeMB} MB", modifier = Modifier.testTag("database-size"))
                    SettingsRow(L("totalEvents"), Icons.Outlined.Layers, value = Sats.compact(model.totalEvents.toLong()), modifier = Modifier.testTag("database-total"))
                }
            }
        }
        settingsSection("kinds") {
            model.stats.forEach { stat ->
                SettingsRow(stat.title, stat.icon, value = Sats.compact(stat.count.toLong()), modifier = Modifier.testTag("database-stat-${stat.id}"))
            }
        }
        settingsSection("cleanup", footer = L("settingsSmartCleanupFooter")) {
            SettingsRow(
                L("settingsSmartCleanup"),
                Icons.Outlined.AutoAwesome,
                enabled = !busy,
                modifier = Modifier.testTag("database-smart-cleanup"),
                trailing = if (model.isCleaning) ({ CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) }) else null,
            ) { model.showCleanupConfirm = true }
        }
        settingsSection("wipe", footer = L("settingsWipeFooter")) {
            SettingsCenteredAction(L("cleanupDatabase"), AppColors.error, Modifier.testTag("database-wipe"), enabled = !busy, loading = model.isWiping) {
                model.showWipeConfirm = true
            }
        }
    }
    if (model.showCleanupConfirm) {
        AlertDialog(
            onDismissRequest = { model.showCleanupConfirm = false },
            title = { Text(L("settingsSmartCleanup")) },
            text = { Text(L("settingsSmartCleanupFooter")) },
            confirmButton = {
                Box(Modifier.testTag("database-smart-cleanup-confirm")) {
                    TextAction(L("cleanup"), { model.showCleanupConfirm = false; model.smartCleanup() })
                }
            },
            dismissButton = { TextAction(L("cancel"), { model.showCleanupConfirm = false }) },
        )
    }
    if (model.showWipeConfirm) {
        AlertDialog(
            onDismissRequest = { model.showWipeConfirm = false },
            title = { Text(L("cleanupDatabase")) },
            text = { Text(L("settingsWipeConfirm")) },
            confirmButton = {
                Box(Modifier.testTag("database-wipe-confirm")) {
                    TextAction(L("settingsWipeAction"), { model.showWipeConfirm = false; model.wipe() }, color = AppColors.error)
                }
            },
            dismissButton = { TextAction(L("cancel"), { model.showWipeConfirm = false }) },
        )
    }
}
