package me.untreu.qiqstr.ui.dm

import com.qiqstr.core.marmotClearPendingCommit
import com.qiqstr.core.marmotClose
import com.qiqstr.core.marmotCreateChat
import com.qiqstr.core.marmotDecryptMedia
import com.qiqstr.core.marmotEncryptMedia
import com.qiqstr.core.marmotGroups
import com.qiqstr.core.marmotGroupsNeedingSelfUpdate
import com.qiqstr.core.marmotKeyPackageEvent
import com.qiqstr.core.marmotKeyPackageRelaysEvent
import com.qiqstr.core.marmotMergePendingCommit
import com.qiqstr.core.marmotMessagesPage
import com.qiqstr.core.marmotOpen
import com.qiqstr.core.marmotPickKeyPackage
import com.qiqstr.core.marmotProcessEvent
import com.qiqstr.core.marmotSelfUpdate
import com.qiqstr.core.marmotSendMessage
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.CoreError
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.bool
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.strings
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.services.RelayConfig
import org.json.JSONObject

data class MarmotGroup(
    val id: String,
    val nostrGroupId: String,
    val name: String,
    val state: String,
    val members: List<String>,
    val relays: List<String>,
    val lastMessageAt: Long,
) {
    val isActive: Boolean get() = state == "active"

    fun peer(me: String): String? {
        val others = members.filter { it != me }
        if (me !in members || others.size != 1) return null
        return others[0]
    }

    companion object {
        fun from(j: JSONObject): MarmotGroup? {
            val id = j.str("id") ?: return null
            val nostrGroupId = j.str("nostrGroupId") ?: return null
            return MarmotGroup(id, nostrGroupId, j.text("name"), j.text("state"), j.strings("members"), j.strings("relays"), j.long("lastMessageAt"))
        }
    }
}

class MarmotOutcome(val eventId: String, raw: String?) {
    val type: String
    val groupId: String?
    val messageJSON: String?
    val groupJSON: String?
    val evolutionEvent: String?
    val isNewWelcome: Boolean
    val retry: List<String>

    init {
        val j = Json.obj(raw) ?: JSONObject()
        type = if (raw == null) "error" else (j.opt("type") as? String) ?: "ignored"
        retry = j.strings("retry")
        groupId = j.str("groupId")
        messageJSON = j.optJSONObject("message")?.toString()
        groupJSON = j.optJSONObject("group")?.toString()
        evolutionEvent = j.str("evolutionEvent")
        isNewWelcome = j.bool("isNew")
    }
}

class MarmotCreatedChat(val groupJSON: String, val welcomes: List<String>, val welcomeRelays: List<String>)

class MarmotSent(val eventJSON: String, val messageJSON: String?)

class MarmotEncryptedMedia(
    val file: File,
    val encryptedHash: String,
    val originalHash: String,
    val mimeType: String,
    val filename: String,
    val size: Int,
    val imeta: List<String>,
)

object MarmotEngine {
    private val lock = Mutex()

    val storageDirectory: File get() = File(RelayConfig.supportDir, "marmot")

    private suspend fun <T> serial(work: suspend () -> T): T = withContext(Dispatchers.IO) { lock.withLock { work() } }

    suspend fun close() {
        withContext(NonCancellable) { runCatching { serial { marmotClose() } } }
    }

    suspend fun open(privateKey: String): String {
        val directory = storageDirectory
        return serial {
            directory.mkdirs()
            marmotOpen(directory.path, privateKey)
        }
    }

    suspend fun groups(): List<MarmotGroup> {
        val raw = serial { marmotGroups() }
        return Json.array(raw).mapNotNull(MarmotGroup::from)
    }

    suspend fun messages(groupId: String, limit: Int, offset: Int = 0): String =
        serial { marmotMessagesPage(groupId, limit.toUInt(), offset.coerceAtLeast(0).toUInt()) }

