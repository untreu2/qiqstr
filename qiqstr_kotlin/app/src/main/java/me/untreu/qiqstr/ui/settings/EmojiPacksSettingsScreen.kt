package me.untreu.qiqstr.ui.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.*
import me.untreu.qiqstr.core.components.CustomEmojiImage
import me.untreu.qiqstr.data.services.*
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.domain.Profile

class EmojiPacksSettingsViewModel : ViewModel() {
    fun load() = viewModelScope.launch { EmojiPackService.load(); EmojiPackService.discover() }
    fun add(pack: EmojiPack) = change { EmojiPackService.add(pack) }
    fun remove(pack: EmojiPack) = change { EmojiPackService.remove(pack) }
    private fun change(work: suspend () -> Unit) {
        if (!ReadOnlyGate.check()) return
        viewModelScope.launch { try { work() } catch (error: Exception) { ToastCenter.error(error) } }
    }
}

@Composable
fun EmojiPacksSettingsScreen() {
    val model: EmojiPacksSettingsViewModel = viewModel()
    LaunchedEffect(Unit) { model.load() }
    SettingsScaffold(L("emojiPacksTitle"), tag = "emoji-packs", isRefreshing = EmojiPackService.isDiscovering, onRefresh = { model.load() }) {
        settingsSection("your-packs", header = L("emojiYourPacks"), footer = L("emojiPacksFooter")) {
            if (EmojiPackService.packs.isEmpty()) Column(Modifier.padding(16.dp).testTag("emoji-packs-empty")) { Text(L("emojiNoPacks")); Text(L("emojiNoPacksHere"), color = AppColors.textSecondary) }
        }
        items(EmojiPackService.packs, key = { "own-${it.coordinate}" }) { pack ->
            val row: @Composable () -> Unit = {
                EmojiPackRow(pack) {
                    if (pack.coordinate != EmojiPackService.ownCoordinate) IconButton(onClick = { model.remove(pack) }, enabled = pack.coordinate !in EmojiPackService.busy) { Icon(Icons.Outlined.Delete, L("emojiRemovePack")) }
                }
            }
            if (pack.coordinate == EmojiPackService.ownCoordinate) row() else {
                val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
                    if (value == SwipeToDismissBoxValue.EndToStart && pack.coordinate !in EmojiPackService.busy) model.remove(pack)
                    false
                })
                SwipeToDismissBox(state = state, enableDismissFromStartToEnd = false, backgroundContent = {
                    Box(Modifier.fillMaxSize().background(AppColors.error).padding(16.dp), contentAlignment = Alignment.CenterEnd) { Icon(Icons.Outlined.Delete, L("emojiRemovePack"), tint = MaterialTheme.colorScheme.onError) }
                }) { row() }
            }
        }
        settingsSection("discover", header = L("emojiDiscover")) {
            if (EmojiPackService.isDiscovering) CircularProgressIndicator(Modifier.padding(16.dp))
            else if (EmojiPackService.discovered.none { !EmojiPackService.contains(it.coordinate) }) Text(L("emojiNoSuggestions"), Modifier.padding(16.dp), color = AppColors.textSecondary)
        }
        items(EmojiPackService.discovered.filterNot { EmojiPackService.contains(it.coordinate) }, key = { it.coordinate }) { pack ->
            EmojiPackRow(pack) { IconButton(onClick = { model.add(pack) }, enabled = pack.coordinate !in EmojiPackService.busy, modifier = Modifier.testTag("emoji-pack-add")) { Icon(Icons.Outlined.Add, L("settingsAdd")) } }
        }
    }
}

@Composable
private fun EmojiPackRow(pack: EmojiPack, action: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().background(AppColors.background).padding(horizontal = 16.dp, vertical = 12.dp).testTag("emoji-pack-row"), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("${pack.title}  ${pack.emojis.size}", style = MaterialTheme.typography.titleMedium)
            if (pack.coordinate != EmojiPackService.ownCoordinate) Text(ProfileCache.profile(pack.author)?.bestName ?: Profile.shortNpub(pack.author), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) { pack.emojis.take(8).forEach { CustomEmojiImage(it.url, 24.dp) } }
        }
        action()
    }
}
