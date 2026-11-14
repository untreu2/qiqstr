package me.untreu.qiqstr.data.services

import android.net.Uri
import androidx.compose.runtime.Immutable
import com.qiqstr.core.createDeletionEvent
import com.qiqstr.core.createNoteEvent
import com.qiqstr.core.createQuoteEvent
import com.qiqstr.core.createReactionEvent
import com.qiqstr.core.createReplyEvent
import com.qiqstr.core.createRepostEvent
import com.qiqstr.core.createSignedEvent
import com.qiqstr.core.dbDeleteEventsByIds
import com.qiqstr.core.dbGetBatchInteractionData
import com.qiqstr.core.dbGetDetailedInteractions
import com.qiqstr.core.dbGetEvent
import com.qiqstr.core.dbQueryEvents
import com.qiqstr.core.fetchCountsFromRelays
import com.qiqstr.core.getRelayList
import com.qiqstr.core.streamInteractionCounts
import com.qiqstr.core.verifyNoteById
import com.qiqstr.core.verifyProfileByPubkey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import me.untreu.qiqstr.core.CoreError
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.bool
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.tags
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.bridge.EventStream
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Note
import org.json.JSONObject

@Immutable
data class InteractionCounts(
    val reactions: Int = 0,
    val reposts: Int = 0,
    val replies: Int = 0,
    val zapAmount: Int = 0,
    val hasReacted: Boolean = false,
    val hasReposted: Boolean = false,
    val hasZapped: Boolean = false,
) {
    companion object {
        fun from(note: Note) = InteractionCounts(
            note.reactionCount, note.repostCount, note.replyCount, note.zapCount, note.hasReacted, note.hasReposted, note.hasZapped,
        )

        fun from(j: JSONObject) = InteractionCounts(
            j.int("reactions"), j.int("reposts"), j.int("replies"), j.int("zaps"), j.bool("hasReacted"), j.bool("hasReposted"), j.bool("hasZapped"),
        )
    }
}

enum class NoteInteractionKind(val raw: String) {
    REACTION("reaction"), REPOST("repost"), ZAP("zap");

    companion object {
        fun from(raw: String?) = entries.firstOrNull { it.raw == raw }
    }
}

@Immutable
data class NoteInteractionDetail(
    val kind: NoteInteractionKind,
    val pubkey: String,
    val content: String,
    val zapAmount: Int,
    val createdAt: Long,
) {
    val id: String get() = "${kind.raw}-$pubkey-$createdAt-${content.hashCode()}"

    companion object {
        fun from(j: JSONObject): NoteInteractionDetail? {
            val kind = NoteInteractionKind.from(j.str("type")) ?: return null
            val pubkey = j.str("pubkey") ?: return null
            return NoteInteractionDetail(kind, pubkey, j.text("content"), j.int("zapAmount"), j.long("createdAt"))
        }
    }
}

enum class NoteReportReason(val raw: String) {
    SPAM("spam"), NUDITY("nudity"), PROFANITY("profanity"), ILLEGAL("illegal"), IMPERSONATION("impersonation"), OTHER("other");

    val id: String get() = raw

    val title: String
        get() = when (this) {
            SPAM -> L("reportReasonSpam")
            NUDITY -> L("reportReasonNudity")
            PROFANITY -> L("reportReasonProfanity")
            ILLEGAL -> L("reportReasonIllegal")
            IMPERSONATION -> L("reportReasonImpersonation")
            OTHER -> L("reportReasonOther")
        }
}

object InteractionService {
    private fun signingKey(): String = Session.requireSigner()

    private suspend fun primaryRelay(): String =
        runCatching { getRelayList() }.getOrNull()?.firstOrNull() ?: RelayConfig.mainRelays.firstOrNull() ?: ""

    suspend fun react(note: Note, content: String = "+") {
        val key = signingKey()
        val relay = primaryRelay()
        val event = createReactionEvent(note.id, note.pubkey, content, key, relay, 1u.toUShort())
        SyncService.publish(event)
    }

