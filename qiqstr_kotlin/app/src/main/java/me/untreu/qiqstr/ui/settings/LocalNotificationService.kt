package me.untreu.qiqstr.ui.settings

import android.Manifest
import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ProcessLifecycleOwner
import com.qiqstr.core.dbGetEvent
import com.qiqstr.core.dbSaveEvents
import com.qiqstr.core.zapReceiptSummary
import java.text.NumberFormat
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.MainActivity
import me.untreu.qiqstr.R
import me.untreu.qiqstr.app.AppTab
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppLanguage
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.services.MuteService
import me.untreu.qiqstr.data.services.WebOfTrustService
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.NotificationBadge
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.RealtimeNotificationHandler
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SessionPhase
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.dm.DMMessage
import me.untreu.qiqstr.ui.dm.DMService
import me.untreu.qiqstr.ui.note.NoteInteractionStore
import org.json.JSONArray
import org.json.JSONObject

enum class LocalNotificationType(val raw: String) {
    REPLIES("replies"), REACTIONS("reactions"), REPOSTS("reposts"), ZAPS("zaps"), MESSAGES("messages");

    val key: String get() = "local_notifications_$raw"
    val isEnabled: Boolean get() = Prefs.bool(key, true)
}

data class NotificationPayload(val destination: Destination, val account: String?) {
    sealed interface Destination {
        data class Thread(val id: String) : Destination
        data class Chat(val pubkey: String?) : Destination
        object Notifications : Destination
    }

    val uri: Uri
        get() {
            val builder = Uri.Builder().scheme(SCHEME).authority("open")
            account?.let { builder.appendQueryParameter("account", it) }
            when (destination) {
                is Destination.Thread -> builder.appendQueryParameter("route", "thread").appendQueryParameter("id", destination.id)
                is Destination.Chat -> {
                    builder.appendQueryParameter("route", "chat")
                    destination.pubkey?.let { builder.appendQueryParameter("id", it) }
                }
                Destination.Notifications -> builder.appendQueryParameter("route", "notifications")
            }
            return builder.build()
        }

    companion object {
        const val SCHEME = "qiqstr-notification"

        fun from(uri: Uri): NotificationPayload? {
            if (uri.scheme != SCHEME) return null
            val id = uri.getQueryParameter("id")
            val destination = when (uri.getQueryParameter("route")) {
                "thread" -> id?.let { Destination.Thread(it) } ?: Destination.Notifications
                "chat" -> Destination.Chat(id)
                else -> Destination.Notifications
            }
            return NotificationPayload(destination, uri.getQueryParameter("account"))
        }
    }
}

private class ActivityItem(
    val id: String,
    val kind: Kind,
    val actor: String,
    val target: String?,
    val root: String?,
    val content: String,
    val createdAt: Long,
    val sats: Long,
) {
    enum class Kind { REPLY, MENTION, REACTION, REPOST, ZAP }

    val type: LocalNotificationType
        get() = when (kind) {
            Kind.REPLY, Kind.MENTION -> LocalNotificationType.REPLIES
            Kind.REACTION -> LocalNotificationType.REACTIONS
            Kind.REPOST -> LocalNotificationType.REPOSTS
            Kind.ZAP -> LocalNotificationType.ZAPS
        }

    val isTextual: Boolean get() = kind == Kind.REPLY || kind == Kind.MENTION

    companion object {
        fun from(event: JSONObject, me: String): ActivityItem? {
            val id = event.str("id") ?: return null
            val tags = event.tags()
            val eventTags = tags.filter { it.size > 1 && it[0] == "e" }
            var content = event.text("content")
            var actor = event.str("pubkey") ?: ""
            var sats = 0L
            val kind: Kind
            val target: String?
            var root: String? = null
            when (event.int("kind")) {
                1 -> {
                    val threadTags = eventTags.filter { it.size < 4 || it[3] != "mention" }
                    kind = if (threadTags.isEmpty()) Kind.MENTION else Kind.REPLY
                    target = (threadTags.firstOrNull { it.size > 3 && it[3] == "root" } ?: threadTags.firstOrNull())?.get(1)
                    root = target ?: id
                }
                6 -> {
                    kind = Kind.REPOST
                    target = eventTags.firstOrNull()?.get(1)
                }
                7 -> {
                    kind = Kind.REACTION
                    target = eventTags.lastOrNull()?.get(1)
                    if (content.trim() == "-") return null
                }
                9735 -> {
                    kind = Kind.ZAP
                    target = eventTags.firstOrNull()?.get(1)
                    val summary = Json.obj(runCatching { zapReceiptSummary(event.toString()) }.getOrNull()) ?: return null
                    val sender = summary.str("sender") ?: return null
                    if (summary.long("amount") <= 0) return null
                    actor = sender
                    content = summary.text("comment")
                    sats = summary.long("amount")
                }
                else -> return null
            }
            if (actor.isEmpty() || actor == me) return null
            return ActivityItem(id, kind, actor, target, root, content, event.long("created_at"), sats)
        }
    }
}

