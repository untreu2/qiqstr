package me.untreu.qiqstr.ui.dm

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.ProfileCache

enum class DMConversationFilter { PRIMARY, REQUESTS }

class DMConversationsViewModel : ViewModel() {
    var filter by mutableStateOf(DMConversationFilter.PRIMARY)
    var showNewMessage by mutableStateOf(false)
    var query by mutableStateOf("")
    private var didAutoSelect = false
    private val service = DMService

    val isInitialLoading: Boolean get() = !service.hasLoaded && service.conversations.isEmpty()
    val hasAnyConversation: Boolean get() = service.conversations.isNotEmpty()
    val hasUnread: Boolean get() = service.unreadCount > 0
    val hasLoaded: Boolean get() = service.hasLoaded

    private val trimmedQuery: String get() = query.trim().lowercase()

    val isSearching: Boolean get() = trimmedQuery.isNotEmpty()

    val searchedPubkey: String?
        get() {
            val hex = Nip19.pubkeyHex(query.trim()) ?: return null
            return if (hex == service.currentPubkey) null else hex
        }

    val visibleConversations: List<DMConversation>
        get() {
            if (!isSearching) return service.conversations.filter { matches(it, filter) }
            return service.conversations.filter(::matchesQuery)
        }

    private fun matchesQuery(conversation: DMConversation): Boolean {
        val q = trimmedQuery
        Nip19.pubkeyHex(q)?.let { return conversation.peer == it }
        if (q.startsWith("npub1") && Nip19.npub(conversation.peer)?.startsWith(q) == true) return true
        if (service.group(conversation.peer)?.displayName?.lowercase()?.contains(q) == true) return true
        if (conversation.lastMessage.content.lowercase().contains(q)) return true
        val profile = ProfileCache.profile(conversation.peer) ?: return conversation.peer.startsWith(q)
        return profile.name.lowercase().contains(q) || profile.displayName.lowercase().contains(q) || profile.nip05.lowercase().contains(q)
    }

    fun unreadCount(filter: DMConversationFilter): Int = service.conversations.count { it.isUnread && matches(it, filter) }

    fun title(filter: DMConversationFilter): String {
        val base = if (filter == DMConversationFilter.PRIMARY) L("dmTabPrimary") else L("dmTabRequests")
        val unread = unreadCount(filter)
        return if (unread > 0) "$base ($unread)" else base
    }

    private fun matches(conversation: DMConversation, filter: DMConversationFilter): Boolean {
        val known = service.isKnown(conversation.peer)
        return if (filter == DMConversationFilter.PRIMARY) known else !known
    }

    suspend fun appeared() {
        service.isListVisible = true
        service.start()
        autoSelectFilter()
    }

    fun autoSelectFilter() {
        if (didAutoSelect || !service.hasLoaded) return
        didAutoSelect = true
        if (filter == DMConversationFilter.PRIMARY && visibleConversations.isEmpty() && hasAnyConversation) filter = DMConversationFilter.REQUESTS
    }

    fun disappeared() {
        service.isListVisible = false
    }

    suspend fun refresh() {
        service.reloadFollowing()
        service.refresh()
    }

    suspend fun poll() {
        while (currentCoroutineContext().isActive) {
            delay(15_000)
            service.refresh()
        }
    }

    suspend fun reloadFollowing() = service.reloadFollowing()

    fun toggleRead(conversation: DMConversation) {
        if (conversation.isUnread) service.markRead(conversation.peer) else service.markUnread(conversation.peer)
    }

    fun canMarkUnread(conversation: DMConversation): Boolean = !conversation.isUnread && !conversation.lastMessage.isMine

    fun markAllRead() = service.markAllRead()

    fun copyNpub(pubkey: String) {
        val clipboard = App.context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("npub", Nip19.npub(pubkey) ?: pubkey))
        ToastCenter.show(L("copiedNpub"), ToastStyle.SUCCESS)
    }
}
