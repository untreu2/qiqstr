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
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material.icons.outlined.PersonOff
import androidx.compose.material.icons.outlined.Tag
import androidx.compose.material.icons.outlined.TextFields
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Tab
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
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
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.auth.rememberHaptics
import me.untreu.qiqstr.ui.note.NoteRepository

class MutedSettingsModel : ViewModel() {
    enum class Tab(val raw: String) {
        USERS("users"), WORDS("words"), HASHTAGS("hashtags"), THREADS("threads");

        val title: String
            get() = when (this) {
                USERS -> L("mutedUsersTitle")
                WORDS -> L("mutedWordsTitle")
                HASHTAGS -> L("mutedHashtagsTitle")
                THREADS -> L("mutedThreadsTitle")
            }
    }

    var tab by mutableStateOf(Tab.USERS)
    var newWord by mutableStateOf("")
    var showAddWord by mutableStateOf(false)
    var newHashtag by mutableStateOf("")
    var showAddHashtag by mutableStateOf(false)
    var threadNotes by mutableStateOf<Map<String, Note>>(emptyMap())
        private set
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

    fun addHashtag() {
        val tag = MuteService.normalizedHashtag(newHashtag)
        newHashtag = ""
        if (tag.isEmpty()) return
        viewModelScope.launch {
            MuteService.muteHashtag(tag)
            feedback += 1
        }
    }

    fun removeHashtag(tag: String) {
        viewModelScope.launch {
            MuteService.unmuteHashtag(tag)
            feedback += 1
        }
    }

    fun unmuteThread(id: String) {
        viewModelScope.launch {
            MuteService.unmuteThread(id)
            feedback += 1
        }
    }

    suspend fun loadThreads() {
        val missing = MuteService.mutedThreads.filter { it !in threadNotes }
        if (missing.isEmpty()) return
        threadNotes = threadNotes + NoteRepository.notes(missing).associateBy { it.id }
        for (id in missing) {
            if (id in threadNotes) continue
            NoteRepository.ensureNote(id)?.let { threadNotes = threadNotes + (id to it) }
        }
        ProfileCache.load(threadNotes.values.map { it.pubkey }.distinct())
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MutedSettingsScreen() {
    val model: MutedSettingsModel = viewModel()
    val haptics = rememberHaptics()
    LaunchedEffect(Unit) { model.appear() }
    LaunchedEffect(model.feedback) { if (model.feedback > 0) haptics.success() }
    LaunchedEffect(MuteService.mutedThreads) { model.loadThreads() }
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
                    if (model.tab == MutedSettingsModel.Tab.HASHTAGS) {
                        IconButton(onClick = { model.newHashtag = ""; model.showAddHashtag = true }, modifier = Modifier.testTag("muted-hashtag-add")) {
                            Icon(Icons.Filled.Add, L("settingsAddHashtag"))
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
                    Column(Modifier.padding(bottom = 8.dp)) {
                        PrimaryScrollableTabRow(
                            selectedTabIndex = model.tab.ordinal,
                            containerColor = AppColors.background,
                            edgePadding = 0.dp,
                            divider = {},
                            modifier = Modifier.fillMaxWidth().testTag("muted-tab"),
                        ) {
                            MutedSettingsModel.Tab.entries.forEach { tab ->
                                Tab(
                                    selected = model.tab == tab,
                                    onClick = { model.tab = tab },
                                    text = { Text(tab.title, maxLines = 1) },
                                    modifier = Modifier.testTag("muted-tab-${tab.raw}"),
                                )
                            }
                        }
                        HorizontalDivider(color = AppColors.divider)
                        Text(
                            L("mutedSubtitle"),
                            style = MaterialTheme.typography.bodySmall,
                            color = AppColors.textSecondary,
                            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp),
                        )
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
                            MutedTextRow(word, Icons.Outlined.TextFields, model.isBusy("word:$word"), Modifier.animateItem().testTag("muted-word-$word")) { model.removeWord(word) }
                        }
                    }
                    MutedSettingsModel.Tab.HASHTAGS -> if (MuteService.mutedHashtags.isEmpty()) {
                        item("hashtags-empty") {
                            EmptyStateView(Icons.Outlined.Tag, L("settingsNoMutedHashtags"), L("settingsNoMutedHashtagsMessage"), modifier = Modifier.testTag("muted-hashtags-empty"))
                        }
                    } else {
                        items(MuteService.mutedHashtags, key = { "hashtag-$it" }) { tag ->
                            MutedTextRow("#$tag", Icons.Outlined.Tag, false, Modifier.animateItem().testTag("muted-hashtag-$tag")) { model.removeHashtag(tag) }
                        }
                    }
                    MutedSettingsModel.Tab.THREADS -> if (MuteService.mutedThreads.isEmpty()) {
                        item("threads-empty") {
                            EmptyStateView(Icons.Outlined.NotificationsOff, L("settingsNoMutedThreads"), L("settingsNoMutedThreadsMessage"), modifier = Modifier.testTag("muted-threads-empty"))
                        }
                    } else {
                        items(MuteService.mutedThreads, key = { "thread-$it" }) { id ->
                            MutedThreadRow(id, model.threadNotes[id], Modifier.animateItem().testTag("muted-thread-$id")) { model.unmuteThread(id) }
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

    if (model.showAddHashtag) {
        AlertDialog(
            onDismissRequest = { model.showAddHashtag = false; model.newHashtag = "" },
            title = { Text(L("settingsAddHashtag")) },
            text = { QiqTextField(model.newHashtag, { model.newHashtag = it }, L("addHashtagToMuteHint"), Modifier.testTag("muted-hashtag-field")) },
            confirmButton = {
                Box(Modifier.testTag("muted-hashtag-add-confirm")) {
                    TextAction(L("settingsAdd"), { model.showAddHashtag = false; model.addHashtag() }, enabled = MuteService.normalizedHashtag(model.newHashtag).isNotEmpty())
                }
            },
            dismissButton = { TextAction(L("cancel"), { model.showAddHashtag = false; model.newHashtag = "" }) },
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
private fun MutedTextRow(title: String, icon: ImageVector, isBusy: Boolean, modifier: Modifier, onDelete: () -> Unit) {
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
        modifier = modifier,
    ) {
        Box {
            SettingsRow(
                title,
                icon,
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

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun MutedThreadRow(noteId: String, note: Note?, modifier: Modifier, onUnmute: () -> Unit) {
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
                Modifier.fillMaxSize().background(AppColors.error).padding(horizontal = 20.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Outlined.Notifications, null, tint = MaterialTheme.colorScheme.onError)
                Text(L("unmute"), color = MaterialTheme.colorScheme.onError)
            }
        },
        modifier = modifier,
    ) {
        Box {
            Column(
                Modifier.fillMaxWidth().background(AppColors.background)
                    .combinedClickable(onClick = { Router.push(Route.Thread(noteId)) }, onLongClick = { menu = true })
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                if (note != null) {
                    val name = ProfileCache.profiles[note.pubkey]?.bestName ?: note.authorName ?: Profile.shortNpub(note.pubkey)
                    Text(name, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(note.content.trim().replace("\n", " "), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                } else {
                    Text(L("thread"), fontWeight = FontWeight.SemiBold)
                    Text("${noteId.take(12)}…", style = MaterialTheme.typography.bodyMedium, fontFamily = FontFamily.Monospace, color = AppColors.textSecondary)
                }
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(
                    text = { Text(L("feedUnmuteConversation")) },
                    leadingIcon = { Icon(Icons.Outlined.Notifications, null) },
                    onClick = { menu = false; onUnmute() },
                )
            }
        }
    }
}
