package me.untreu.qiqstr.data.sync

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.qiqstr.core.sessionPublicKey
import com.qiqstr.core.addRelayWithFlags
import com.qiqstr.core.connectRelays
import com.qiqstr.core.dbGetProfile
import com.qiqstr.core.dbGetProfiles
import com.qiqstr.core.dbWipeDirectory
import com.qiqstr.core.discoverAndConnectOutboxRelays
import com.qiqstr.core.initClient
import com.qiqstr.core.shutdownClient
import com.qiqstr.core.waitForReady
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.BuildConfig
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.SecureStore
import me.untreu.qiqstr.core.bool
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.data.accounts.AccountData
import me.untreu.qiqstr.data.accounts.AccountStore
import me.untreu.qiqstr.data.accounts.AuthError
import me.untreu.qiqstr.data.accounts.Nip05Resolver
import me.untreu.qiqstr.data.accounts.Account
import me.untreu.qiqstr.data.services.ReadOnlyError
import me.untreu.qiqstr.data.services.ReadOnlyGate
import me.untreu.qiqstr.data.services.RelayConfig
import me.untreu.qiqstr.domain.Profile
import org.json.JSONObject

sealed interface SessionPhase {
    object Launching : SessionPhase
    object SignedOut : SessionPhase
    object Starting : SessionPhase
    object Ready : SessionPhase
    data class Failed(val message: String) : SessionPhase
}

object Session {
    var phase by mutableStateOf<SessionPhase>(SessionPhase.Launching)
        private set
    var account by mutableStateOf<Account?>(null)
        private set
    var accounts by mutableStateOf<List<Account>>(emptyList())
        private set
    var generation by mutableIntStateOf(0)
        private set
    var mutedPubkeys by mutableStateOf<List<String>>(emptyList())
    var mutedWords by mutableStateOf<List<String>>(emptyList())
    var isNewAccount = false

    val pubkey: String? get() = account?.pubkeyHex
    val npub: String? get() = account?.npub
    val isReadOnly: Boolean get() = account?.isReadOnly ?: false
    val canSign: Boolean
        get() {
            val current = account ?: return false
            if (current.isReadOnly) return false
            return runCatching { sessionPublicKey() }.getOrNull() == current.pubkeyHex
        }

    fun revealSigningKey(): String? = account?.let { AccountStore.storedSigningKey(it.npub) }

    fun revealMnemonic(): String? = account?.let { AccountStore.storedMnemonic(it.npub) }

    var debugLogin: String? = null

    suspend fun launch() {
        ServiceRegistry.register()
        refreshAccounts()
        if (BuildConfig.DEBUG && AccountStore.active == null) {
            debugLogin?.let { input ->
                runCatching { login(input) }
                return
            }
        }
        val active = AccountStore.active
        if (active != null) start(active) else phase = SessionPhase.SignedOut
    }

    fun refreshAccounts() { accounts = AccountStore.accounts }

    suspend fun recoverFromLaunchFailure() {
        RelayConfig.databaseDir.deleteRecursively()
        RelayConfig.resetRelays()
        launch()
    }

    suspend fun login(input: String) {
        val stored = if (Nip05Resolver.looksLikeAddress(input)) {
            AccountStore.storeReadOnly(Nip05Resolver.resolve(input).pubkey)
        } else {
            AccountStore.login(input)
        }
        isNewAccount = false
        start(stored)
    }

    suspend fun login(input: String, password: String) {
        val stored = AccountStore.login(input, password)
        isNewAccount = false
        start(stored)
    }

    suspend fun addKey(input: String, password: String? = null) {
        val current = account ?: return
        if (!current.isReadOnly) return
        val upgraded = if (password != null) AccountStore.upgrade(current.npub, input, password) else AccountStore.upgrade(current.npub, input)
        val key = AccountStore.storedSigningKey(upgraded.npub) ?: throw AuthError.InvalidKey
        com.qiqstr.core.updateSigner(key)
        account = upgraded
        refreshAccounts()
        val generation = this.generation
        SessionHooks.runBootstrap(upgraded.pubkeyHex)
        if (generation != this.generation) return
        DataBus.everythingChanged()
    }

    fun requireSigner() {
        if (!canSign) {
            if (account?.isReadOnly == true) ReadOnlyGate.present()
            throw ReadOnlyError()
        }
    }

    suspend fun createAccount(): Account {
        val created = AccountStore.createAccount()
        isNewAccount = true
        start(created)
        return created
    }

    suspend fun switchAccount(npub: String) {
        val target = AccountStore.switchTo(npub)
        isNewAccount = false
        start(target)
    }

    suspend fun logout(erasingData: Boolean = false) {
        val leaving = account?.pubkeyHex
        val next = AccountStore.logoutActive()
        teardown()
        refreshAccounts()
        if (leaving != null) {
            if (erasingData) {
                account = null
                phase = SessionPhase.Starting
                AccountData.erase(leaving, isLastAccount = next == null)
            } else {
                AccountData.removeCredentials(leaving)
            }
        }
        if (next != null) {
            start(next)
        } else {
            runCatching { shutdownClient() }
            account = null
            phase = SessionPhase.SignedOut
        }
    }

    suspend fun removeAccount(npub: String) {
        if (npub == account?.npub) {
            logout()
        } else {
            accounts.firstOrNull { it.npub == npub }?.let { AccountData.removeCredentials(it.pubkeyHex) }
            AccountStore.remove(npub)
            refreshAccounts()
        }
    }

