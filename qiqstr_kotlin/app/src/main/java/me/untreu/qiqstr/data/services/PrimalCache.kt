package me.untreu.qiqstr.data.services

import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.withTimeoutOrNull
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.text
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject

object PrimalCache {
    val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.SECONDS)
            .build()
    }

    suspend fun request(name: String, args: Map<String, Any?>, timeout: Int): List<JSONObject> {
        val subscription = "qx_${UUID.randomUUID().toString().take(8)}"
        val request = listOf("REQ", subscription, mapOf("cache" to listOf(name, args)))
        return relayRequest(RelayConfig.primalCacheUrl, subscription, request, timeout, stopOnNotice = true)
    }

    suspend fun relayRequest(
        url: String,
        subscription: String,
        request: List<Any?>,
        timeout: Int,
        stopOnNotice: Boolean = false,
        limit: Int = Int.MAX_VALUE,
    ): List<JSONObject> {
        val frames = Channel<String>(Channel.UNLIMITED)
        val payload = Json.string(request)
        val socket = runCatching {
            client.newWebSocket(Request.Builder().url(url).build(), object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    if (!webSocket.send(payload)) frames.close()
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    frames.trySend(text)
                }

                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    frames.close()
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    frames.close()
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    frames.close()
                }
            })
        }.getOrNull() ?: return emptyList()
        val events = mutableListOf<JSONObject>()
        try {
            withTimeoutOrNull(timeout * 1000L) {
                for (raw in frames) {
                    val frame = Json.any(raw) as? JSONArray ?: continue
                    val type = frame.opt(0) as? String ?: continue
                    if (type == "EOSE" || type == "CLOSED" || (stopOnNotice && type == "NOTICE")) break
                    if (type == "EVENT" && frame.length() >= 3) {
                        frame.optJSONObject(2)?.let(events::add)
                        if (events.size >= limit) break
                    }
                }
            }
        } finally {
            runCatching { socket.send(Json.string(listOf("CLOSE", subscription))) }
            runCatching { socket.close(1000, null) }
            frames.close()
        }
        return events
    }

    private fun meta(events: List<JSONObject>): JSONObject? =
        events.firstOrNull { it.int("kind") == 10000113 }?.let { Json.obj(it.text("content")) }

    fun order(events: List<JSONObject>): List<String> {
        val elements = meta(events)?.optJSONArray("elements") ?: return emptyList()
        return (0 until elements.length()).mapNotNull { elements.opt(it) as? String }
    }

    fun page(events: List<JSONObject>): Pair<Long, Long>? {
        val info = meta(events) ?: return null
        return info.long("since") to info.long("until")
    }

    fun signed(events: List<JSONObject>, kinds: Set<Int>): List<JSONObject> =
        events.filter { it.int("kind") in kinds && it.str("id") != null && it.str("sig") != null }

    fun content(events: List<JSONObject>, kind: Int): Any? =
        events.firstOrNull { it.int("kind") == kind }?.let { Json.any(it.text("content")) }

    fun contents(events: List<JSONObject>, kind: Int): List<JSONObject> =
        events.filter { it.int("kind") == kind }.mapNotNull { Json.obj(it.text("content")) }
}
