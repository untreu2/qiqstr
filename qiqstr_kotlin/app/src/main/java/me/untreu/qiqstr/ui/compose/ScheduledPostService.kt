package me.untreu.qiqstr.ui.compose

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.File
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.data.bridge.isHex
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SessionPhase
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.ui.settings.BackgroundRefresh
import org.json.JSONArray
import org.json.JSONObject

data class ScheduledPost(val draft: ComposeDraft, val publishAt: Long, val lastError: String? = null) {
    val id: String get() = draft.id

    fun toJson(): JSONObject = JSONObject().apply {
        put("draft", draft.toJson())
        put("publishAt", publishAt)
        lastError?.let { put("lastError", it) }
    }

    companion object {
        fun from(j: JSONObject): ScheduledPost? {
            val draft = j.optJSONObject("draft")?.let(ComposeDraft::from) ?: return null
            return ScheduledPost(draft, j.long("publishAt"), j.str("lastError"))
        }
    }
}

object ScheduledPostService {
    private const val RETRY_SECONDS = 60L

    var posts by mutableStateOf<List<ScheduledPost>>(emptyList())
        private set
    private var owner: String? = null
    private var timer: Job? = null
    private var publishing = false
    private var pendingEdit: ScheduledPost? = null

    fun hasPending(pubkey: String?): Boolean = pubkey?.let(::file)?.exists() == true

    val nextDue: Long? get() = all().minOfOrNull { it.publishAt }

    val nextAttempt: Long?
        get() {
            val retry = TimeFormat.now + RETRY_SECONDS
            return all().minOfOrNull { if (it.lastError == null) it.publishAt else maxOf(it.publishAt, retry) }
        }

    fun all(): List<ScheduledPost> {
        ensureLoaded()
        return posts
    }

    fun reset() {
        timer?.cancel()
        timer = null
        owner = null
        posts = emptyList()
        pendingEdit = null
    }

    fun start() {
        ensureLoaded()
        restartTimer()
        BackgroundRefresh.schedule()
        App.scope.launch { publishDue() }
    }

    fun schedule(draft: ComposeDraft, at: Long) {
        ensureLoaded()
        posts = (posts.filter { it.id != draft.id } + ScheduledPost(draft, at)).sortedBy { it.publishAt }
        persist()
        restartTimer()
        BackgroundRefresh.schedule()
    }

    fun cancel(id: String) {
        ensureLoaded()
        if (posts.none { it.id == id }) return
        posts = posts.filter { it.id != id }
        persist()
        restartTimer()
        BackgroundRefresh.schedule()
    }

    fun contains(id: String): Boolean = all().any { it.id == id }

    fun edit(post: ScheduledPost) {
        pendingEdit = post
    }

    fun takePendingEdit(): ScheduledPost? {
        val post = pendingEdit
        pendingEdit = null
        return post
    }

    suspend fun publishDue() {
        if (withContext(NonCancellable) { publishDuePosts() }) {
            restartTimer()
            BackgroundRefresh.schedule()
        }
    }

    private suspend fun publishDuePosts(): Boolean {
        ensureLoaded()
        val account = owner ?: return false
        if (publishing || Session.phase != SessionPhase.Ready || !Session.canSign || Session.pubkey != account) return false
        publishing = true
        try {
            val due = posts.filter { it.publishAt <= TimeFormat.now }
            if (due.isEmpty() || !SyncService.hasConnectedRelays()) return false
            for (post in due) {
                if (Session.pubkey != account || owner != account) return false
                val failure = runCatching { ComposePublisher.publish(post.draft) }.exceptionOrNull()
                if (owner != account) {
                    if (failure == null) write(account, read(account).orEmpty().filter { it.id != post.id })
                    return false
                }
                if (failure == null) {
                    posts = posts.filter { it.id != post.id }
                    ToastCenter.show(L("feedScheduledPosted"), ToastStyle.SUCCESS)
                } else {
                    posts = posts.map { if (it.id == post.id) it.copy(lastError = coreErrorMessage(failure)) else it }
                }
                persist()
            }
            return true
        } finally {
            publishing = false
        }
    }

    private fun restartTimer() {
        timer?.cancel()
        val next = nextAttempt ?: return
        val wait = maxOf(1, next - TimeFormat.now)
        timer = App.scope.launch {
            delay(wait * 1000)
            publishDue()
            if (!isActive || posts.none { it.publishAt <= TimeFormat.now }) return@launch
            delay(RETRY_SECONDS * 1000)
            restartTimer()
        }
    }

    private fun ensureLoaded() {
        val pubkey = Session.pubkey
        if (pubkey == owner) return
        owner = pubkey
        posts = pubkey?.let(::read) ?: emptyList()
    }

    private fun persist() {
        owner?.let { write(it, posts) }
    }

    private fun write(owner: String, posts: List<ScheduledPost>) {
        val file = file(owner) ?: return
        if (posts.isEmpty()) {
            file.delete()
            return
        }
        runCatching {
            file.parentFile?.mkdirs()
            val tmp = File(file.parentFile, "${file.name}.tmp")
            tmp.writeText(JSONArray(posts.map { it.toJson() }).toString())
            if (!tmp.renameTo(file)) {
                file.delete()
                tmp.renameTo(file)
            }
        }
    }

    private fun read(owner: String): List<ScheduledPost>? {
        val file = file(owner) ?: return null
        if (!file.exists()) return null
        val raw = runCatching { file.readText() }.getOrNull() ?: return null
        return Json.array(raw).mapNotNull(ScheduledPost::from).sortedBy { it.publishAt }
    }

    private fun file(owner: String): File? {
        if (owner.length != 64 || !owner.all { it.isHex() }) return null
        return File(File(App.context.filesDir, "Scheduled"), "$owner.json")
    }
}
