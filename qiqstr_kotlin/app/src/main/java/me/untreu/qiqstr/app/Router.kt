package me.untreu.qiqstr.app

import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.lifecycle.ViewModelStore
import java.util.concurrent.atomic.AtomicLong
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.NostrLink
import me.untreu.qiqstr.data.services.ReadOnlyGate
import me.untreu.qiqstr.data.sync.NotificationBadge
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SessionPhase
import me.untreu.qiqstr.domain.Note

enum class FollowListMode { FOLLOWING, FOLLOWERS }

enum class SettingsRoute { KEYS, RELAYS, MUTED, DISPLAY, DATABASE, EVENT_MANAGER, PAYMENTS, LANGUAGE, NOTIFICATIONS, SAFETY, DIAGNOSTICS, MEDIA_SERVER, EMOJI_PACKS, NUTZAPS }

sealed interface Route {
    val key: String

    data class Profile(val pubkey: String) : Route { override val key get() = "profile/$pubkey" }
    data class Thread(val noteId: String) : Route { override val key get() = "thread/$noteId" }
    data class Quotes(val noteId: String) : Route { override val key get() = "quotes/$noteId" }
    data class NoteStatistics(val noteId: String) : Route { override val key get() = "stats/$noteId" }
    data class FollowList(val pubkey: String, val mode: FollowListMode) : Route { override val key get() = "follows/$pubkey/$mode" }
    data class Hashtag(val tag: String) : Route { override val key get() = "hashtag/$tag" }
    object Reads : Route { override val key get() = "reads" }
    data class Article(val articleId: String) : Route { override val key get() = "article/$articleId" }
    data class ArticleAddress(val naddr: String) : Route { override val key get() = "naddr/$naddr" }
    object EditProfile : Route { override val key get() = "editProfile" }
    object Settings : Route { override val key get() = "settings" }
    data class SettingsPage(val page: SettingsRoute) : Route { override val key get() = "settings/$page" }
    object Bookmarks : Route { override val key get() = "bookmarks" }
    object FollowSets : Route { override val key get() = "followSets" }
    data class FollowSet(val setId: String) : Route { override val key get() = "followSet/$setId" }
    data class DMChat(val pubkey: String) : Route { override val key get() = "dm/$pubkey" }
    object WalletReceive : Route { override val key get() = "walletReceive" }
    object UserSearch : Route { override val key get() = "userSearch" }
    object SuggestedFollows : Route { override val key get() = "suggestedFollows" }
    object LiveStreams : Route { override val key get() = "liveStreams" }
    data class LiveStream(val coordinate: String) : Route { override val key get() = "live/$coordinate" }
    object DiscoverFeeds : Route { override val key get() = "discoverFeeds" }
    data class DiscoverFeed(val feedId: String) : Route { override val key get() = "discoverFeed/$feedId" }
    data class FollowPack(val packId: String) : Route { override val key get() = "followPack/$packId" }
}

enum class AppTab { FEED, DM, WALLET, NOTIFICATIONS, SEARCH }

sealed interface AppSheet {
    val requiresSigner: Boolean get() = false

    data class Zap(val note: Note) : AppSheet { override val requiresSigner get() = true }
    data class ZapProfile(val pubkey: String) : AppSheet { override val requiresSigner get() = true }
    object SwitchAccount : AppSheet
    data class ShareProfile(val pubkey: String) : AppSheet
}

sealed interface ComposeContext {
    object NewNote : ComposeContext
    data class Reply(val note: Note) : ComposeContext
    data class Quote(val note: Note) : ComposeContext
}

class RouteEntry(val route: Route) {
    val id: Long = counter.incrementAndGet()
    val viewModelStore = ViewModelStore()

    companion object {
        private val counter = AtomicLong()
    }
}

