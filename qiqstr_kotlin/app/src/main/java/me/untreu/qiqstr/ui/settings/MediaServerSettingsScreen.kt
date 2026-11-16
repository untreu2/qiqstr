package me.untreu.qiqstr.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.QiqTextField
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.services.MediaServerStore
import me.untreu.qiqstr.data.services.ReadOnlyGate
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.ui.auth.rememberHaptics

class MediaServerSettingsModel : ViewModel() {
    var feedback by mutableIntStateOf(0)
        private set

    fun load() {
        viewModelScope.launch { MediaServerStore.load() }
    }

    fun select(server: String) {
        if (!ReadOnlyGate.check()) return
        viewModelScope.launch {
            try {
                MediaServerStore.select(server)
                feedback += 1
            } catch (error: Throwable) {
                ToastCenter.error(error)
            }
        }
    }

    fun remove(server: String) {
        viewModelScope.launch {
            try {
                MediaServerStore.remove(server)
            } catch (error: Throwable) {
                ToastCenter.error(error)
            }
        }
    }
}

@Composable
fun MediaServerSettingsScreen() {
    val model: MediaServerSettingsModel = viewModel()
    val haptics = rememberHaptics()
    var showAdd by remember { mutableStateOf(false) }
    var newServer by remember { mutableStateOf("") }
    val isSaving = MediaServerStore.isSaving
    LaunchedEffect(Unit) { model.load() }
    LaunchedEffect(model.feedback) { if (model.feedback > 0) haptics.success() }
    Box(Modifier.fillMaxSize()) {
        SettingsScaffold(L("settingsMediaServer"), tag = "media-server-list") {
            settingsSection("servers", L("settingsMediaServerUpload"), footer = L("settingsMediaServerFooter")) {
                val current = MediaServerStore.current
                MediaServerStore.options.forEach { server ->
                    key(server) {
                        MediaServerRow(
                            server = server,
                            isSelected = server == current,
                            isRemovable = server in MediaServerStore.servers && server != current,
                            enabled = !isSaving,
                            onSelect = { model.select(server) },
                            onRemove = { model.remove(server) },
                        )
                    }
                }
            }
            settingsSection("add") {
                SettingsRow(L("settingsMediaServerAdd"), Icons.Outlined.Add, modifier = Modifier.testTag("media-server-add"), enabled = !isSaving) {
                    newServer = ""
                    showAdd = true
                }
            }
        }
        if (isSaving) CircularProgressIndicator(Modifier.align(Alignment.Center), color = AppColors.textPrimary)
    }

    if (showAdd) {
        AlertDialog(
            onDismissRequest = { showAdd = false },
            title = { Text(L("settingsMediaServerAdd")) },
            text = { QiqTextField(newServer, { newServer = it }, "blossom.example.com", Modifier.testTag("media-server-field"), keyboardType = KeyboardType.Uri) },
            confirmButton = {
                Box(Modifier.testTag("media-server-add-confirm")) {
                    TextAction(L("settingsAdd"), { showAdd = false; model.select(newServer) }, enabled = MediaServerStore.normalized(newServer) != null)
                }
            },
            dismissButton = { TextAction(L("cancel"), { showAdd = false }) },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MediaServerRow(server: String, isSelected: Boolean, isRemovable: Boolean, enabled: Boolean, onSelect: () -> Unit, onRemove: () -> Unit) {
    val name = MediaServerStore.displayName(server)
    val row = @Composable {
        SettingsRow(
            name,
            Icons.Outlined.Dns,
            modifier = Modifier.semantics { selected = isSelected }.testTag("media-server-$name"),
            enabled = enabled,
            trailing = if (isSelected) ({ Icon(Icons.Filled.Check, null, tint = AppColors.textPrimary) }) else null,
            onClick = onSelect,
        )
    }
    if (!isRemovable) {
        row()
        return
    }
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart) onRemove()
        false
    })
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        gesturesEnabled = enabled,
        backgroundContent = {
            Box(Modifier.fillMaxSize().background(AppColors.error).padding(horizontal = 20.dp), contentAlignment = Alignment.CenterEnd) {
                Icon(Icons.Outlined.Delete, L("delete"), tint = MaterialTheme.colorScheme.onError)
            }
        },
    ) { row() }
}