    suspend fun process(events: List<String>): List<MarmotOutcome> {
        val ordered = events
            .mapNotNull { raw ->
                val j = Json.obj(raw) ?: return@mapNotNull null
                val id = j.str("id") ?: return@mapNotNull null
                Triple(j.long("created_at"), id, raw)
            }
            .sortedWith(compareBy<Triple<Long, String, String>>({ it.first }, { it.second }))
        if (ordered.isEmpty()) return emptyList()
        return runCatching {
            serial { ordered.map { item -> MarmotOutcome(item.second, runCatching { marmotProcessEvent(item.third) }.getOrNull()) } }
        }.getOrDefault(emptyList())
    }

    suspend fun keyPackageEvent(relays: List<String>): String = serial { marmotKeyPackageEvent(relays) }

    suspend fun keyPackageRelaysEvent(relays: List<String>): String = serial { marmotKeyPackageRelaysEvent(relays) }

    suspend fun pickKeyPackage(eventsJSON: String, owner: String): String? = serial { marmotPickKeyPackage(eventsJSON, owner) }

    suspend fun createChat(keyPackage: String, relays: List<String>): MarmotCreatedChat {
        val raw = serial { marmotCreateChat(keyPackage, relays) }
        val j = Json.obj(raw) ?: JSONObject()
        val group = j.optJSONObject("group") ?: throw CoreError(L("dmSendFailed"))
        return MarmotCreatedChat(group.toString(), j.strings("welcomes"), j.strings("welcomeRelays"))
    }

    suspend fun send(groupId: String, kind: Int, content: String, tags: List<List<String>>): MarmotSent {
        val tagsJSON = if (tags.isEmpty()) "[]" else Json.string(tags)
        val raw = serial { marmotSendMessage(groupId, kind.toUShort(), content, tagsJSON) }
        val j = Json.obj(raw) ?: JSONObject()
        val event = j.opt("event") as? String ?: throw CoreError(L("dmSendFailed"))
        return MarmotSent(event, j.optJSONObject("message")?.toString())
    }

    suspend fun rotateKeys(olderThan: Long, publish: suspend (String, String) -> Boolean) {
        runCatching {
            serial {
                val groups = runCatching { marmotGroupsNeedingSelfUpdate(olderThan.toULong()) }.getOrDefault(emptyList())
                for (group in groups) {
                    val commit = runCatching { marmotSelfUpdate(group) }.getOrNull() ?: continue
                    if (publish(group, commit)) {
                        runCatching { marmotMergePendingCommit(group) }
                    } else {
                        runCatching { marmotClearPendingCommit(group) }
                    }
                }
            }
        }
    }

    suspend fun finishCommit(groupId: String, eventJSON: String, publish: suspend (String) -> Boolean) {
        runCatching {
            serial {
                if (publish(eventJSON)) {
                    runCatching { marmotMergePendingCommit(groupId) }
                } else {
                    runCatching { marmotClearPendingCommit(groupId) }
                }
            }
        }
    }

    suspend fun encryptMedia(groupId: String, data: ByteArray, mimeType: String, filename: String): MarmotEncryptedMedia {
        val output = File(App.context.cacheDir, "marmot-upload-${UUID.randomUUID()}")
        val raw = serial { marmotEncryptMedia(groupId, data, mimeType, filename, output.path) }
        val j = Json.obj(raw) ?: JSONObject()
        val encryptedHash = j.str("encryptedHash")
        val originalHash = j.str("originalHash")
        if (encryptedHash == null || originalHash == null) {
            output.delete()
            throw CoreError(L("encryptionFailed"))
        }
        return MarmotEncryptedMedia(
            file = output,
            encryptedHash = encryptedHash,
            originalHash = originalHash,
            mimeType = j.str("mimeType") ?: mimeType,
            filename = j.str("filename") ?: filename,
            size = j.int("size"),
            imeta = j.strings("imeta"),
        )
    }

    suspend fun decryptMedia(groupId: String, imeta: List<String>, data: ByteArray): ByteArray =
        serial { marmotDecryptMedia(groupId, imeta, data) }
}
