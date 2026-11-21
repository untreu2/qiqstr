package me.untreu.qiqstr.ui.compose

import android.util.Base64
import com.qiqstr.core.signBlossomAuthEvent
import com.qiqstr.core.sha256Hash
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.core.CoreError
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.data.services.RelayConfig
import me.untreu.qiqstr.data.sync.Session
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

data class UploadedMedia(val url: String, val sha256: String, val mimeType: String, val size: Int)

object MediaUploadService {
    private val http: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(120, TimeUnit.SECONDS)
            .readTimeout(120, TimeUnit.SECONDS)
            .callTimeout(600, TimeUnit.SECONDS)
            .build()
    }

    suspend fun upload(bytes: ByteArray, mimeType: String): String = uploadMedia(bytes, mimeType).url

    suspend fun uploadMedia(bytes: ByteArray, mimeType: String, server: String? = null): UploadedMedia {
        val target = server ?: RelayConfig.blossomServer
        Session.requireSigner()
        val hash = withContext(Dispatchers.Default) { sha256Hash(bytes) }
        val auth = signBlossomAuthEvent("Upload $hash", hash, TimeFormat.now + 600)
        val token = Base64.encodeToString(auth.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
        val base = target.replace(Regex("/+$"), "")
        return withContext(Dispatchers.IO) {
            val request = Request.Builder()
                .url("$base/upload")
                .header("Authorization", "Nostr $token")
                .put(bytes.toRequestBody(mimeType.toMediaTypeOrNull()))
                .build()
            val response = runCatching { http.newCall(request).execute() }.getOrElse { throw CoreError(L("mediaUploadFailed")) }
            response.use {
                val body = it.body?.string().orEmpty()
                if (!it.isSuccessful) {
                    val reason = it.header("X-Reason") ?: body.take(200)
                    throw CoreError("${L("mediaUploadFailed")} (${it.code}) $reason".trim())
                }
                val json = Json.obj(body)
                val sha = json?.str("sha256") ?: hash
                val remote = json?.str("url") ?: sha.takeIf { s -> s.isNotEmpty() }?.let { s -> "$base/$s" } ?: throw CoreError(L("mediaUploadFailed"))
                val size = json?.long("size")?.toInt() ?: 0
                UploadedMedia(withExtension(remote, mimeType), sha, mimeType, if (size == 0) bytes.size else size)
            }
        }
    }

    private val extensions = mapOf(
        "image/jpeg" to "jpg", "image/png" to "png", "image/gif" to "gif", "image/webp" to "webp",
        "video/mp4" to "mp4", "video/quicktime" to "mov", "audio/mp4" to "m4a",
    )

    fun withExtension(url: String, mimeType: String): String {
        val ext = extensions[mimeType] ?: return url
        val scheme = url.indexOf("://")
        if (scheme < 0) return url
        val pathStart = url.indexOf('/', scheme + 3)
        if (pathStart < 0) return url
        val pathEnd = url.indexOfAny(charArrayOf('?', '#'), pathStart).let { if (it < 0) url.length else it }
        val path = url.substring(pathStart, pathEnd)
        if (path.endsWith("/")) return url
        val name = path.substringAfterLast('/')
        val dot = name.lastIndexOf('.')
        if (dot > 0 && dot < name.length - 1) return url
        return url.substring(0, pathEnd) + ".$ext" + url.substring(pathEnd)
    }
}
