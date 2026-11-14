package me.untreu.qiqstr.ui.wallet

import com.qiqstr.core.dbGetProfile
import com.qiqstr.core.setKnownZappers
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.data.bridge.isHex
import me.untreu.qiqstr.data.sync.DataBus
import org.json.JSONObject

object ZapperDirectory {
    private data class Entry(val address: String, val zapper: String, val checkedAt: Double)

    private const val STORE_KEY = "zapper_directory"
    private const val LIFETIME_SECONDS = 3 * 86_400.0
    private const val LIMIT = 500
    private val entries = HashMap<String, Entry>()
    private val inFlight = HashSet<String>()
    private var didLoad = false

    private val now: Double get() = System.currentTimeMillis() / 1000.0

    fun prepare() {
        loadIfNeeded()
        push()
    }

    fun record(pubkey: String, address: String, params: LnurlPayParams) {
        loadIfNeeded()
        store(pubkey.lowercase(), address, zapper(params))
    }

    suspend fun verify(pubkey: String) {
        loadIfNeeded()
        val key = pubkey.lowercase()
        if (key.isEmpty() || key in inFlight) return
        val address = address(key) ?: return
        val entry = entries[key]
        if (entry != null && entry.address == address && now - entry.checkedAt < LIFETIME_SECONDS) return
        inFlight.add(key)
        try {
            val params = runCatching {
                when {
                    Lnurl.isLightningAddress(address) -> Lnurl.payParams(address)
                    else -> Lnurl.decode(address)?.let { Lnurl.payParams(it) }
                }
            }.getOrNull() ?: return
            store(key, address, zapper(params))
        } finally {
            inFlight.remove(key)
        }
    }

    fun reset() {
        inFlight.clear()
    }

    private fun store(pubkey: String, address: String, zapper: String) {
        val previous = entries[pubkey]?.zapper
        entries[pubkey] = Entry(address, zapper, now)
        if (entries.size > LIMIT) {
            entries.entries.sortedBy { it.value.checkedAt }.take(entries.size - LIMIT).map { it.key }.forEach { entries.remove(it) }
        }
        val json = JSONObject()
        entries.forEach { (key, value) ->
            json.put(key, JSONObject().put("address", value.address).put("zapper", value.zapper).put("checkedAt", value.checkedAt))
        }
        Prefs.set(STORE_KEY, json.toString())
        if (previous == zapper) return
        push()
        DataBus.interactionsChanged()
        DataBus.notificationsChanged()
    }

    private fun loadIfNeeded() {
        if (didLoad) return
        didLoad = true
        val json = Json.obj(Prefs.string(STORE_KEY)) ?: return
        for (key in json.keys()) {
            val value = json.optJSONObject(key) ?: continue
            entries[key] = Entry(value.optString("address"), value.optString("zapper"), value.optDouble("checkedAt", 0.0))
        }
    }

    private fun push() {
        runCatching { setKnownZappers(Json.string(entries.mapValues { it.value.zapper })) }
    }

    private fun zapper(params: LnurlPayParams): String {
        val key = params.nostrPubkey?.lowercase()
        if (!params.allowsNostr || key == null || key.length != 64 || !key.all { it.isHex() }) return ""
        return key
    }

    private suspend fun address(pubkey: String): String? {
        val raw = Json.obj(runCatching { dbGetProfile(pubkey) }.getOrNull())
        val lud16 = raw?.str("lud16")?.trim()?.lowercase() ?: ""
        if (Lnurl.isLightningAddress(lud16)) return lud16
        val lud06 = (raw?.str("lud06") ?: lud16).trim().lowercase()
        return if (lud06.startsWith("lnurl1")) lud06 else null
    }
}
