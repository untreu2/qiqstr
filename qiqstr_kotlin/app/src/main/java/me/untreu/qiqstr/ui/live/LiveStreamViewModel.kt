package me.untreu.qiqstr.ui.live

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.AppSheet
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.data.services.LiveChatMessage
import me.untreu.qiqstr.data.services.LiveService
import me.untreu.qiqstr.data.services.LiveStream
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session

class LiveStreamViewModel(val coordinate: String) : ViewModel() {
    var stream by mutableStateOf(LiveService.cached(coordinate))
        private set
    var notFound by mutableStateOf(false)
        private set
    var playbackURL by mutableStateOf<String?>(null)
        private set
    var messages by mutableStateOf<List<LiveChatMessage>>(emptyList())
        private set
    var chatLoaded by mutableStateOf(false)
        private set
    var isSending by mutableStateOf(false)
        private set
    var draft by mutableStateOf("")
    var isPlaying by mutableStateOf(true)
        private set
    private val seen = HashSet<String>()

    val canSend: Boolean get() = !isSending && draft.trim().isNotEmpty()
    val showsChatInput: Boolean get() = stream?.isLive == true

    suspend fun load() {
        if (stream == null) {
            stream = LiveService.stream(coordinate)
            notFound = stream == null
        }
        startPlayback()
    }

    suspend fun refreshStreamPeriodically() {
        while (true) {
            delay(60_000)
            val updated = LiveService.stream(coordinate) ?: continue
            stream = updated
            if (updated.playbackURL != playbackURL) startPlayback()
        }
    }

    suspend fun runChat() {
        val stream = stream ?: return
        if (!chatLoaded) {
            merge(LiveService.chatHistory(stream))
            chatLoaded = true
        }
        if (!stream.isLive) return
        coroutineScope {
            launch { subscribe(stream) }
            launch { poll(stream) }
        }
    }

    private suspend fun subscribe(stream: LiveStream) = coroutineScope {
        var attempts = 0
        while (isActive) {
            try {
                LiveService.chatStream(stream).collect { message ->
                    attempts = 0
                    merge(listOf(message))
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
            }
            attempts += 1
            delay(minOf(30, 2 * attempts) * 1000L)
        }
    }

    private suspend fun poll(stream: LiveStream) {
        while (true) {
            delay(8_000)
            val since = (messages.lastOrNull()?.createdAt ?: TimeFormat.now) - 30
            merge(LiveService.chatSince(stream, since))
        }
    }

    private fun merge(incoming: List<LiveChatMessage>) {
        val muted = Session.mutedPubkeys.toSet()
        val fresh = incoming.filter { it.pubkey !in muted && seen.add(it.id) }
        if (fresh.isEmpty()) return
        messages = (messages + fresh).sortedWith(compareBy<LiveChatMessage> { it.createdAt }.thenBy { it.id }).takeLast(500)
        viewModelScope.launch { ProfileCache.load(fresh.map { it.pubkey }.distinct()) }
    }

    fun applyMutes() {
        val muted = Session.mutedPubkeys.toSet()
        val visible = messages.filter { it.pubkey !in muted }
        if (visible.size != messages.size) messages = visible
    }

    suspend fun refreshProfiles() {
        ProfileCache.load((messages.map { it.pubkey } + listOfNotNull(stream?.host)).distinct(), fetchMissing = false)
    }

    fun send() {
        val stream = stream ?: return
        if (!canSend) return
        isSending = true
        viewModelScope.launch {
            try {
                val message = LiveService.sendChat(draft, stream)
                draft = ""
                merge(listOf(message))
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                ToastCenter.error(error)
            } finally {
                isSending = false
            }
        }
    }

    fun zapHost() {
        val host = stream?.host ?: return
        Router.present(AppSheet.ZapProfile(host))
    }

    fun openHost() {
        val host = stream?.host ?: return
        Router.push(Route.Profile(host))
    }

    fun resume() {
        isPlaying = true
    }

    fun stop() {
        isPlaying = false
    }

    private fun startPlayback() {
        val current = stream
        val url = current?.playbackURL
        playbackURL = if (url != null && (current.isLive || current.canReplay)) url else null
    }
}
