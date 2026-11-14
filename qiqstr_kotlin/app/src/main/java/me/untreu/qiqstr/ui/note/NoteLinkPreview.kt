package me.untreu.qiqstr.ui.note

import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.net.URI
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.components.RemoteImage
import okhttp3.OkHttpClient
import okhttp3.Request

@Immutable
data class NoteLinkMetadata(val url: String, val title: String, val summary: String?, val image: String?, val site: String)

object NoteLinkPreviewService {
    private val cache = HashMap<String, NoteLinkMetadata>()
    private val misses = HashSet<String>()
    private val inflight = HashMap<String, CompletableDeferred<NoteLinkMetadata?>>()
    private val lock = Mutex()
    private val client by lazy {
        OkHttpClient.Builder()
            .connectTimeout(8, TimeUnit.SECONDS)
            .readTimeout(8, TimeUnit.SECONDS)
            .callTimeout(12, TimeUnit.SECONDS)
            .build()
    }
    private const val USER_AGENT = "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"

    suspend fun cached(url: String): NoteLinkMetadata? = lock.withLock { cache[url] }

    suspend fun metadata(url: String): NoteLinkMetadata? {
        val (deferred, owner) = lock.withLock {
            cache[url]?.let { return it }
            if (url in misses) return null
            inflight[url]?.let { return@withLock it to false }
            val created = CompletableDeferred<NoteLinkMetadata?>()
            inflight[url] = created
            created to true
        }
        if (!owner) return deferred.await()
        val result = runCatching { fetch(url) }.getOrNull()
        lock.withLock {
            inflight.remove(url)
            if (result != null) cache[url] = result else misses.add(url)
        }
        deferred.complete(result)
        return result
    }

    private suspend fun fetch(string: String): NoteLinkMetadata? = withContext(Dispatchers.IO) {
        val uri = runCatching { URI(string) }.getOrNull() ?: return@withContext null
        if (uri.scheme?.startsWith("http") != true) return@withContext null
        val request = Request.Builder().url(string).header("User-Agent", USER_AGENT).header("Accept", "text/html").build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) return@withContext null
            val body = response.body ?: return@withContext null
            val mime = body.contentType()?.let { "${it.type}/${it.subtype}" }
            if (mime != null && !mime.contains("html")) return@withContext null
            val source = body.source()
            source.request(400_000)
            val bytes = source.buffer.let { buffer -> buffer.readByteArray(minOf(buffer.size, 400_000)) }
            val html = String(bytes, Charsets.UTF_8)
            val meta = metaTags(html)
            val title = meta["og:title"] ?: meta["twitter:title"] ?: titleTag(html)
            if (title.isNullOrEmpty()) return@withContext null
            var image = meta["og:image"] ?: meta["og:image:url"] ?: meta["twitter:image"]
            image = image?.let { raw -> runCatching { uri.resolve(raw).toString() }.getOrDefault(raw) }
            val site = meta["og:site_name"] ?: uri.host?.replace("www.", "") ?: ""
            NoteLinkMetadata(
                url = string,
                title = decode(title),
                summary = (meta["og:description"] ?: meta["description"] ?: meta["twitter:description"])?.let(::decode),
                image = image,
                site = decode(site),
            )
        }
    }

    private val tagRegex = Regex("""<meta\s[^>]*>""", RegexOption.IGNORE_CASE)
    private val attrRegex = Regex("""(property|name|content)\s*=\s*("([^"]*)"|'([^']*)')""", RegexOption.IGNORE_CASE)
    private val titleRegex = Regex("""<title[^>]*>([^<]*)</title>""", RegexOption.IGNORE_CASE)

    private fun metaTags(html: String): Map<String, String> {
        val result = HashMap<String, String>()
        for (match in tagRegex.findAll(html)) {
            var key: String? = null
            var content: String? = null
            for (attr in attrRegex.findAll(match.value)) {
                val name = attr.groupValues[1].lowercase()
                val value = attr.groups[3]?.value ?: attr.groups[4]?.value ?: ""
                if (name == "content") content = value else key = value.lowercase()
            }
            if (key != null && !content.isNullOrEmpty() && !result.containsKey(key)) result[key] = content
        }
        return result
    }

    private fun titleTag(html: String): String? = titleRegex.find(html)?.groupValues?.get(1)?.trim()

    private fun decode(s: String): String {
        var out = s
        val entities = mapOf("&amp;" to "&", "&quot;" to "\"", "&#39;" to "'", "&#x27;" to "'", "&apos;" to "'", "&lt;" to "<", "&gt;" to ">", "&nbsp;" to " ")
        for ((k, v) in entities) out = out.replace(k, v)
        return out.trim()
    }
}

@Composable
fun NoteLinkPreview(url: String, modifier: Modifier = Modifier) {
    var metadata by remember(url) { mutableStateOf<NoteLinkMetadata?>(null) }
    LaunchedEffect(url) {
        NoteLinkPreviewService.cached(url)?.let { metadata = it; return@LaunchedEffect }
        metadata = NoteLinkPreviewService.metadata(url)
    }
    val m = metadata ?: return
    val shape = RoundedCornerShape(16.dp)
    Surface(
        onClick = { Router.open(Uri.parse(url)) },
        shape = shape,
        color = AppColors.inputFill,
        border = BorderStroke(0.5.dp, AppColors.border),
        modifier = modifier.fillMaxWidth().testTag("note-link-preview"),
    ) {
        Column {
            m.image?.let { RemoteImage(it, Modifier.fillMaxWidth().height(170.dp).background(AppColors.tile)) }
            Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(m.site, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = AppColors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(m.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = AppColors.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                m.summary?.takeIf { it.isNotEmpty() }?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}