object LocalNotificationService : RealtimeNotificationHandler {
    const val ENABLED_KEY = "local_notifications_enabled"
    const val PROMPTED_KEY = "local_notifications_prompted"
    private const val BADGE_KEY = "local_notifications_badge"
    private const val MESSAGES_GROUP = "messages"
    private const val ACTIVITY_CHANNEL = "activity"
    private const val MESSAGES_CHANNEL = "messages"
    private const val SEEN_LIMIT = 1500
    private const val OVERLAP = 120L
    private const val HANDLED_EXTRA = "qiqstr_notification_handled"

    var isEnabled by mutableStateOf(Prefs.bool(ENABLED_KEY))
        private set
    var isAuthorized by mutableStateOf(false)
        private set
    var isDenied by mutableStateOf(false)
        private set
    var backgroundRefreshAvailable by mutableStateOf(true)
        private set

    private var pending: NotificationPayload? = null
    private val seen = HashMap<String, MutableSet<String>>()
    private val seenOrder = HashMap<String, MutableList<String>>()
    private val groups = HashMap<String, MutableList<String>>()
    private var activated = false
    private var lastHandled: Pair<Uri, Long>? = null

    val isDelivering: Boolean get() = isEnabled && isAuthorized
    val shouldOfferPrompt: Boolean get() = !isEnabled && !isDenied && !Prefs.bool(PROMPTED_KEY)

    private val context: Context get() = App.context
    private val manager: NotificationManagerCompat get() = NotificationManagerCompat.from(context)

