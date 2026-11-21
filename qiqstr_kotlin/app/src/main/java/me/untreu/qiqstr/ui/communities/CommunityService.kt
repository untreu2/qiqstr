package me.untreu.qiqstr.ui.communities

import androidx.compose.runtime.*
import com.qiqstr.core.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.*
import me.untreu.qiqstr.data.bridge.EventStream
import me.untreu.qiqstr.data.services.FollowService
import me.untreu.qiqstr.data.services.RelayConfig
import me.untreu.qiqstr.data.services.WebOfTrustService
import me.untreu.qiqstr.data.sync.*
import me.untreu.qiqstr.domain.Note
import org.json.JSONObject

object CommunityService {
    val groupRelays = listOf("wss://chat.wisp.talk", "wss://relay.highlighter.com", "wss://groups.hzrd149.com", "wss://spatia-arcana.com", "wss://groups.0xchat.com")
    var groups by mutableStateOf<List<RelayGroup>>(emptyList())
        private set
    var communities by mutableStateOf<List<Community>>(emptyList())
        private set
    var channels by mutableStateOf<List<PublicChannel>>(emptyList())
        private set
    var hasLoaded by mutableStateOf(false)
        private set
    private var owner: String? = null
    private var generation = 0
    private val groupCache = mutableMapOf<String, RelayGroup>()
    private val communityCache = mutableMapOf<String, Community>()
    private val channelCache = mutableMapOf<String, PublicChannel>()
    private val listLock = Mutex()
    fun reset() { generation++; owner = null; groups = emptyList(); communities = emptyList(); channels = emptyList(); hasLoaded = false; groupCache.clear(); communityCache.clear(); channelCache.clear() }
    fun trusted(pubkey: String) = CommunitySafety.isTrusted(pubkey, Session.pubkey, FollowService.following.toSet(), WebOfTrustService.isReady, WebOfTrustService.isReady && WebOfTrustService.isTrusted(pubkey))
    fun allows(vararg fields: String) = CommunitySafety.allows(*fields, sensitive = WebOfTrustService.showsSensitiveContent)
    suspend fun load() = coroutineScope {
        val me = Session.pubkey ?: return@coroutineScope
        if (owner != me) { reset(); owner = me }
        val gen = generation
        val gl = async { SyncService.fetchReplaceable(10009, me).maxByOrNull { it.long("created_at") }?.tags().orEmpty() }
        val cl = async { SyncService.fetchReplaceable(10004, me).maxByOrNull { it.long("created_at") }?.tags().orEmpty() }
        val chl = async { SyncService.fetchReplaceable(10005, me).maxByOrNull { it.long("created_at") }?.tags().orEmpty() }
        val refs = gl.await().filter { it.size > 2 && it[0] == "group" }.mapNotNull { tag -> normalizedRelay(tag[2])?.let { RelayGroup(tag[1], it, tag.getOrElse(3) { "" }) } }.distinctBy { it.id }
        val coordinates = cl.await().filter { it.size > 1 && it[0] == "a" }.map { it[1] }
        val ids = chl.await().filter { it.size > 1 && it[0] == "e" }.map { it[1] }
        if (gen != generation || me != Session.pubkey) return@coroutineScope
        groups = refs.map { groupCache[it.id] ?: it }
        hasLoaded = true
        val rg = async { resolveGroups(refs) }; val rc = async { resolveCommunities(coordinates) }; val rch = async { resolveChannels(ids) }
        val g = rg.await(); val c = rc.await(); val ch = rch.await()
        if (gen != generation || me != Session.pubkey) return@coroutineScope
        groups = g; communities = c; channels = ch
    }
    fun isJoined(group: RelayGroup) = groups.any { it.id == group.id }
    fun isJoined(community: Community) = communities.any { it.id == community.id }
    fun isJoined(channel: PublicChannel) = channels.any { it.id == channel.id }
    private suspend fun editList(kind: Int, change: (List<List<String>>) -> List<List<String>>) = listLock.withLock {
        val me = Session.pubkey ?: throw CoreError(L("readOnlyMessage"))
        Session.requireSigner()
        val base = SyncService.latestEditableEvent(kind, me, allowingNew = true)
        if (me != Session.pubkey) throw CancellationException()
        SyncService.publish(signEvent(kind.toUShort(), base?.text("content").orEmpty(), change(base?.tags().orEmpty())))
        if (me != Session.pubkey) throw CancellationException()
    }
    private suspend fun resolveGroups(refs: List<RelayGroup>): List<RelayGroup> = coroutineScope {
        val gen = generation
        val found = refs.groupBy { it.relay }.map { (relay, list) -> async { fetch(mapOf("kinds" to listOf(39000), "#d" to list.map { it.groupId }), listOf(relay), 6).sortedByDescending { it.long("created_at") }.mapNotNull { RelayGroup.from(it, relay) }.distinctBy { it.id } } }.awaitAll().flatten().associateBy { it.id }
        if (gen == generation) groupCache.putAll(found)
        refs.map { found[it.id] ?: groupCache[it.id] ?: it }
    }
    private suspend fun resolveCommunities(coordinates: List<String>): List<Community> {
        val gen = generation
        val parsed = coordinates.mapNotNull(Community::parse)
        if (parsed.isEmpty()) return emptyList()
        val events = SyncService.fetchEvents(mapOf("kinds" to listOf(34550), "authors" to parsed.map { it.first }.distinct(), "#d" to parsed.map { it.second }.distinct()), 8)
        if (gen == generation) latestCommunities(events).forEach { communityCache[it.id] = it }
        return coordinates.distinct().mapNotNull { communityCache[it] }
    }
    private suspend fun resolveChannels(ids: List<String>): List<PublicChannel> = coroutineScope {
        if (ids.isEmpty()) return@coroutineScope emptyList()
        val gen = generation
        val relays = readRelays()
        val created = async { fetch(mapOf("kinds" to listOf(40), "ids" to ids), relays, 8) }
        val metadata = async { fetch(mapOf("kinds" to listOf(41), "#e" to ids, "limit" to 200), relays, 8) }
        val found = parseChannels(created.await(), metadata.await())
        if (gen == generation) found.forEach { channelCache[it.id] = it }
        ids.distinct().mapNotNull { channelCache[it] }
    }
    suspend fun community(coordinate: String): Community? = resolveCommunities(listOf(coordinate)).firstOrNull() ?: communityCache[coordinate]
    suspend fun channel(id: String): PublicChannel? = resolveChannels(listOf(id)).firstOrNull() ?: channelCache[id]
    suspend fun group(ref: RelayGroup): RelayGroup = resolveGroups(listOf(ref)).firstOrNull() ?: ref
    suspend fun discoverGroups(relay: String): List<RelayGroup> {
        val url = normalizedRelay(relay) ?: return emptyList()
        val gen = generation
        val found = fetch(mapOf("kinds" to listOf(39000), "limit" to 300), listOf(url), 8).sortedByDescending { it.long("created_at") }.mapNotNull { RelayGroup.from(it, url) }.filter { !it.isPrivate && allows(it.name, it.about) }.distinctBy { it.id }.sortedBy { it.displayName.lowercase() }
        if (gen == generation) found.forEach { groupCache[it.id] = it }
        return found
    }
    suspend fun discoverCommunities(): List<Community> {
        val gen = generation
        val follows = FollowService.following.take(500)
        val counts = mutableMapOf<String, Int>()
        fun count(id: String, amount: Int = 1) { counts[id] = (counts[id] ?: 0) + amount }
        if (follows.isNotEmpty()) {
            val lists = SyncService.fetchEvents(mapOf("kinds" to listOf(10004), "authors" to follows, "limit" to 500), 8)
            for (list in lists.filter { it.str("pubkey") in follows }) list.tags().filter { it.size > 1 && it[0] == "a" && it[1].startsWith("34550:") }.map { it[1] }.distinct().forEach { count(it) }
            val created = SyncService.fetchEvents(mapOf("kinds" to listOf(34550), "authors" to follows, "limit" to 100), 8)
            if (gen != generation) throw CancellationException()
            latestCommunities(created).filter { it.pubkey in follows }.forEach { communityCache[it.id] = it; count(it.id) }
        }
        val posts = SyncService.fetchEvents(mapOf("kinds" to listOf(1111), "#K" to listOf("34550"), "limit" to 300), 8)
        for (post in posts) {
            val coordinate = post.tags().firstOrNull { it.size > 1 && it[0] == "A" }?.get(1) ?: continue
            val author = Community.parse(coordinate)?.first ?: continue
            if (trusted(author)) count(coordinate)
        }
        if (gen != generation) throw CancellationException()
        return resolveCommunities(counts.entries.sortedByDescending { it.value }.take(60).map { it.key }).filter { it.pubkey !in Session.mutedPubkeys && allows(it.name, it.summary, it.rules) }
    }
    suspend fun discoverChannels(): List<PublicChannel> {
        val gen = generation
        val relays = readRelays()
        val follows = FollowService.following.take(500)
        val counts = mutableMapOf<String, Int>()
        fun count(id: String, amount: Int = 1) { counts[id] = (counts[id] ?: 0) + amount }
        if (follows.isNotEmpty()) {
            val lists = fetch(mapOf("kinds" to listOf(10005), "authors" to follows, "limit" to 500), relays, 8)
            for (list in lists.filter { it.str("pubkey") in follows }) list.tags().filter { it.size > 1 && it[0] == "e" }.map { it[1] }.distinct().forEach { count(it, 3) }
        }
        val recent = fetch(mapOf("kinds" to listOf(42), "since" to TimeFormat.now - 14 * 86400, "limit" to 500), relays, 8)
        for (message in recent) if (message.str("pubkey")?.let(::trusted) == true) channelRoot(message)?.let { count(it) }
        if (gen != generation) throw CancellationException()
        return resolveChannels(counts.entries.sortedByDescending { it.value }.take(60).map { it.key }).filter { it.creator !in Session.mutedPubkeys && allows(it.name, it.about) }
    }
    suspend fun groupHistory(group: RelayGroup) = CommunityChatMessage.list(fetch(mapOf("kinds" to listOf(9), "#h" to listOf(group.groupId), "limit" to 150), listOf(group.relay), 8).filter { e -> e.tags().any { it.size > 1 && it[0] == "h" && it[1] == group.groupId } }, 9)
    suspend fun groupMemberCount(group: RelayGroup): Int? = fetch(mapOf("kinds" to listOf(39002), "#d" to listOf(group.groupId), "limit" to 1), listOf(group.relay), 6).maxByOrNull { it.long("created_at") }?.tags()?.filter { it.size > 1 && it[0] == "p" }?.map { it[1] }?.distinct()?.size
    fun groupStream(group: RelayGroup): Flow<CommunityChatMessage> = stream(mapOf("kinds" to listOf(9), "#h" to listOf(group.groupId), "since" to TimeFormat.now - 5), listOf(group.relay)).filter { e -> e.tags().any { it.size > 1 && it[0] == "h" && it[1] == group.groupId } }.mapNotNull { CommunityChatMessage.from(it, 9) }
    suspend fun channelHistory(channel: PublicChannel) = CommunityChatMessage.list(fetch(mapOf("kinds" to listOf(42), "#e" to listOf(channel.id), "limit" to 150), readRelays(channel.relays), 8).filter { channelRoot(it) == channel.id }, 42)
    suspend fun channelStream(channel: PublicChannel): Flow<CommunityChatMessage> = stream(mapOf("kinds" to listOf(42), "#e" to listOf(channel.id), "since" to TimeFormat.now - 5), readRelays(channel.relays)).filter { channelRoot(it) == channel.id }.mapNotNull { CommunityChatMessage.from(it, 42) }
    suspend fun send(text: String, group: RelayGroup): CommunityChatMessage {
        val event = sign(9, text, listOf(listOf("h", group.groupId)))
        sendToRelays(event, listOf(group.relay))
        return CommunityChatMessage.from(JSONObject(event), 9) ?: throw CoreError(L("liveSendFailed"))
    }
    suspend fun send(text: String, channel: PublicChannel): CommunityChatMessage {
        val event = sign(42, text, listOf(listOf("e", channel.id, channel.relays.firstOrNull().orEmpty(), "root")))
        SyncService.publish(event)
        if (channel.relays.isNotEmpty()) App.scope.launch { runCatching { sendToRelays(event, channel.relays) } }
        return CommunityChatMessage.from(JSONObject(event), 42) ?: throw CoreError(L("liveSendFailed"))
    }
    suspend fun join(group: RelayGroup) {
        val account = Session.pubkey
        runCatching { sendToRelays(sign(9021, "", listOf(listOf("h", group.groupId))), listOf(group.relay)) }
        if (account != Session.pubkey) throw CancellationException()
        editList(10009) { tags -> tags.filterNot { groupTag(it, group) } + listOf(listOf("group", group.groupId, group.relay) + listOf(group.name).filter { it.isNotEmpty() }) }
        groupCache[group.id] = group; groups = groups.filterNot { it.id == group.id } + group
    }
    suspend fun leave(group: RelayGroup) {
        val account = Session.pubkey
        runCatching { sendToRelays(sign(9022, "", listOf(listOf("h", group.groupId))), listOf(group.relay)) }
        if (account != Session.pubkey) throw CancellationException()
        editList(10009) { tags -> tags.filterNot { groupTag(it, group) } }; groups = groups.filterNot { it.id == group.id }
    }
    private fun groupTag(tag: List<String>, group: RelayGroup) = tag.size > 2 && tag[0] == "group" && tag[1] == group.groupId && normalizedRelay(tag[2]) == group.relay
    suspend fun join(channel: PublicChannel) { editList(10005) { it.filterNot { tag -> tag.size > 1 && tag[0] == "e" && tag[1] == channel.id } + listOf(listOf("e", channel.id)) }; channelCache[channel.id] = channel; channels = channels.filterNot { it.id == channel.id } + channel }
    suspend fun leave(channel: PublicChannel) { editList(10005) { it.filterNot { tag -> tag.size > 1 && tag[0] == "e" && tag[1] == channel.id } }; channels = channels.filterNot { it.id == channel.id } }
    suspend fun join(community: Community) { editList(10004) { it.filterNot { tag -> tag.size > 1 && tag[0] == "a" && tag[1] == community.id } + listOf(listOf("a", community.id)) }; communityCache[community.id] = community; communities = communities.filterNot { it.id == community.id } + community }
    suspend fun leave(community: Community) { editList(10004) { it.filterNot { tag -> tag.size > 1 && tag[0] == "a" && tag[1] == community.id } }; communities = communities.filterNot { it.id == community.id } }
    suspend fun posts(community: Community): List<Note> = coroutineScope {
        val relays = readRelays(community.relays)
        val modern = async { fetch(mapOf("kinds" to listOf(1111), "#A" to listOf(community.id), "limit" to 60), relays, 8) }
        val legacy = async { fetch(mapOf("kinds" to listOf(1), "#a" to listOf(community.id), "limit" to 60), relays, 8) }
        val events = (modern.await() + legacy.await()).filter { isCommunityPost(it, community.id) }.distinctBy { it.str("id") }.sortedByDescending { it.long("created_at") }
        if (events.isEmpty()) return@coroutineScope emptyList()
        runCatching { dbSaveEvents(Json.string(events)) }
        val ids = events.mapNotNull { it.str("id") }.take(60)
        val notes = Note.list(runCatching { dbGetHydratedNotesByIds(ids, Session.mutedPubkeys, Session.mutedWords, Session.pubkey) }.getOrNull())
        ProfileCache.load(notes.map { it.pubkey }.distinct())
        notes.sortedBy { ids.indexOf(it.id) }
    }
    suspend fun post(text: String, images: List<String>, community: Community) {
        val content = (listOf(text.trim()) + images).filter { it.isNotEmpty() }.joinToString("\n\n")
        if (content.isEmpty()) throw CoreError(L("liveChatEmptyMessage"))
        val relay = community.relays.firstOrNull().orEmpty()
        val tags = listOf(listOf("A", community.id, relay), listOf("a", community.id, relay), listOf("K", "34550"), listOf("k", "34550"), listOf("P", community.pubkey), listOf("p", community.pubkey)) + images.map { listOf("imeta", "url $it") }
        val event = sign(1111, content, tags)
        SyncService.publish(event)
        if (community.relays.isNotEmpty()) App.scope.launch { runCatching { sendToRelays(event, community.relays) } }
        DataBus.feedChanged()
    }
    fun latestCommunities(events: List<JSONObject>) = events.mapNotNull(Community::from).sortedByDescending { it.createdAt }.distinctBy { it.id }
    fun parseChannels(created: List<JSONObject>, metadata: List<JSONObject>): List<PublicChannel> = created.mapNotNull(PublicChannel::from).distinctBy { it.id }.map { channel -> metadata.fold(channel) { value, event -> value.metadata(event) } }
    private fun sign(kind: Int, content: String, tags: List<List<String>>) = signEvent(kind.toUShort(), content.trim(), tags)
    private suspend fun sendToRelays(event: String, relays: List<String>) {
        val result = Json.obj(sendEventTo(event, relays))
        if (result?.optJSONArray("success")?.length() == null || result.optJSONArray("success")!!.length() == 0) throw CoreError(L("publishNoRelayAccepted"))
    }
    private suspend fun readRelays(extra: List<String> = emptyList()) = (runCatching { getRelayList() }.getOrDefault(RelayConfig.mainRelays) + extra.take(4)).filter { it.startsWith("wss://") }.distinct()
    private suspend fun fetch(filter: Map<String, Any>, relays: List<String>, timeout: Int): List<JSONObject> = Json.array(runCatching { fetchEventsFromRelays(Json.string(filter), relays, timeout.toUInt()) }.getOrNull())
    private fun stream(filter: Map<String, Any>, relays: List<String>) = EventStream.make { sink -> subscribeToEventsOnRelays(Json.string(filter), relays, sink) }.mapNotNull { Json.obj(it) }
}

object CommunitiesFeature : FeatureHooks {
    override fun register() { SessionHooks.onTeardown { CommunityService.reset() } }
}