    suspend fun unreact(note: Note) {
        val key = signingKey()
        val me = Session.pubkey ?: return
        val ids = ownEvents(listOf(7), me, note.id) { event ->
            event.tags().lastOrNull { it.size > 1 && it[0] == "e" }?.get(1) == note.id
        }
        if (ids.isEmpty()) throw CoreError(L("eventNotFound"))
        publishDeletion(ids, key)
    }

    suspend fun repost(note: Note) {
        val key = signingKey()
        val relay = primaryRelay()
        val original = runCatching { dbGetEvent(note.id) }.getOrNull()
        val event = createRepostEvent(note.id, note.pubkey, original ?: "", key, relay)
        SyncService.publish(event)
    }

    suspend fun undoRepost(note: Note) {
        val key = signingKey()
        val me = Session.pubkey ?: return
        val ids = ownEvents(listOf(6, 16), me, note.id) { event ->
            event.tags().any { it.size > 1 && it[0] == "e" && it[1] == note.id }
        }
        if (ids.isEmpty()) throw CoreError(L("eventNotFound"))
        publishDeletion(ids, key)
    }

    private suspend fun ownEvents(kinds: List<Int>, me: String, target: String, matching: (JSONObject) -> Boolean): List<String> {
        val filter = mapOf("kinds" to kinds, "authors" to listOf(me), "#e" to listOf(target), "limit" to 20)
        val local = Json.array(runCatching { dbQueryEvents(Json.string(filter), 20u) }.getOrNull())
        val remote = SyncService.fetchEvents(filter, timeout = 6)
        return (local + remote)
            .filter { it.str("pubkey") == me && it.int("kind") in kinds && matching(it) }
            .mapNotNull { it.str("id") }
            .distinct()
    }

    suspend fun delete(note: Note) {
        val key = signingKey()
        publishDeletion(listOf(note.id), key)
    }

    private suspend fun publishDeletion(ids: List<String>, key: String) {
        val event = createDeletionEvent(ids, "", key)
        SyncService.publish(event)
        runCatching { dbDeleteEventsByIds(ids) }
        DataBus.feedChanged()
        DataBus.interactionsChanged()
    }

    suspend fun publishNote(content: String, mediaUrls: List<String>, extraTags: List<List<String>> = emptyList()): String {
        val key = signingKey()
        val body = composeContent(content, mediaUrls)
        val tags = merge(contentTags(body, mediaUrls), extraTags)
        val event = createNoteEvent(body, tags, key)
        return publishReturningId(event)
    }

    suspend fun publishReply(note: Note, content: String, mediaUrls: List<String>, extraTags: List<List<String>> = emptyList()): String {
        val key = signingKey()
        val me = Session.pubkey ?: ""
        val body = composeContent(content, mediaUrls)
        val rootId = note.rootId ?: note.parentId ?: note.id
        var tags = mutableListOf<List<String>>()
        if (rootId == note.id) {
            tags.add(listOf("e", note.id, "", "root", note.pubkey))
        } else {
            val rootAuthor = rootAuthor(note, rootId)
            tags.add(listOf("e", rootId, "", "root") + listOfNotNull(rootAuthor))
            tags.add(listOf("e", note.id, "", "reply", note.pubkey))
        }
        val pubkeys = mutableListOf(note.pubkey)
        for (tag in note.tags) if (tag.size > 1 && tag[0] == "p" && tag[1].length == 64) pubkeys.add(tag[1])
        val seen = LinkedHashSet<String>()
        for (pk in pubkeys) if (pk != me && seen.add(pk)) tags.add(listOf("p", pk))
        if (seen.isEmpty() && note.pubkey.isNotEmpty()) tags.add(listOf("p", note.pubkey))
        val extra = contentTags(body, mediaUrls).filter { it.firstOrNull() != "p" || (if (it.size > 1) it[1] else "") !in seen }
        tags = merge(tags, extra + extraTags.filter { it.firstOrNull() != "e" }).toMutableList()
        val event = createReplyEvent(body, tags, key)
        return publishReturningId(event)
    }