    private val isInBackground: Boolean
        get() = !ProcessLifecycleOwner.get().lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)

    fun updateEnabled(value: Boolean) {
        isEnabled = value
        Prefs.set(ENABLED_KEY, value)
        if (value) BackgroundRefresh.schedule() else BackgroundRefresh.cancel()
    }

    fun activate() {
        if (activated) return
        activated = true
        ensureChannels()
        refreshStatus()
        if (isEnabled) BackgroundRefresh.schedule()
    }

    fun refreshStatus() {
        val granted = Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        isAuthorized = granted && manager.areNotificationsEnabled()
        isDenied = !isAuthorized && Prefs.bool(PROMPTED_KEY)
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        backgroundRefreshAvailable = Build.VERSION.SDK_INT < Build.VERSION_CODES.P || !activityManager.isBackgroundRestricted
        if (isEnabled && isDenied) BackgroundRefresh.cancel()
    }

    val needsPermissionRequest: Boolean
        get() = Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED

    fun completeEnable(granted: Boolean): Boolean {
        Prefs.set(PROMPTED_KEY, true)
        refreshStatus()
        val allowed = granted && isAuthorized
        updateEnabled(allowed)
        if (allowed) Session.pubkey?.let { setLastCheck(it, TimeFormat.now) }
        return allowed
    }

    fun dismissPrompt() = Prefs.set(PROMPTED_KEY, true)

    suspend fun sessionReady() {
        refreshStatus()
        if (storedBadge > 0) NotificationBadge.markUnread()
        openPending()
    }

    fun enteredBackground() {
        val me = Session.pubkey ?: return
        if (!isEnabled) return
        setLastCheck(me, TimeFormat.now)
        persistSeen(me)
        BackgroundRefresh.schedule()
    }

    fun clearBadge() {
        groups.clear()
        Prefs.set(BADGE_KEY, 0L)
        activeNotifications().filter { it.notification.group != MESSAGES_GROUP }.forEach { manager.cancel(it.tag, it.id) }
    }

    fun clearMessages() {
        activeNotifications().filter { it.notification.group == MESSAGES_GROUP }.forEach { manager.cancel(it.tag, it.id) }
    }

    private fun activeNotifications() = runCatching {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).activeNotifications.toList()
    }.getOrDefault(emptyList())

    override fun shouldBadge(event: JSONObject, me: String): Boolean {
        val item = ActivityItem.from(event, me) ?: return false
        if (item.actor == me || !accepts(item.actor, mutedPubkeys)) return false
        if (MuteService.hidesNotification(item.target, item.root)) return false
        if (NoteInteractionStore.isDeleted(item.id) || item.target?.let(NoteInteractionStore::isDeleted) == true) return false
        if (!item.isTextual) return true
        val text = item.content.lowercase()
        return mutedWords.none { text.contains(it) }
    }

    override fun handleRealtime(event: JSONObject, me: String) {
        val id = event.str("id") ?: return
        val last = lastCheck(me)
        if (!isEnabled || !isInBackground || last == null) {
            insertSeen(id, me)
            return
        }
        App.scope.launch { deliver(listOf(event), me, last - OVERLAP) }
    }

    suspend fun checkForNewActivity(me: String) {
        if (!isEnabled) return
        val now = TimeFormat.now
        val last = lastCheck(me)
        if (last == null) {
            setLastCheck(me, now)
            return
        }
        val wantsActivity = LocalNotificationType.entries.any { it != LocalNotificationType.MESSAGES && it.isEnabled }
        val (events, incoming) = coroutineScope {
            val activity = async { if (wantsActivity) fetchActivity(me, last - OVERLAP) else emptyList() }
            val messages = async { fetchMessages(me, last) }
            val mutes = async { ensureMutesLoaded() }
            val trust = async { WebOfTrustService.load(me) }
            mutes.await()
            trust.await()
            activity.await() to messages.await()
        }
        if (Session.pubkey != me) return
        setLastCheck(me, now)
        deliver(events, me, last - OVERLAP)
        deliverMessages(incoming, me, last)
        persistSeen(me)
    }

    private suspend fun fetchActivity(me: String, since: Long): List<JSONObject> {
        val events = SyncService.fetchEvents(mapOf("kinds" to listOf(1, 6, 7, 9735), "#p" to listOf(me), "since" to since, "limit" to 200), timeout = 8)
        if (events.isNotEmpty()) {
            runCatching { dbSaveEvents(JSONArray(events).toString()) }
            DataBus.notificationsChanged()
        }
        return events
    }

    private suspend fun fetchMessages(me: String, since: Long): List<DMMessage> {
        if (!LocalNotificationType.MESSAGES.isEnabled || !Session.canSign || Session.pubkey != me) return emptyList()
        return runCatching { DMService.incomingMessages(since) }.getOrDefault(emptyList())
    }

    private suspend fun ensureMutesLoaded() {
        if (Session.mutedPubkeys.isNotEmpty() || MuteService.isLoaded) return
        MuteService.load()
    }

    private val mutedPubkeys: Set<String> get() = Session.mutedPubkeys.toSet() + MuteService.mutedPubkeys

    private val mutedWords: List<String>
        get() = (Session.mutedWords.toSet() + MuteService.mutedWords).map { it.lowercase() }.filter { it.isNotEmpty() }

    private fun accepts(pubkey: String, muted: Set<String>): Boolean {
        if (pubkey in muted) return false
        return !WebOfTrustService.filtersNotifications || WebOfTrustService.isTrusted(pubkey)
    }

    private suspend fun deliver(events: List<JSONObject>, me: String, since: Long) {
        val muted = mutedPubkeys
        val words = mutedWords
        val items = events.mapNotNull { ActivityItem.from(it, me) }
            .filter { item ->
                if (item.createdAt <= since || !item.type.isEnabled || !accepts(item.actor, muted)) return@filter false
                if (MuteService.hidesNotification(item.target, item.root)) return@filter false
                if (item.isTextual) {
                    val text = item.content.lowercase()
                    if (words.any { text.contains(it) }) return@filter false
                }
                insertSeen(item.id, me)
            }
            .sortedBy { it.createdAt }
        if (items.isEmpty() || Session.pubkey != me) return

        val names = displayNames(items.map { it.actor }.distinct())
        val targets = noteSnippets(items.filter { !it.isTextual }.mapNotNull { it.target }.distinct())

        for (item in items) {
            when (item.kind) {
                ActivityItem.Kind.REPLY, ActivityItem.Kind.MENTION -> {
                    val name = names[item.actor] ?: Profile.shortNpub(item.actor)
                    val title = if (item.kind == ActivityItem.Kind.REPLY) L("localNotifyReplied", "name" to name) else L("localNotifyMentioned", "name" to name)
                    post("activity-${item.id}", title, snippet(item.content), "thread-${item.target ?: item.id}", NotificationPayload(NotificationPayload.Destination.Thread(item.id), me))
                }
                ActivityItem.Kind.REACTION, ActivityItem.Kind.REPOST -> {
                    val target = item.target ?: continue
                    val key = "${if (item.kind == ActivityItem.Kind.REACTION) "reactions" else "reposts"}-$target"
                    val actors = groups.getOrPut(key) { mutableListOf() }
                    actors.remove(item.actor)
                    actors.add(0, item.actor)
                    val title = groupTitle(item, actors, names)
                    post(key, title, targets[target] ?: "", "thread-$target", NotificationPayload(NotificationPayload.Destination.Thread(target), me), silent = actors.size > 1)
                }
                ActivityItem.Kind.ZAP -> {
                    val name = names[item.actor] ?: Profile.shortNpub(item.actor)
                    val title = if (item.sats > 0) {
                        L("localNotifyZap", "amount" to NumberFormat.getIntegerInstance(AppLanguage.locale).format(item.sats), "count" to item.sats, "name" to name)
                    } else {
                        L("localNotifyZapNoAmount", "name" to name)
                    }
                    val comment = snippet(item.content)
                    val body = comment.ifEmpty { item.target?.let { targets[it] } ?: "" }
                    post("zap-${item.id}", title, body, "zaps", NotificationPayload(NotificationPayload.Destination.Notifications, me))
                }
            }
        }
        Prefs.set(BADGE_KEY, storedBadge + items.size)
        NotificationBadge.markUnread()
    }

    private suspend fun deliverMessages(messages: List<DMMessage>, me: String, since: Long) {
        if (messages.isEmpty()) return
        val muted = mutedPubkeys
        val incoming = messages.filter { !it.isMine && it.createdAt > since && accepts(it.sender, muted) && insertSeen("dm-${it.id}", me) }
        if (incoming.isEmpty() || Session.pubkey != me) return
        val bySender = incoming.groupBy { it.sender }
        val names = displayNames(bySender.keys.toList())
        for ((sender, list) in bySender) {
            val name = names[sender] ?: Profile.shortNpub(sender)
            val body = if (list.size == 1) L("localNotifyNewMessage") else L("localNotifyNewMessages", "count" to list.size)
            post("chat-$sender", name, body, MESSAGES_GROUP, NotificationPayload(NotificationPayload.Destination.Chat(sender), me))
        }
        NotificationBadge.hasUnreadMessages = true
    }

    private fun groupTitle(item: ActivityItem, actors: List<String>, names: Map<String, String>): String {
        val first = names[actors[0]] ?: Profile.shortNpub(actors[0])
        val isReaction = item.kind == ActivityItem.Kind.REACTION
        return when (actors.size) {
            1 -> {
                val reaction = item.content.trim()
                if (isReaction && reaction.isNotEmpty() && reaction != "+" && !reaction.contains(":")) {
                    L("localNotifyReacted", "name" to first, "reaction" to reaction)
                } else {
                    L(if (isReaction) "localNotifyLikedOne" else "localNotifyRepostedOne", "name" to first)
                }
            }
            2 -> {
                val other = names[actors[1]] ?: Profile.shortNpub(actors[1])
                L(if (isReaction) "localNotifyLikedTwo" else "localNotifyRepostedTwo", "name" to first, "other" to other)
            }
            else -> L(if (isReaction) "localNotifyLikedMany" else "localNotifyRepostedMany", "count" to actors.size)
        }
    }

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val system = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        system.createNotificationChannel(NotificationChannel(ACTIVITY_CHANNEL, L("notifications"), NotificationManager.IMPORTANCE_DEFAULT))
        system.createNotificationChannel(NotificationChannel(MESSAGES_CHANNEL, L("messages"), NotificationManager.IMPORTANCE_HIGH))
    }

    private fun post(id: String, title: String, body: String, thread: String, payload: NotificationPayload, silent: Boolean = false) {
        if (!isAuthorized && !manager.areNotificationsEnabled()) return
        ensureChannels()
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = payload.uri
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pendingIntent = PendingIntent.getActivity(context, id.hashCode(), intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val isMessage = thread == MESSAGES_GROUP
        val notification = NotificationCompat.Builder(context, if (isMessage) MESSAGES_CHANNEL else ACTIVITY_CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setContentText(body.ifEmpty { null })
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setGroup(thread)
            .setAutoCancel(true)
            .setSilent(silent)
            .setOnlyAlertOnce(silent)
            .setCategory(if (isMessage) NotificationCompat.CATEGORY_MESSAGE else NotificationCompat.CATEGORY_SOCIAL)
            .setPriority(if (isMessage) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_DEFAULT)
            .setNumber(if (isMessage) 0 else storedBadge.toInt() + 1)
            .setContentIntent(pendingIntent)
            .build()
        runCatching { manager.notify(id, id.hashCode(), notification) }
    }

    private suspend fun displayNames(pubkeys: List<String>): Map<String, String> {
        ProfileCache.load(pubkeys, fetchMissing = false)
        val names = HashMap<String, String>()
        for (pubkey in pubkeys) ProfileCache.profile(pubkey)?.let { names[pubkey] = it.bestName }
        val missing = pubkeys.filter { it !in names }
        if (missing.isEmpty()) return names
        val metadata = SyncService.fetchEvents(mapOf("kinds" to listOf(0), "authors" to missing, "limit" to missing.size * 2), timeout = 5)
        if (metadata.isNotEmpty()) runCatching { dbSaveEvents(JSONArray(metadata).toString()) }
        for (event in metadata.sortedBy { it.long("created_at") }) {
            val pubkey = event.str("pubkey") ?: continue
            val json = Json.obj(event.str("content")) ?: continue
            names[pubkey] = Profile.from(json, pubkey).bestName
        }
        return names
    }

    private suspend fun noteSnippets(ids: List<String>): Map<String, String> {
        val snippets = HashMap<String, String>()
        for (id in ids) {
            val event = Json.obj(runCatching { dbGetEvent(id) }.getOrNull()) ?: continue
            snippets[id] = snippet(event.text("content"))
        }
        val missing = ids.filter { it !in snippets }
        if (missing.isEmpty()) return snippets
        for (event in SyncService.fetchEvents(mapOf("ids" to missing, "limit" to missing.size), timeout = 4)) {
            val id = event.str("id") ?: continue
            snippets[id] = snippet(event.text("content"))
        }
        return snippets
    }

    private val nostrEntity = Regex("nostr:[a-z0-9]+")
    private val mediaUrl = Regex("""https?://\S+\.(jpe?g|png|gif|webp|heic|mp4|mov|webm)(\?\S*)?""", RegexOption.IGNORE_CASE)
    private val whitespace = Regex("\\s+")

    private fun snippet(text: String): String {
        val cleaned = text.replace(nostrEntity, "").replace(mediaUrl, "").replace(whitespace, " ").trim()
        return if (cleaned.length > 240) cleaned.take(239) + "…" else cleaned
    }

    private val storedBadge: Long get() = Prefs.long(BADGE_KEY)

    private fun lastCheckKey(me: String) = "local_notifications_last_$me"
    private fun seenKey(me: String) = "local_notifications_seen_$me"

    private fun lastCheck(me: String): Long? = if (Prefs.contains(lastCheckKey(me))) Prefs.long(lastCheckKey(me)) else null

    private fun setLastCheck(me: String, value: Long) = Prefs.set(lastCheckKey(me), maxOf(value, lastCheck(me) ?: 0))

    private fun loadSeen(me: String) {
        if (seen.containsKey(me)) return
        val stored = Prefs.stringList(seenKey(me)).orEmpty()
        seenOrder[me] = stored.toMutableList()
        seen[me] = stored.toMutableSet()
    }

    private fun insertSeen(id: String, me: String): Boolean = synchronized(seen) {
        loadSeen(me)
        val set = seen.getValue(me)
        if (!set.add(id)) return false
        val order = seenOrder.getValue(me)
        order.add(id)
        if (order.size > SEEN_LIMIT) {
            val dropped = order.subList(0, order.size - SEEN_LIMIT)
            set.removeAll(dropped.toSet())
            dropped.clear()
        }
        true
    }

    private fun persistSeen(me: String) {
        val order = synchronized(seen) { seenOrder[me]?.toList() } ?: return
        Prefs.setStringList(seenKey(me), order)
    }

    fun handleLaunch(intent: Intent?) {
        val uri = intent?.data ?: return
        if (intent.getBooleanExtra(HANDLED_EXTRA, false) || NotificationPayload.from(uri) == null) return
        intent.putExtra(HANDLED_EXTRA, true)
        handle(uri)
    }

    fun handle(uri: Uri): Boolean {
        val payload = NotificationPayload.from(uri) ?: return false
        val now = System.currentTimeMillis()
        val last = lastHandled
        if (last != null && last.first == uri && now - last.second < 10_000) return true
        lastHandled = uri to now
        App.scope.launch { open(payload) }
        return true
    }

    suspend fun open(payload: NotificationPayload) {
        pending = payload
        openPending()
    }

    private suspend fun openPending() {
        val payload = pending ?: return
        if (Session.phase != SessionPhase.Ready) return
        pending = null
        val account = payload.account
        if (account != null && account != Session.pubkey) {
            val stored = Session.accounts.firstOrNull { it.pubkeyHex == account } ?: return
            runCatching { Session.switchAccount(stored.npub) }
            if (Session.phase != SessionPhase.Ready || Session.pubkey != account) return
        }
        Router.sheet = null
        Router.showSidebar = false
        when (val destination = payload.destination) {
            is NotificationPayload.Destination.Thread -> {
                Router.selectedTab = AppTab.NOTIFICATIONS
                Router.popToRoot(AppTab.NOTIFICATIONS)
                Router.push(Route.Thread(destination.id))
            }
            is NotificationPayload.Destination.Chat -> {
                Router.selectedTab = AppTab.DM
                Router.popToRoot(AppTab.DM)
                destination.pubkey?.let { Router.push(Route.DMChat(it)) }
            }
            NotificationPayload.Destination.Notifications -> {
                Router.selectedTab = AppTab.NOTIFICATIONS
                Router.popToRoot(AppTab.NOTIFICATIONS)
            }
        }
    }
}