object Router {
    var selectedTab by mutableStateOf(AppTab.FEED)
    val stacks: Map<AppTab, SnapshotStateList<RouteEntry>> = AppTab.entries.associateWith { mutableStateListOf() }
    var isComposing by mutableStateOf(false)
    var composeContext by mutableStateOf<ComposeContext?>(null)
    var showSidebar by mutableStateOf(false)
    var sheet by mutableStateOf<AppSheet?>(null)
    private var pendingLink: NostrLink? = null
    private var pendingAppUri: Uri? = null
    var externalHandlers = mutableListOf<(Uri) -> Boolean>()

    fun stack(tab: AppTab = selectedTab): SnapshotStateList<RouteEntry> = stacks.getValue(tab)

    fun push(route: Route) {
        stack().add(RouteEntry(route))
    }

    fun pop(): Boolean {
        val stack = stack()
        if (stack.isEmpty()) return false
        stack.removeAt(stack.lastIndex).viewModelStore.clear()
        return true
    }

    fun popToRoot(tab: AppTab) {
        val stack = stack(tab)
        stack.forEach { it.viewModelStore.clear() }
        stack.clear()
    }

    val reselects = mutableStateMapOf<AppTab, Int>()

    fun select(tab: AppTab) {
        if (tab == selectedTab) {
            if (stack(tab).isEmpty()) reselects[tab] = (reselects[tab] ?: 0) + 1
            popToRoot(tab)
        }
        selectedTab = tab
        if (tab == AppTab.NOTIFICATIONS) NotificationBadge.markRead()
    }

    fun compose(context: ComposeContext = ComposeContext.NewNote) {
        if (!ReadOnlyGate.check()) return
        composeContext = context
        isComposing = true
    }

    fun present(newSheet: AppSheet) {
        if (newSheet.requiresSigner && !Session.canSign) {
            ReadOnlyGate.present()
            return
        }
        sheet = newSheet
    }

    fun reset() {
        AppTab.entries.forEach(::popToRoot)
        selectedTab = AppTab.FEED
        isComposing = false
        showSidebar = false
        sheet = null
    }

    fun openUrl(url: String) {
        val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return
        open(uri)
    }

    fun open(uri: Uri) {
        val scheme = uri.scheme?.lowercase()
        if (scheme == "qiqstr" && uri.host?.lowercase() != "nwc") {
            openAppUri(uri)
            return
        }
        val link = NostrLink.fromUri(uri) ?: NostrLink.fromEntity(uri.toString())
        when {
            link != null -> open(link)
            externalHandlers.any { it(uri) } -> Unit
            scheme == "http" || scheme == "https" -> browse(uri)
            scheme != null && scheme !in setOf("nostr", "qiqstr", "lightning", "nostr+walletconnect", "nostrwalletconnect") -> {
                runCatching {
                    App.context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            }
        }
    }

    fun browse(uri: Uri) {
        runCatching {
            val intent = CustomTabsIntent.Builder().setShowTitle(true).build()
            intent.intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            intent.launchUrl(App.context, uri)
        }.onFailure {
            runCatching { App.context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        }
    }

    fun open(link: NostrLink) {
        if (Session.phase != SessionPhase.Ready) {
            pendingLink = link
            return
        }
        NostrLinkResolver.open(link)
    }

    fun openPendingLink() {
        if (Session.phase != SessionPhase.Ready) return
        pendingAppUri?.let { pendingAppUri = null; openAppUri(it) }
        val link = pendingLink ?: return
        pendingLink = null
        NostrLinkResolver.open(link)
    }

    private fun openAppUri(uri: Uri) {
        if (Session.phase != SessionPhase.Ready) {
            pendingAppUri = uri
            return
        }
        when (uri.host?.lowercase()) {
            "compose" -> compose()
            "search" -> selectedTab = AppTab.SEARCH
            "messages" -> selectedTab = AppTab.DM
            "notifications" -> {
                selectedTab = AppTab.NOTIFICATIONS
                NotificationBadge.markRead()
            }
        }
    }
}
