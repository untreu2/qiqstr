package me.untreu.qiqstr.ui.settings

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.VolumeUp
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.PersonOff
import androidx.compose.material.icons.outlined.TextFields
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.components.QiqTextField
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.services.MuteService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.auth.rememberHaptics

class MutedSettingsModel : ViewModel() {
    enum class Tab { USERS, WORDS;

        val title: String get() = if (this == USERS) L("mutedUsersTitle") else L("mutedWordsTitle")
    }

    var tab by mutableStateOf(Tab.USERS)
    var newWord by mutableStateOf("")
    var showAddWord by mutableStateOf(false)
    var busy by mutableStateOf<Set<String>>(emptySet())
        private set
    var isRefreshing by mutableStateOf(false)
        private set
    var feedback by mutableIntStateOf(0)
        private set

    fun appear() {
        viewModelScope.launch {
            if (!MuteService.isLoaded) MuteService.load()
            ProfileCache.load(MuteService.mutedPubkeys)
        }
    }

    fun refresh() {
        viewModelScope.launch {
            isRefreshing = true
            MuteService.load()
            val pubkeys = MuteService.mutedPubkeys
            if (pubkeys.isNotEmpty()) SyncService.syncProfiles(pubkeys)
            ProfileCache.load(pubkeys, fetchMissing = false)
            for (pk in pubkeys) ProfileCache.refresh(pk)
            isRefreshing = false
        }
    }

    fun unmute(pubkey: String) {
        if (pubkey in busy) return
        busy = busy + pubkey
        viewModelScope.launch {
            try {
                MuteService.unmute(pubkey)
                feedback += 1
                ToastCenter.show(L("userUnmuted"), ToastStyle.SUCCESS)
            } catch (error: Throwable) {
                ToastCenter.error(error)
            } finally {
                busy = busy - pubkey
            }
        }
    }

    fun addWord() {
        val word = newWord.trim().lowercase()
        if (word.isEmpty()) return
        if (word in MuteService.mutedWords) { newWord = ""; return }
        newWord = ""
        val key = "word:$word"
        busy = busy + key
        viewModelScope.launch {
            try {
                MuteService.addWord(word)
                feedback += 1
            } catch (error: Throwable) {
                newWord = word
                ToastCenter.error(error)
            } finally {
                busy = busy - key
            }
        }
    }

    fun removeWord(word: String) {
        val key = "word:$word"
        if (key in busy) return
        busy = busy + key
        viewModelScope.launch {
            try {
                MuteService.removeWord(word)
                feedback += 1
            } catch (error: Throwable) {
                ToastCenter.error(error)
            } finally {
                busy = busy - key
            }
        }
    }

    fun isBusy(key: String) = key in busy
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MutedSettingsScreen() {
    val model: MutedSettingsModel = viewModel()
    val haptics = rememberHaptics()
    LaunchedEffect(Unit) { model.appear() }
    LaunchedEffect(model.feedback) { if (model.feedback > 0) haptics.success() }
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    Scaffold(
        containerColor = AppColors.background,
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text(L("mutedTitle")) },
                navigationIcon = { IconButton(onClick = { Router.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } },
                actions = {
                    if (model.tab == MutedSettingsModel.Tab.WORDS) {
                        IconButton(onClick = { model.newWord = ""; model.showAddWord = true }, modifier = Modifier.testTag("muted-word-add")) {
                            Icon(Icons.Filled.Add, L("settingsAddWord"))
                        }
                    }
                },
                scrollBehavior = scrollBehavior,
                colors = TopAppBarDefaults.largeTopAppBarColors(containerColor = AppColors.background, scrolledContainerColor = AppColors.background),
            )
        },
    ) { padding ->
        PullToRefreshBox(isRefreshing = model.isRefreshing, onRefresh = { model.refresh() }, modifier = Modifier.fillMaxSize().padding(padding)) {
            LazyColumn(Modifier.fillMaxSize()) {
                item("tabs") {
                    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().testTag("muted-tab")) {
                            MutedSettingsModel.Tab.entries.forEachIndexed { index, tab ->
                                val count = if (tab == MutedSettingsModel.Tab.USERS) MuteService.mutedPubkeys.size else MuteService.mutedWords.size
                                SegmentedButton(
                                    selected = model.tab == tab,
                                    onClick = { model.tab = tab },
                                    shape = SegmentedButtonDefaults.itemShape(index, MutedSettingsModel.Tab.entries.size),
                                ) { Text("${tab.title} ($count)", maxLines = 1) }
                            }
                        }
                        Text(L("mutedSubtitle"), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
                    }
                }
                when (model.tab) {
                    MutedSettingsModel.Tab.USERS -> when {
                        !MuteService.isLoaded -> items(3) { MutedPlaceholderRow() }
                        MuteService.mutedPubkeys.isEmpty() -> item("users-empty") {
                            EmptyStateView(Icons.Outlined.PersonOff, L("noMutedUsers"), L("youHaventMutedAnyUsersYet"), modifier = Modifier.testTag("muted-users-empty"))
                        }
                        else -> items(MuteService.mutedPubkeys, key = { it }) { pubkey ->
                            MutedUserRow(pubkey, model.isBusy(pubkey), Modifier.animateItem()) { model.unmute(pubkey) }
                        }
                    }
                    MutedSettingsModel.Tab.WORDS -> if (MuteService.mutedWords.isEmpty()) {
                        item("words-empty") {
                            EmptyStateView(Icons.Outlined.TextFields, L("settingsNoMutedWords"), modifier = Modifier.testTag("muted-words-empty"))
                        }
                    } else {
                        items(MuteService.mutedWords, key = { "word-$it" }) { word ->
                            MutedWordRow(word, model.isBusy("word:$word"), Modifier.animateItem()) { model.removeWord(word) }
                        }
                    }
                }
            }
        }
    }

    if (model.showAddWord) {
        AlertDialog(
            onDismissRequest = { model.showAddWord = false; model.newWord = "" },
            title = { Text(L("settingsAddWord")) },
            text = { QiqTextField(model.newWord, { model.newWord = it }, L("addWordToMuteHint"), Modifier.testTag("muted-word-field")) },
            confirmButton = {
                Box(Modifier.testTag("muted-word-add-confirm")) {
                    TextAction(L("settingsAdd"), { model.showAddWord = false; model.addWord() }, enabled = model.newWord.isNotBlank())
                }
            },
            dismissButton = { TextAction(L("cancel"), { model.showAddWord = false; model.newWord = "" }) },
        )
    }
}

