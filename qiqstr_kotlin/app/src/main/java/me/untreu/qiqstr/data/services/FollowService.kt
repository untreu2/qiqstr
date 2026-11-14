package me.untreu.qiqstr.data.services

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.qiqstr.core.createSignedEvent
import com.qiqstr.core.dbGetFollowingList
import com.qiqstr.core.dbQueryEvents
import com.qiqstr.core.dbSaveFollowingListFromEvent
import com.qiqstr.core.getConnectedRelayCount
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.CoreError
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.accounts.AccountStore
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import org.json.JSONObject

class FollowError : Exception() {
    override val message: String get() = L("followListUnavailable")
}

object FollowService {
    var following by mutableStateOf<Set<String>>(emptySet())
        private set
    var pending by mutableStateOf<Set<String>>(emptySet())
        private set
    var isLoaded by mutableStateOf(false)
        private set
    private var generation = 0
    private val queue = Mutex()
    private var verifiedAt: Long? = null
    private const val VERIFICATION_WINDOW = 60_000L

    val count: Int get() = following.size

    fun isFollowing(pubkey: String) = pubkey in following
    fun isPending(pubkey: String) = pubkey in pending

    fun reset() {
        generation += 1
        following = emptySet()
        pending = emptySet()
        isLoaded = false
        verifiedAt = null
    }

    suspend fun load() {
        val me = Session.pubkey ?: return
        val generation = this.generation
        SyncService.syncFollowingList(me)
        if (generation != this.generation) return
        val list = localList(me)
        if (generation != this.generation) return
        if (pending.isEmpty()) following = list
        isLoaded = true
    }

    suspend fun refresh() {
        val me = Session.pubkey ?: return
        val generation = this.generation
        val list = localList(me)
        if (generation != this.generation || pending.isNotEmpty()) return
        following = list
    }

    suspend fun follow(pubkey: String, creatingList: Boolean = false) = mutate(setOf(pubkey), creatingList) { it + pubkey }

    suspend fun unfollow(pubkey: String) = mutate(setOf(pubkey), false) { it - pubkey }

    suspend fun followMany(pubkeys: List<String>, creatingList: Boolean = false) {
        val targets = pubkeys.filter { it.isNotEmpty() }.toSet()
        if (targets.isEmpty()) return
        mutate(targets, creatingList) { it + targets }
    }

    private suspend fun mutate(targets: Set<String>, creatingList: Boolean, change: (Set<String>) -> Set<String>) =
        queue.withLock { apply(targets, creatingList, change) }

    private suspend fun apply(targets: Set<String>, creatingList: Boolean, change: (Set<String>) -> Set<String>) {
        val key = Session.requireSigner()
        val me = Session.pubkey?.lowercase() ?: throw CoreError(L("privateKeyNotFound"))
        val generation = this.generation
        val snapshot = following
        following = change(following) - me
        pending = pending + targets
        try {
            val base = latestContactList(me, creatingList)
            if (generation != this.generation) return
            val baseTags = base?.tags() ?: emptyList()
            val list = change(pubkeys(baseTags)) - me
            val event = createSignedEvent(3u.toUShort(), base?.text("content") ?: "", mergedTags(baseTags, list), key)
            SyncService.publish(event)
            if (generation != this.generation) return
            verifiedAt = System.currentTimeMillis()
            following = list
            DataBus.feedChanged()
            App.scope.launch { SyncService.syncFeed(force = true) }
        } catch (error: Throwable) {
            if (generation == this.generation) following = snapshot
            throw error
        } finally {
            if (generation == this.generation) pending = pending - targets
        }
    }

    private suspend fun latestContactList(me: String, creatingList: Boolean): JSONObject? {
        val filter = Json.string(mapOf("kinds" to listOf(3), "authors" to listOf(me), "limit" to 1))
        val candidates = Json.array(runCatching { dbQueryEvents(filter, 1u) }.getOrNull()).toMutableList()
        val fresh = verifiedAt?.let { System.currentTimeMillis() - it < VERIFICATION_WINDOW } ?: false
        if (!fresh || candidates.isEmpty()) {
            val remote = SyncService.fetchContactLists(me)
            if (remote.isEmpty()) {
                if (candidates.isNotEmpty()) throw FollowError()
            } else {
                verifiedAt = System.currentTimeMillis()
            }
            candidates += remote
        }
        val newest = candidates.filter { it.int("kind") == 3 && it.str("pubkey")?.lowercase() == me }
            .maxWithOrNull(compareBy<JSONObject>({ it.long("created_at") }, { it.str("id") ?: "" }))
        if (newest != null) {
            runCatching { dbSaveFollowingListFromEvent(newest.toString(), me) }
            return newest
        }
        if (runCatching { getConnectedRelayCount() }.getOrDefault(0u) == 0u) throw FollowError()
        if (!creatingList && !Session.isNewAccount && !AccountStore.wasCreatedHere(me)) throw FollowError()
        return null
    }

    private fun pubkeys(tags: List<List<String>>): Set<String> =
        tags.filter { it.size > 1 && it[0] == "p" && it[1].isNotEmpty() }.map { it[1].lowercase() }.toSet()

    private fun mergedTags(base: List<List<String>>, list: Set<String>): List<List<String>> {
        val tags = mutableListOf<List<String>>()
        val kept = mutableSetOf<String>()
        for (tag in base) {
            if (tag.isEmpty()) continue
            if (tag.size <= 1 || tag[0] != "p") { tags.add(tag); continue }
            val pubkey = tag[1].lowercase()
            if (pubkey in list && kept.add(pubkey)) tags.add(tag)
        }
        return tags + (list - kept).sorted().map { listOf("p", it) }
    }

    private suspend fun localList(me: String): Set<String> =
        runCatching { dbGetFollowingList(me) }.getOrDefault(emptyList()).filter { it.isNotEmpty() && it.lowercase() != me.lowercase() }.toSet()
}
