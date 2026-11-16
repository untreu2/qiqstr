package me.untreu.qiqstr.ui.compose

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.File
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.bool
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.strings
import me.untreu.qiqstr.data.bridge.isHex
import me.untreu.qiqstr.data.sync.Session
import org.json.JSONArray
import org.json.JSONObject

data class ComposeDraftMedia(
    val url: String,
    val sha256: String,
    val mimeType: String,
    val size: Int,
    val width: Double?,
    val height: Double?,
    val blurhash: String?,
    val altText: String,
    val isVideo: Boolean,
    val duration: Double? = null,
    val waveform: List<Int>? = null,
) {
    val isAudio: Boolean get() = mimeType.startsWith("audio/")

    fun toJson(): JSONObject = JSONObject().apply {
        put("url", url)
        put("sha256", sha256)
        put("mimeType", mimeType)
        put("size", size)
        width?.let { put("width", it) }
        height?.let { put("height", it) }
        blurhash?.let { put("blurhash", it) }
        put("altText", altText)
        put("isVideo", isVideo)
        duration?.let { put("duration", it) }
        waveform?.let { put("waveform", JSONArray(it)) }
    }

    companion object {
        fun from(j: JSONObject): ComposeDraftMedia? {
            val url = j.str("url") ?: return null
            return ComposeDraftMedia(
            url = url,
            sha256 = j.optString("sha256", ""),
            mimeType = j.optString("mimeType", ""),
            size = j.long("size").toInt(),
            width = if (j.has("width")) j.optDouble("width") else null,
            height = if (j.has("height")) j.optDouble("height") else null,
            blurhash = j.str("blurhash"),
            altText = j.optString("altText", ""),
            isVideo = j.bool("isVideo"),
            duration = if (j.has("duration")) j.optDouble("duration").takeIf { !it.isNaN() } else null,
            waveform = j.optJSONArray("waveform")?.let { a -> (0 until a.length()).map { a.optInt(it) } },
            )
        }
    }
}

data class ComposeDraftPoll(val options: List<String>, val multiple: Boolean, val endsAt: Long?) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("options", JSONArray(options))
        put("multiple", multiple)
        endsAt?.let { put("endsAt", it) }
    }

    companion object {
        fun from(j: JSONObject) = ComposeDraftPoll(j.strings("options"), j.bool("multiple"), if (j.has("endsAt")) j.long("endsAt") else null)
    }
}

data class ComposeDraftGoal(val amountSats: Long, val closesAt: Long?) {
    fun toJson() = JSONObject().apply { put("amountSats", amountSats); closesAt?.let { put("closesAt", it) } }
    companion object { fun from(j: JSONObject) = ComposeDraftGoal(j.long("amountSats"), if (j.has("closesAt")) j.long("closesAt") else null) }
}

data class ComposeDraft(
    val id: String,
    val kind: Kind,
    val targetId: String?,
    val targetPubkey: String?,
    val text: String,
    val mentions: Map<String, String>,
    val media: List<ComposeDraftMedia>,
    val contentWarningEnabled: Boolean,
    val contentWarningReason: String,
    val poll: ComposeDraftPoll?,
    val updatedAt: Long,
    val emojis: Map<String, String> = emptyMap(),
    val goal: ComposeDraftGoal? = null,
) {
    enum class Kind(val raw: String) {
        NEW_NOTE("newNote"), REPLY("reply"), QUOTE("quote");

        companion object {
            fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: NEW_NOTE
        }
    }

    val contextKey: String
        get() = when (kind) {
            Kind.NEW_NOTE -> "new"
            Kind.REPLY -> "reply-${targetId ?: ""}"
            Kind.QUOTE -> "quote-${targetId ?: ""}"
        }

    val preview: String get() = text.trim().replace("\n", " ")

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("kind", kind.raw)
        targetId?.let { put("targetId", it) }
        targetPubkey?.let { put("targetPubkey", it) }
        put("text", text)
        put("mentions", JSONObject(mentions))
        put("media", JSONArray(media.map { it.toJson() }))
        put("contentWarningEnabled", contentWarningEnabled)
        put("contentWarningReason", contentWarningReason)
        poll?.let { put("poll", it.toJson()) }
        put("updatedAt", updatedAt)
        put("emojis", JSONObject(emojis))
        goal?.let { put("goal", it.toJson()) }
    }

    companion object {
        fun from(j: JSONObject): ComposeDraft? {
            val id = j.str("id") ?: return null
            val mentions = j.optJSONObject("mentions")?.let { m -> m.keys().asSequence().associateWith { m.optString(it) } } ?: emptyMap()
            val media = j.optJSONArray("media")?.let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it)?.let(ComposeDraftMedia::from) } } ?: emptyList()
            return ComposeDraft(
                id = id,
                kind = Kind.from(j.str("kind")),
                targetId = j.str("targetId"),
                targetPubkey = j.str("targetPubkey"),
                text = j.optString("text", ""),
                mentions = mentions,
                media = media,
                contentWarningEnabled = j.bool("contentWarningEnabled"),
                contentWarningReason = j.optString("contentWarningReason", ""),
                poll = j.optJSONObject("poll")?.let(ComposeDraftPoll::from),
                updatedAt = j.long("updatedAt"),
                emojis = j.optJSONObject("emojis")?.let { m -> m.keys().asSequence().associateWith { m.optString(it) } } ?: emptyMap(),
                goal = j.optJSONObject("goal")?.let(ComposeDraftGoal::from),
            )
        }
    }
}

object DraftStore {
    var drafts by mutableStateOf<List<ComposeDraft>>(emptyList())
        private set
    private var owner: String? = null
    private var loaded = false
    var pendingDraftId: String? = null

    fun all(): List<ComposeDraft> {
        ensureLoaded()
        return drafts
    }

    fun draft(id: String): ComposeDraft? = all().firstOrNull { it.id == id }

    fun latest(contextKey: String): ComposeDraft? = all().filter { it.contextKey == contextKey }.maxByOrNull { it.updatedAt }

    fun save(draft: ComposeDraft) {
        ensureLoaded()
        drafts = (listOf(draft) + drafts.filter { it.id != draft.id }).sortedByDescending { it.updatedAt }
        persist()
    }

    fun delete(id: String) {
        ensureLoaded()
        if (drafts.none { it.id == id }) return
        drafts = drafts.filter { it.id != id }
        persist()
    }

    private fun ensureLoaded() {
        val pubkey = Session.pubkey
        if (loaded && pubkey == owner) return
        loaded = true
        owner = pubkey
        drafts = pubkey?.let(::read) ?: emptyList()
    }

    private fun persist() {
        val file = owner?.let(::file) ?: return
        runCatching {
            file.parentFile?.mkdirs()
            val tmp = File(file.parentFile, "${file.name}.tmp")
            tmp.writeText(JSONArray(drafts.map { it.toJson() }).toString())
            if (!tmp.renameTo(file)) {
                file.delete()
                tmp.renameTo(file)
            }
        }
    }

    private fun read(owner: String): List<ComposeDraft>? {
        val file = file(owner) ?: return null
        if (!file.exists()) return null
        val raw = runCatching { file.readText() }.getOrNull() ?: return null
        return Json.array(raw).mapNotNull(ComposeDraft::from).sortedByDescending { it.updatedAt }
    }

    private fun file(owner: String): File? {
        if (owner.length != 64 || !owner.all { it.isHex() }) return null
        return File(File(App.context.filesDir, "Drafts"), "$owner.json")
    }
}
