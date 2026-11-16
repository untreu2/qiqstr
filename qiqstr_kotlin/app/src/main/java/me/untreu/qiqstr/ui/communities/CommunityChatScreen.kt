package me.untreu.qiqstr.ui.communities

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.Flow
import me.untreu.qiqstr.App
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.*
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.services.ReadOnlyGate
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.dm.DMFormat
import me.untreu.qiqstr.ui.live.ChatText
import me.untreu.qiqstr.ui.live.LiveChatInput

class CommunityChatViewModel(private val id: String, private val channelTarget: Boolean) : ViewModel() {
    var group by mutableStateOf<RelayGroup?>(if (channelTarget) null else RelayGroup.link(id))
        private set
    var channel by mutableStateOf<PublicChannel?>(null)
        private set
    var messages by mutableStateOf<List<CommunityChatMessage>>(emptyList())
        private set
    var loaded by mutableStateOf(false)
        private set
    var missing by mutableStateOf(false)
        private set
    var sending by mutableStateOf(false)
        private set
    var updating by mutableStateOf(false)
        private set
    var memberCount by mutableStateOf<Int?>(null)
        private set
    var draft by mutableStateOf("")
    private var streamJob: Job? = null
    private var started = false
    val title: String get() = group?.displayName ?: channel?.displayName.orEmpty()
    val about: String get() = group?.about ?: channel?.about.orEmpty()
    val joined: Boolean get() = group?.let(CommunityService::isJoined) ?: channel?.let(CommunityService::isJoined) ?: false
    val canSend: Boolean get() = draft.isNotBlank() && !sending && (group != null || channel != null)
    val shareLink: String? get() = group?.id ?: channel?.id?.let(Nip19::note)?.let { "nostr:$it" }
    suspend fun start() {
        if (started) return
        started = true
        try {
            if (!CommunityService.hasLoaded) CommunityService.load()
            if (channelTarget) {
                channel = CommunityService.channel(id)
                val target = channel ?: run { missing = true; return }
                listen { CommunityService.channelStream(target) }
                merge(CommunityService.channelHistory(target))
            } else {
                val ref = group ?: run { missing = true; return }
                group = CommunityService.group(ref)
                listen { CommunityService.groupStream(ref) }
                coroutineScope { launch { merge(CommunityService.groupHistory(ref)) }; launch { memberCount = CommunityService.groupMemberCount(ref) } }
            }
            ProfileCache.load(messages.map { it.pubkey }.distinct())
        } catch (error: CancellationException) { started = false; throw error } catch (error: Throwable) { ToastCenter.error(error) } finally { loaded = true }
    }
    private fun listen(source: suspend () -> Flow<CommunityChatMessage>) {
        streamJob?.cancel()
        streamJob = viewModelScope.launch {
            while (isActive) {
                try { source().collect { merge(listOf(it)); ProfileCache.load(listOf(it.pubkey)) } }
                catch (error: CancellationException) { throw error } catch (_: Throwable) { }
                delay(3000)
            }
        }
    }
    fun stop() { streamJob?.cancel(); streamJob = null; started = false }
    private fun merge(incoming: List<CommunityChatMessage>) { messages = (messages + incoming).filter { it.pubkey !in Session.mutedPubkeys }.distinctBy { it.id }.sortedWith(compareBy({ it.createdAt }, { it.id })).takeLast(1000) }
    fun applyMutes() { messages = messages.filter { it.pubkey !in Session.mutedPubkeys } }
    fun send() {
        if (!canSend || !ReadOnlyGate.check()) return
        val text = draft; draft = ""; sending = true
        viewModelScope.launch {
            try { val message = group?.let { CommunityService.send(text, it) } ?: channel?.let { CommunityService.send(text, it) }; if (message != null) merge(listOf(message)) }
            catch (error: Throwable) { if (draft.isEmpty()) draft = text; ToastCenter.error(error) }
            finally { sending = false }
        }
    }
    fun toggleMembership() {
        if (updating || !ReadOnlyGate.check()) return
        updating = true
        viewModelScope.launch {
            try {
                group?.let { if (joined) CommunityService.leave(it) else CommunityService.join(it) }
                channel?.let { if (joined) CommunityService.leave(it) else CommunityService.join(it) }
                ToastCenter.show(L(if (joined) "communityJoinedToast" else "communityLeftToast"), ToastStyle.SUCCESS)
            } catch (error: Throwable) { ToastCenter.error(error) } finally { updating = false }
        }
    }
    fun copyLink() { shareLink?.let { (App.context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("nostr", it)); ToastCenter.show(L("copiedToClipboard"), ToastStyle.SUCCESS) } }
}

