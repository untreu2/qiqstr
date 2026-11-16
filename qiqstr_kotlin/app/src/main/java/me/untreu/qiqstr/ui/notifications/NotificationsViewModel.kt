package me.untreu.qiqstr.ui.notifications

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.Repeat
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.qiqstr.core.dbGetHydratedNotifications
import com.qiqstr.core.dbGetHydratedNotificationsBefore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.data.services.MuteService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.services.WebOfTrustService
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.NotificationItem
import me.untreu.qiqstr.domain.NotificationKind
import me.untreu.qiqstr.ui.note.NoteInteractionStore
import me.untreu.qiqstr.ui.note.NoteRepository

enum class NotificationFilter(val raw: String) {
    ALL("all"), REPLIES("replies"), REACTIONS("reactions"), REPOSTS("reposts"), ZAPS("zaps");

    val title: String
        get() = when (this) {
            ALL -> L("notificationFilterAll")
            REPLIES -> L("notificationFilterReplies")
            REACTIONS -> L("reactions")
            REPOSTS -> L("reposts")
            ZAPS -> L("zaps")
        }

    val icon: ImageVector
        get() = when (this) {
            ALL -> Icons.Outlined.Inbox
            REPLIES -> Icons.Outlined.ChatBubbleOutline
            REACTIONS -> Icons.Outlined.FavoriteBorder
            REPOSTS -> Icons.Outlined.Repeat
            ZAPS -> Icons.Outlined.Bolt
        }

    fun includes(kind: NotificationKind): Boolean = when (this) {
        ALL -> true
        REPLIES -> kind == NotificationKind.REPLY || kind == NotificationKind.MENTION || kind == NotificationKind.QUOTE
        REACTIONS -> kind == NotificationKind.REACTION
        REPOSTS -> kind == NotificationKind.REPOST
        ZAPS -> kind == NotificationKind.ZAP
    }
}

@Immutable
data class NotificationGroup(
    val id: String,
    val kind: NotificationKind,
    val items: List<NotificationItem>,
    val authors: List<String>,
    val targetNoteId: String?,
    val createdAt: Long,
    val totalZapAmount: Long,
) {
    val lead: NotificationItem get() = items[0]
    val isGrouped: Boolean get() = items.size > 1

    val focusedNoteId: String?
        get() = when (kind) {
            NotificationKind.REPLY, NotificationKind.MENTION, NotificationKind.QUOTE -> lead.id.ifEmpty { null } ?: targetNoteId
            else -> targetNoteId ?: lead.id.ifEmpty { null }
        }
}

data class VisibleNotifications(val groups: List<NotificationGroup>, val hidden: Int)