@Composable
private fun MutedPlaceholderRow() {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(40.dp).clip(CircleShape).background(AppColors.tile))
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Box(Modifier.width(140.dp).height(14.dp).clip(RoundedCornerShape(4.dp)).background(AppColors.tile))
            Box(Modifier.width(100.dp).height(12.dp).clip(RoundedCornerShape(4.dp)).background(AppColors.tile))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun MutedUserRow(pubkey: String, isBusy: Boolean, modifier: Modifier, onUnmute: () -> Unit) {
    val profile = ProfileCache.profiles[pubkey]
    var menu by remember { mutableStateOf(false) }
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart) onUnmute()
        false
    })
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Row(
                Modifier.fillMaxSize().background(AppColors.error).padding(horizontal = 20.dp).testTag("muted-unmute-$pubkey"),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.AutoMirrored.Outlined.VolumeUp, null, tint = MaterialTheme.colorScheme.onError)
                Text(L("unmute"), color = MaterialTheme.colorScheme.onError)
            }
        },
        modifier = modifier,
    ) {
        Box {
            Row(
                Modifier.fillMaxWidth().background(AppColors.background)
                    .combinedClickable(onClick = { Router.push(Route.Profile(pubkey)) }, onLongClick = { menu = true })
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                ProfileAvatar(pubkey, size = 40.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(profile?.bestName ?: Profile.shortNpub(pubkey), fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(profile?.nip05?.ifEmpty { null } ?: Profile.shortNpub(pubkey), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                if (isBusy) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(
                    text = { Text(L("unmute")) },
                    leadingIcon = { Icon(Icons.AutoMirrored.Outlined.VolumeUp, null) },
                    onClick = { menu = false; onUnmute() },
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun MutedWordRow(word: String, isBusy: Boolean, modifier: Modifier, onDelete: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart) onDelete()
        false
    })
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(Modifier.fillMaxSize().background(AppColors.error).padding(horizontal = 20.dp), contentAlignment = Alignment.CenterEnd) {
                Icon(Icons.Outlined.Delete, L("delete"), tint = MaterialTheme.colorScheme.onError)
            }
        },
        modifier = modifier.testTag("muted-word-$word"),
    ) {
        Box {
            SettingsRow(
                word,
                Icons.Outlined.TextFields,
                modifier = Modifier.combinedClickable(onClick = {}, onLongClick = { menu = true }),
                trailing = if (isBusy) ({ CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) }) else null,
            )
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(
                    text = { Text(L("delete"), color = AppColors.error) },
                    leadingIcon = { Icon(Icons.Outlined.Delete, null, tint = AppColors.error) },
                    onClick = { menu = false; onDelete() },
                )
            }
        }
    }
}