    suspend fun publishQuote(note: Note, content: String, mediaUrls: List<String>, extraTags: List<List<String>> = emptyList()): String {
        val key = signingKey()
        val reference = Nip19.nevent(note.id, note.pubkey) ?: Nip19.note(note.id) ?: note.id
        val text = composeContent(content, mediaUrls)
        val body = if (text.isEmpty()) "nostr:$reference" else "$text\nnostr:$reference"
        val relay = primaryRelay()
        val additional = merge(contentTags(body, mediaUrls), extraTags).filter { tag ->
            val first = tag.firstOrNull() ?: return@filter false
            if (first == "q") return@filter false
            !(first == "p" && tag.size > 1 && tag[1] == note.pubkey)
        }
        val event = createQuoteEvent(body, note.id, note.pubkey, relay, key, additional)
        return publishReturningId(event)
    }

    suspend fun publishPoll(
        question: String,
        options: List<String>,
        multiple: Boolean,
        endsAt: Long?,
        mediaUrls: List<String>,
        extraTags: List<List<String>> = emptyList(),
    ): String {
        val key = signingKey()
        val body = composeContent(question, mediaUrls)
        var tags: List<List<String>> = options.map { listOf("option", pollOptionId(), it) }
        tags = tags + listOf(listOf("polltype", if (multiple) "multiplechoice" else "singlechoice"))
        if (endsAt != null) tags = tags + listOf(listOf("endsAt", endsAt.toString()))
        val relays = runCatching { getRelayList() }.getOrNull() ?: RelayConfig.mainRelays
        tags = tags + relays.take(3).filter { it.startsWith("wss://") }.map { listOf("relay", it) }
        tags = merge(tags, contentTags(body, mediaUrls) + extraTags)
        val event = createSignedEvent(NotePoll.KIND.toUShort(), body, tags, key)
        return publishReturningId(event)
    }

    suspend fun publishPollResponse(pollId: String, optionIds: List<String>, relays: List<String>) {
        val key = signingKey()
        val tags = listOf(listOf("e", pollId)) + optionIds.map { listOf("response", it) }
        val event = createSignedEvent(NotePoll.RESPONSE_KIND.toUShort(), "", tags, key)
        if (relays.isNotEmpty() && runCatching { SyncService.publish(event, relays) }.isSuccess) return
        SyncService.publish(event)
    }

    private fun pollOptionId(): String {
        val alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
        return (0 until 9).map { alphabet.random() }.joinToString("")
    }

    suspend fun report(pubkey: String, noteId: String?, reason: String) {
        val key = signingKey()
        val tags = mutableListOf(listOf("p", pubkey, reason))
        if (!noteId.isNullOrEmpty()) tags.add(listOf("e", noteId, reason))
        val event = createSignedEvent(1984u.toUShort(), "", tags, key)
        SyncService.publish(event)
    }

    private suspend fun publishReturningId(eventJson: String): String = SyncService.publish(eventJson).str("id") ?: ""

    suspend fun localCounts(noteIds: List<String>): Map<String, InteractionCounts> {
        val me = Session.pubkey ?: return emptyMap()
        if (noteIds.isEmpty()) return emptyMap()
        return decodeCounts(runCatching { dbGetBatchInteractionData(noteIds, me) }.getOrNull())
    }

    suspend fun relayCounts(noteIds: List<String>): Map<String, InteractionCounts> {
        if (noteIds.isEmpty()) return emptyMap()
        return decodeCounts(runCatching { fetchCountsFromRelays(noteIds, Session.pubkey) }.getOrNull())
    }

    fun liveCounts(noteIds: List<String>): Flow<Map<String, InteractionCounts>> {
        val me = Session.pubkey
        return EventStream.make { sink -> streamInteractionCounts(noteIds, me, sink) }.map { decodeCounts(it) }
    }

    suspend fun verify(note: Note): Pair<Boolean, Boolean> {
        val event = runCatching { verifyNoteById(note.id) }.getOrDefault(false)
        val profile = runCatching { verifyProfileByPubkey(note.pubkey) }.getOrDefault(false)
        return event to profile
    }