    suspend fun wipeEverything() {
        teardown()
        SecureStore.wipe()
        runCatching { dbWipeDirectory() }
        RelayConfig.databaseDir.deleteRecursively()
        Prefs.clear()
        account = null
        refreshAccounts()
        phase = SessionPhase.SignedOut
    }

    private fun teardown() {
        generation += 1
        SyncService.reset()
        SessionHooks.runTeardown()
        mutedPubkeys = emptyList()
        mutedWords = emptyList()
        ProfileCache.clear()
        NotificationBadge.reset()
    }

    private suspend fun start(target: Account) {
        teardown()
        val generation = this.generation
        account = target
        refreshAccounts()
        phase = SessionPhase.Starting
        try {
            RelayConfig.databaseDir.mkdirs()
            initClient(RelayConfig.mainRelays, AccountStore.storedSigningKey(target.npub), RelayConfig.databaseDir.absolutePath, RelayConfig.discoveryRelays)
            applyRelayFlags()
            App.scope.launch { runCatching { connectRelays() } }
            runCatching { waitForReady(3u) }
        } catch (error: Throwable) {
            phase = SessionPhase.Failed(coreErrorMessage(error))
            return
        }
        if (generation != this.generation) return
        phase = SessionPhase.Ready
        DataBus.everythingChanged()
        App.scope.launch { bootstrap(target.pubkeyHex, generation) }
    }

    private suspend fun bootstrap(me: String, generation: Int) {
        coroutineScope {
            launch { SyncService.syncFollowingList(me, force = true) }
            launch { SyncService.syncProfile(me, force = true) }
        }
        if (generation != this.generation) return
        SessionHooks.runBootstrap(me)
        if (generation != this.generation) return
        val follows = SyncService.followingList(me)
        val mode = RelayConfig.gossipMode
        App.scope.launch {
            runCatching { discoverAndConnectOutboxRelays(follows + me, mode.maxOutboxRelays.toUInt(), mode.minRelayFrequency.toUInt()) }
        }
        SyncService.syncFeed(force = true)
        if (generation != this.generation) return
        SyncService.startRealtime()
        SyncService.syncNotifications(force = true)
    }

    private suspend fun applyRelayFlags() {
        val flags = Json.obj(Prefs.string("relay_flags")) ?: return
        for (relay in RelayConfig.mainRelays) {
            val f = flags.optJSONObject(relay) ?: continue
            val read = f.bool("read")
            val write = f.bool("write")
            if (read && write) continue
            runCatching { addRelayWithFlags(relay, read, write) }
        }
    }

    fun isCurrent(generation: Int) = generation == this.generation
}

object SessionHooks {
    private val bootstrapHooks = mutableListOf<suspend (String) -> Unit>()
    private val teardownHooks = mutableListOf<() -> Unit>()

    fun onBootstrap(hook: suspend (String) -> Unit) { bootstrapHooks.add(hook) }
    fun onTeardown(hook: () -> Unit) { teardownHooks.add(hook) }

    suspend fun runBootstrap(pubkey: String) = coroutineScope {
        bootstrapHooks.forEach { hook -> launch { runCatching { hook(pubkey) } } }
    }

    fun runTeardown() = teardownHooks.forEach { runCatching { it() } }
}

object NotificationBadge {
    var hasUnreadNotifications by mutableStateOf(false)
        private set
    var hasUnreadMessages by mutableStateOf(false)
    var unreadCount by mutableIntStateOf(0)
        private set

    fun markUnread(from: String? = null) {
        hasUnreadNotifications = true
        unreadCount += 1
    }

    fun markRead() {
        hasUnreadNotifications = false
        unreadCount = 0
    }

    fun reset() {
        hasUnreadNotifications = false
        hasUnreadMessages = false
        unreadCount = 0
    }
}

object ProfileCache {
    val profiles = mutableStateMapOf<String, Profile>()
    private val inflight = HashSet<String>()

    fun clear() = profiles.clear()

    fun profile(pubkey: String): Profile? = profiles[pubkey]

    fun set(profile: Profile) { profiles[profile.pubkey] = profile }

    suspend fun load(pubkeys: List<String>, fetchMissing: Boolean = true) {
        val wanted = pubkeys.filter { it.isNotEmpty() && it !in inflight }.distinct()
        if (wanted.isEmpty()) return
        inflight.addAll(wanted)
        try {
            val map = Json.obj(runCatching { dbGetProfiles(wanted) }.getOrNull()) ?: JSONObject()
            val missing = mutableListOf<String>()
            for (pk in wanted) {
                when (val value = map.opt(pk)) {
                    is JSONObject -> profiles[pk] = Profile.from(value, pk)
                    is String -> Json.obj(value)?.let { profiles[pk] = Profile.from(it, pk) } ?: missing.add(pk)
                    else -> missing.add(pk)
                }
            }
            if (fetchMissing && missing.isNotEmpty()) SyncService.fetchMissingProfiles(missing)
        } finally {
            inflight.removeAll(wanted.toSet())
        }
    }

    suspend fun refresh(pubkey: String) {
        val raw = runCatching { dbGetProfile(pubkey) }.getOrNull() ?: return
        Json.obj(raw)?.let { profiles[pubkey] = Profile.from(it, pubkey) }
    }
}