class NotificationsViewModel : ViewModel() {
    var live by mutableStateOf<List<NotificationItem>>(emptyList())
        private set
    var older by mutableStateOf<List<NotificationItem>>(emptyList())
        private set
    var isLoaded by mutableStateOf(false)
        private set
    var isLoadingMore by mutableStateOf(false)
        private set
    var hasReachedEnd by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)
        private set
    var lastSeen by mutableLongStateOf(0L)
        private set
    var filter by mutableStateOf(NotificationFilter.ALL)
    var onlyTrusted by mutableStateOf(Prefs.bool(WebOfTrustService.FILTER_NOTIFICATIONS_KEY, true))
        private set
    var revealsHidden by mutableStateOf(false)
        private set

    private val olderIds = HashSet<String>()
    private var mutedThreadItems by mutableStateOf<Set<String>>(emptySet())
    private var didInitialSync = false
    private var seenMarked = false

    private val me: String? get() = Session.pubkey

    fun updateOnlyTrusted(value: Boolean) {
        Prefs.set(WebOfTrustService.FILTER_NOTIFICATIONS_KEY, value)
        if (value != onlyTrusted) revealsHidden = false
        onlyTrusted = value
    }

    val all: List<NotificationItem>
        get() {
            val liveIds = live.map { it.id }.toSet()
            val merged = live + older.filter { it.id !in liveIds }
            val hidden = NoteInteractionStore.deletedIds
            val me = me
            return merged
                .filter {
                    it.fromPubkey != me && it.kind != NotificationKind.UNKNOWN && it.id !in hidden && (it.targetNoteId ?: "") !in hidden &&
                        it.id !in mutedThreadItems
                }
                .sortedByDescending { it.createdAt }
        }

    val visible: VisibleNotifications
        get() {
            val items = all.filter { filter.includes(it.kind) }
            if (!onlyTrusted || revealsHidden || !WebOfTrustService.isReady) return VisibleNotifications(group(items), 0)
            val trusted = items.filter { WebOfTrustService.isTrusted(it.fromPubkey) }
            return VisibleNotifications(group(trusted), items.size - trusted.size)
        }

    fun revealHidden() {
        revealsHidden = true
    }

    fun isUnread(group: NotificationGroup): Boolean = lastSeen > 0 && group.createdAt > lastSeen

    fun markSeenOnce() {
        if (seenMarked) return
        seenMarked = true
        val me = me ?: return
        val key = "notif_last_seen_$me"
        lastSeen = Prefs.long(key)
        Prefs.set(key, TimeFormat.now)
    }

    suspend fun reload() {
        val me = me ?: return
        try {
            val raw = dbGetHydratedNotifications(me, LIVE_LIMIT, Session.mutedPubkeys, Session.mutedWords)
            if (me != this.me) return
            live = Json.array(raw).map(NotificationItem::from)
            errorMessage = null
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            if (!isLoaded) errorMessage = coreErrorMessage(error)
        }
        isLoaded = true
        applyMutedThreads()
        ProfileCache.load(all.map { it.fromPubkey }.distinct())
        if (!didInitialSync) {
            didInitialSync = true
            viewModelScope.launch { SyncService.syncNotifications() }
        }
    }

    suspend fun refresh() {
        SyncService.syncNotifications(force = true)
        reload()
    }

    suspend fun applyMutedThreads() {
        if (MuteService.mutedThreads.isEmpty()) {
            if (mutedThreadItems.isNotEmpty()) mutedThreadItems = emptySet()
            return
        }
        val items = live + older
        val ids = items.flatMap { listOf(it.id, it.targetNoteId ?: "") }.filter { it.length == 64 }.distinct()
        val roots = HashMap<String, String>()
        for (note in NoteRepository.notes(ids)) if (!roots.containsKey(note.id)) roots[note.id] = note.rootId ?: note.id
        mutedThreadItems = items.filter { item ->
            listOf(item.id, item.targetNoteId ?: "").any { id -> MuteService.isThreadMuted(id) || roots[id]?.let(MuteService::isThreadMuted) == true }
        }.map { it.id }.toSet()
    }

    suspend fun loadMoreIfNeeded(group: NotificationGroup) {
        if (visible.groups.lastOrNull()?.id != group.id) return
        loadMore()
    }

    suspend fun loadMore() {
        val me = me ?: return
        if (!isLoaded || isLoadingMore || hasReachedEnd) return
        val oldest = all.lastOrNull()?.createdAt ?: return
        if (oldest <= 0) return
        isLoadingMore = true
        try {
            var added = appendOlder(oldest)
            var remoteCount = 0
            if (!added) {
                remoteCount = SyncService.syncOlderNotifications(oldest)
                if (me != this.me) return
                added = appendOlder(oldest)
            }
            if (!added && remoteCount == 0) hasReachedEnd = true
        } finally {
            isLoadingMore = false
        }
    }

    private suspend fun appendOlder(before: Long): Boolean {
        val me = me ?: return false
        val raw = runCatching {
            dbGetHydratedNotificationsBefore(me, before.toULong(), PAGE_SIZE, Session.mutedPubkeys, Session.mutedWords)
        }.getOrNull()
        if (me != this.me) return false
        val fresh = Json.array(raw).map(NotificationItem::from).filter { it.id.isNotEmpty() && olderIds.add(it.id) }
        if (fresh.isEmpty()) return false
        older = older + fresh
        ProfileCache.load(older.map { it.fromPubkey }.distinct())
        return true
    }

    fun mute(pubkey: String) {
        viewModelScope.launch {
            runCatching { MuteService.mute(pubkey) }
                .onSuccess { ToastCenter.show(L("userMuted"), ToastStyle.SUCCESS) }
                .onFailure(ToastCenter::error)
        }
    }

    companion object {
        private val LIVE_LIMIT = 200u
        private val PAGE_SIZE = 100u
        private val groupable = setOf(NotificationKind.REACTION, NotificationKind.REPOST, NotificationKind.ZAP)

        fun group(items: List<NotificationItem>): List<NotificationGroup> {
            val order = mutableListOf<Pair<String, Int>>()
            val buckets = LinkedHashMap<String, MutableList<NotificationItem>>()
            val singles = mutableListOf<Pair<NotificationItem, Int>>()
            items.forEachIndexed { i, item ->
                val target = item.targetNoteId
                if (item.kind in groupable && !target.isNullOrEmpty()) {
                    val key = "${item.kind.raw}:$target"
                    if (!buckets.containsKey(key)) order.add(key to i)
                    buckets.getOrPut(key) { mutableListOf() }.add(item)
                } else {
                    singles.add(item to i)
                }
            }
            val result = singles.map { make(listOf(it.first), it.first.id) to it.second }.toMutableList()
            for ((key, index) in order) {
                val bucket = (buckets[key] ?: mutableListOf()).sortedByDescending { it.createdAt }
                result.add(make(bucket, key) to index)
            }
            return result.sortedBy { it.second }.map { it.first }
        }

        private fun make(items: List<NotificationItem>, id: String): NotificationGroup {
            val seen = HashSet<String>()
            val authors = items.map { it.fromPubkey }.filter { it.isNotEmpty() && seen.add(it) }
            var total = 0L
            for (item in items) total = if (Long.MAX_VALUE - total < item.zapAmount) Long.MAX_VALUE else total + item.zapAmount
            return NotificationGroup(id, items[0].kind, items, authors, items[0].targetNoteId, items[0].createdAt, total)
        }
    }
}