    suspend fun detailedInteractions(noteId: String): List<NoteInteractionDetail> =
        Json.array(runCatching { dbGetDetailedInteractions(noteId) }.getOrNull()).mapNotNull { NoteInteractionDetail.from(it) }

    fun decodeCounts(raw: String?): Map<String, InteractionCounts> {
        val map = Json.obj(raw) ?: return emptyMap()
        val result = HashMap<String, InteractionCounts>()
        for (key in map.keys()) map.optJSONObject(key)?.let { result[key] = InteractionCounts.from(it) }
        return result
    }

    fun composeContent(content: String, mediaUrls: List<String>): String {
        val text = content.trim()
        val media = mediaUrls.filter { !text.contains(it) }
        if (media.isEmpty()) return text
        return if (text.isEmpty()) media.joinToString("\n") else "$text\n\n${media.joinToString("\n")}"
    }

    private fun rootAuthor(note: Note, rootId: String): String? =
        note.tags.firstOrNull { it.size > 4 && it[0] == "e" && it[1] == rootId && it[3] == "root" && it[4].length == 64 }?.get(4)

    fun contentTags(content: String, mediaUrls: List<String>): List<List<String>> {
        val tags = mutableListOf<List<String>>()
        for (tag in hashtags(content)) tags.add(listOf("t", tag))
        for (pubkey in mentionedPubkeys(content)) tags.add(listOf("p", pubkey))
        for ((id, _) in quotedEvents(content)) tags.add(listOf("q", id))
        for (url in mediaUrls) {
            val imeta = mutableListOf("imeta", "url $url")
            mimeType(url)?.let { imeta.add("m $it") }
            tags.add(imeta)
        }
        return tags
    }

    private val hashtagRegex = Regex("""(?:^|\s)#([\p{L}\p{N}_]+)""")
    private val mentionRegex = Regex("""nostr:((?:npub1|nprofile1)[0-9a-z]+)""", RegexOption.IGNORE_CASE)
    private val quoteRegex = Regex("""nostr:((?:note1|nevent1)[0-9a-z]+)""", RegexOption.IGNORE_CASE)

    fun hashtags(content: String): List<String> =
        hashtagRegex.findAll(content).map { it.groupValues[1].lowercase() }.distinct().toList()

    fun mentionedPubkeys(content: String): List<String> =
        mentionRegex.findAll(content).mapNotNull { Nip19.pubkeyHex(it.groupValues[1]) }.distinct().toList()

    fun quotedEvents(content: String): List<Pair<String, String>> {
        val result = mutableListOf<Pair<String, String>>()
        for (match in quoteRegex.findAll(content)) {
            val bech = match.groupValues[1]
            val hex = Nip19.decode(bech) ?: continue
            if (result.none { it.first == hex }) result.add(hex to bech)
        }
        return result
    }

    fun mimeType(url: String): String? {
        val path = (runCatching { Uri.parse(url).path }.getOrNull() ?: url).lowercase()
        return when {
            path.endsWith(".jpg") || path.endsWith(".jpeg") -> "image/jpeg"
            path.endsWith(".png") -> "image/png"
            path.endsWith(".gif") -> "image/gif"
            path.endsWith(".webp") -> "image/webp"
            path.endsWith(".mp4") -> "video/mp4"
            path.endsWith(".mov") -> "video/quicktime"
            else -> null
        }
    }

    private fun imetaKey(entry: String): String = entry.split(" ", limit = 2).first()

    fun merge(base: List<List<String>>, extra: List<List<String>>): List<List<String>> {
        val result = base.toMutableList()
        for (tag in extra) {
            if (tag.isEmpty()) continue
            val url = tag.getOrNull(1)
            val index = if (tag[0] == "imeta" && url != null) result.indexOfFirst { it.firstOrNull() == "imeta" && it.getOrNull(1) == url } else -1
            if (index >= 0) {
                val merged = result[index].toMutableList()
                for (entry in tag.drop(2)) if (merged.drop(1).none { imetaKey(it) == imetaKey(entry) }) merged.add(entry)
                result[index] = merged
            } else if (result.none { it.take(2) == tag.take(2) }) {
                result.add(tag)
            }
        }
        return result
    }
}