@Composable
fun CommunityChatScreen(id: String, channel: Boolean = false) {
    val model: CommunityChatViewModel = viewModel { CommunityChatViewModel(id, channel) }
    var info by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { model.start() }
    LaunchedEffect(Session.mutedPubkeys) { model.applyMutes() }
    DisposableEffect(model) { onDispose { model.stop() } }
    Scaffold(topBar = { TopAppBar(title = { Text(model.title) }, navigationIcon = { IconButton(onClick = { Router.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } }, actions = { IconButton(onClick = { info = true }, modifier = Modifier.testTag("community-chat-info")) { Icon(Icons.Outlined.Info, L("communityInfo")) } }) }, bottomBar = {
        if (!model.missing) Column {
            if (model.group != null && !model.joined && model.loaded) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(L(if (model.group?.isClosed == true) "communityClosedBanner" else "communityJoinBanner"), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, modifier = Modifier.weight(1f))
                    Spacer(Modifier.width(12.dp))
                    Button(onClick = model::toggleMembership, enabled = !model.updating, colors = ButtonDefaults.buttonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background), modifier = Modifier.testTag("community-join")) { Text(L("communityJoin")) }
                }
            }
            LiveChatInput(model.draft, { model.draft = it }, model.canSend, model.sending, model::send)
        }
    }, modifier = Modifier.testTag("community-chat")) { padding ->
        val state = rememberLazyListState()
        LaunchedEffect(model.messages.lastOrNull()?.id) { if (model.messages.isNotEmpty()) state.animateScrollToItem(model.messages.lastIndex) }
        LazyColumn(Modifier.fillMaxSize().padding(padding), state = state, contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            if (!model.loaded) item { CircularProgressIndicator() }
            else if (model.missing || model.messages.isEmpty()) item { Text(L(if (model.missing) "communityNotFound" else "communityChatEmpty")) }
            items(model.messages, key = { it.id }) { message ->
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.testTag("community-chat-message")) {
                    ProfileAvatar(message.pubkey, size = 32.dp, modifier = Modifier.clickable { Router.push(Route.Profile(message.pubkey)) })
                    Column(Modifier.weight(1f)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text(ProfileCache.profile(message.pubkey)?.bestName ?: Profile.shortNpub(message.pubkey), style = MaterialTheme.typography.labelLarge); Text(DMFormat.time(message.createdAt), style = MaterialTheme.typography.labelSmall, color = AppColors.textSecondary) }
                        ChatText(message.content)
                    }
                }
            }
        }
    }
    if (info) ModalBottomSheet(onDismissRequest = { info = false }) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(model.title, style = MaterialTheme.typography.headlineSmall)
            if (model.about.isNotEmpty()) Text(model.about)
            model.group?.let { Text(it.relay); if (it.isClosed) Text(L("communityClosed")) }
            model.memberCount?.let { Text(L("communityMembers", "count" to it)) }
            model.channel?.let { channel -> TextButton(onClick = { info = false; Router.push(Route.Profile(channel.creator)) }) { Text(L("communityCreator") + ": " + (ProfileCache.profile(channel.creator)?.bestName ?: Profile.shortNpub(channel.creator))) } }
            TextButton(onClick = model::copyLink) { Text(L("communityCopyLink")) }
            TextButton(onClick = model::toggleMembership, enabled = !model.updating, modifier = Modifier.testTag("community-membership")) { Text(L(if (model.joined) "communityLeave" else "communityJoin")) }
        }
    }
}
