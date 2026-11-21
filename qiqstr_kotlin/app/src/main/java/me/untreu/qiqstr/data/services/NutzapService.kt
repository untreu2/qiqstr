package me.untreu.qiqstr.data.services

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.qiqstr.core.*
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.*
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.ui.wallet.WalletService
import me.untreu.qiqstr.ui.wallet.ZapError
import org.json.JSONObject

data class NutzapInfo(val mints: List<String>, val relays: List<String>, val lockKey: String) {
    companion object {
        fun from(event: JSONObject): NutzapInfo? {
            val tags = event.tags()
            val mints = tags.filter { it.size > 1 && it[0] == "mint" && it[1].startsWith("https://") && (it.size < 3 || it[2].lowercase() == "sat") }.map { CashuMint.normalized(it[1]) }
            val relays = tags.filter { it.size > 1 && it[0] == "relay" && RelayConfig.isUsableRelayURL(it[1]) }.map { it[1] }
            val key = tags.firstOrNull { it.size > 1 && it[0] == "pubkey" }?.get(1)?.lowercase() ?: return null
            return if (key.length in listOf(64, 66) && key.all { it in "0123456789abcdef" } && mints.isNotEmpty()) NutzapInfo(mints, relays, key) else null
        }
    }
}

object CashuMint {
    val presets = listOf("https://mint.minibits.cash/Bitcoin", "https://mint.coinos.io", "https://mint.lnvoltz.com", "https://mint.macadamia.cash")
    fun normalized(raw: String): String = raw.trim().let { if (it.contains("://")) it else "https://$it" }.trimEnd('/')
    fun isValid(raw: String): Boolean = runCatching { java.net.URI(normalized(raw)).let { it.scheme == "https" && it.host?.contains('.') == true && normalized(raw).none(Char::isWhitespace) } }.getOrDefault(false)
    fun displayName(mint: String): String = runCatching { java.net.URI(mint).let { it.host + it.path.orEmpty().takeIf { p -> p.length > 1 }.orEmpty() } }.getOrDefault(mint)
}

data class SentCashuToken(val token: String, val amountSats: Long, val mint: String, val createdAt: Long) {
    fun toJson() = mapOf("token" to token, "amountSats" to amountSats, "mint" to mint, "createdAt" to createdAt)
    companion object { fun from(j: JSONObject) = SentCashuToken(j.optString("token"), j.long("amountSats"), j.optString("mint"), j.long("createdAt")) }
}

object NutzapService {
    const val infoKind = 10019
    const val nutzapKind = 9321
    const val walletKind = 17375
    const val historyKind = 7376
    var mints by mutableStateOf<List<String>>(emptyList())
        private set
    var isReceiving by mutableStateOf(false)
        private set
    var isLoaded by mutableStateOf(false)
        private set
    var isSaving by mutableStateOf(false)
        private set
    var sentTokens by mutableStateOf<List<SentCashuToken>>(emptyList())
        private set
    var receivedTick by mutableStateOf(0)
        private set
    private var owner: String? = null
    private var generation = 0
    private var lockSecret: String? = null
    private var redeeming = false
    private val infoCache = mutableMapOf<String, Pair<Long, NutzapInfo?>>()
    private val sendLock = Mutex()
    private val outboxLock = Mutex()
    var sendMint: String
        get() = Prefs.string("cashu_send_mint")?.takeIf(CashuMint::isValid) ?: mints.firstOrNull() ?: CashuMint.presets[0]
        set(value) { Prefs.set("cashu_send_mint", CashuMint.normalized(value)) }
    val mintOptions: List<String> get() = (mints + CashuMint.presets).distinct()
    fun reset() { generation++; owner = null; mints = emptyList(); isReceiving = false; isLoaded = false; lockSecret = null; sentTokens = emptyList(); infoCache.clear() }
    suspend fun load() = coroutineScope {
        val me = Session.pubkey ?: return@coroutineScope
        val gen = generation
        if (owner != me) {
            owner = me
            mints = Prefs.stringList("nutzap_mints_$me") ?: emptyList()
            isReceiving = Prefs.bool("nutzap_receiving_$me")
            sentTokens = Json.array(Prefs.string("cashu_sent_tokens_$me")).map(SentCashuToken::from)
        }
        publishOutbox()
        if (!Session.canSign) { isLoaded = true; return@coroutineScope }
        val infos = async { SyncService.fetchReplaceable(infoKind, me) }
        val wallets = async { SyncService.fetchReplaceable(walletKind, me) }
        val info = infos.await().maxByOrNull { it.long("created_at") }?.let(NutzapInfo::from)
        val wallet = wallets.await().maxByOrNull { it.long("created_at") }
        if (gen != generation) return@coroutineScope
        wallet?.let { walletSecret(it, me)?.let { found -> lockSecret = found } }
        if (info != null) {
            isReceiving = runCatching { info.lockKey.takeLast(64).lowercase() == lockKey().takeLast(64).lowercase() }.getOrDefault(false)
            if (isReceiving) mints = info.mints
        }
        persist()
        isLoaded = true
        if (isReceiving) redeemPending()
    }
    private fun walletSecret(event: JSONObject, me: String): String? = runCatching {
        if (!Session.canSign) return null
        val plain = sessionNip44Decrypt(event.optString("content"), me)
        val array = org.json.JSONArray(plain)
        (0 until array.length()).mapNotNull { array.optJSONArray(it)?.let { tag -> (0 until tag.length()).map { index -> tag.optString(index) } } }.firstOrNull { it.size > 1 && it[0] == "privkey" && it[1].length == 64 }?.get(1)?.lowercase()
    }.getOrNull()
    private fun secret(): String = lockSecret ?: run { Session.requireSigner(); sessionNutzapLockSecret() }.also { lockSecret = it }
    private fun lockKey() = getPublicKey(secret())
    suspend fun setReceiving(enabled: Boolean, next: List<String>? = null) {
        if (isSaving) return
        val me = Session.pubkey ?: return
        Session.requireSigner()
        val list = (next ?: mints.ifEmpty { CashuMint.presets.take(2) }).map(CashuMint::normalized).filter(CashuMint::isValid)
        if (enabled && list.isEmpty()) throw CoreError(L("nutzapNeedsMint"))
        isSaving = true
        try {
            if (enabled) publishWalletIfMissing(me, list)
            val lock = lockKey()
            val base = SyncService.latestEditableEvent(infoKind, me, allowingNew = true)
            val kept = base?.tags().orEmpty().filterNot { it.firstOrNull() in listOf("mint", "relay", "pubkey") }
            val tags = if (enabled) (runCatching { getRelayList() }.getOrDefault(RelayConfig.mainRelays)).filter { it.startsWith("wss://") }.take(4).map { listOf("relay", it) } + list.map { listOf("mint", it, "sat") } + listOf(listOf("pubkey", lock)) else emptyList()
            SyncService.publish(signEvent(infoKind.toUShort(), "", tags + kept))
            if (me != Session.pubkey) return
            mints = list
            isReceiving = enabled
            infoCache.remove(me)
            persist()
            if (enabled) App.scope.launch { redeemPending() }
        } finally { isSaving = false }
    }
    private suspend fun publishWalletIfMissing(me: String, mints: List<String>) {
        val existing = SyncService.fetchReplaceable(walletKind, me).maxByOrNull { it.long("created_at") }
        if (existing != null) { walletSecret(existing, me)?.let { lockSecret = it }; return }
        val payload = listOf(listOf("privkey", secret())) + mints.map { listOf("mint", it) }
        SyncService.publish(signEvent(walletKind.toUShort(), sessionNip44Encrypt(Json.string(payload), me), emptyList()))
    }
    suspend fun lookup(mint: String): String {
        WalletService.prepareCashu()
        return Json.obj(cashuMintInfo(CashuMint.normalized(mint)))?.str("name") ?: CashuMint.displayName(mint)
    }
    suspend fun info(pubkey: String): NutzapInfo? {
        infoCache[pubkey]?.takeIf { System.currentTimeMillis() - it.first < 600_000 }?.let { return it.second }
        val info = SyncService.fetchReplaceable(infoKind, pubkey).maxByOrNull { it.long("created_at") }?.let(NutzapInfo::from)
        infoCache[pubkey] = System.currentTimeMillis() to info
        return info
    }
    suspend fun send(pubkey: String, note: Note?, amountSats: Long, comment: String) = sendLock.withLock {
        val me = Session.pubkey ?: throw ZapError.InvalidAmount()
        if (amountSats <= 0) throw ZapError.InvalidAmount()
        Session.requireSigner()
        val info = info(pubkey) ?: throw CoreError(L("nutzapNotSupported"))
        val mint = info.mints.first()
        WalletService.prepareCashu()
        fund(mint, amountSats)
        val proofs = Json.obj(cashuCreateToken(mint, amountSats.toULong(), info.lockKey))?.strings("proofs").orEmpty()
        if (proofs.isEmpty()) throw CoreError(L("nutzapFailed"))
        val tags = proofs.map { listOf("proof", it) } + listOf(listOf("u", mint), listOf("unit", "sat")) + (note?.let { listOf(listOf("e", it.id, "", it.pubkey), listOf("k", it.kind.toString())) } ?: emptyList()) + listOf(listOf("p", pubkey))
        val event = signEvent(nutzapKind.toUShort(), comment.trim(), tags)
        val relays = (info.relays + RelayConfig.mainRelays).distinct()
        outboxLock.withLock { Prefs.setStringList("nutzap_outbox_$me", outbox(me) + Json.string(mapOf("event" to event, "relays" to relays))) }
        publishOutbox()
        WalletService.refresh()
    }
    suspend fun createToken(mint: String, amountSats: Long): SentCashuToken = sendLock.withLock {
        val me = Session.pubkey ?: throw ZapError.InvalidAmount()
        if (amountSats <= 0) throw ZapError.InvalidAmount()
        val url = CashuMint.normalized(mint)
        WalletService.prepareCashu()
        fund(url, amountSats)
        val token = Json.obj(cashuCreateToken(url, amountSats.toULong(), null))?.str("token") ?: throw CoreError(L("cashuSendFailed"))
        val sent = SentCashuToken(token, amountSats, url, TimeFormat.now)
        if (Session.pubkey == me) {
            sentTokens = (listOf(sent) + sentTokens).take(30)
            Prefs.set("cashu_sent_tokens_$me", Json.string(sentTokens.map(SentCashuToken::toJson)))
        }
        WalletService.refresh()
        sent
    }
    fun forget(token: SentCashuToken) {
        val me = owner ?: return
        sentTokens = sentTokens.filterNot { it.token == token.token }
        Prefs.set("cashu_sent_tokens_$me", Json.string(sentTokens.map(SentCashuToken::toJson)))
    }
    private suspend fun fund(mint: String, amountSats: Long) {
        val quote = Json.obj(cashuFundQuote(mint, amountSats.toULong())) ?: throw CoreError(L("cashuSendFailed"))
        if (!quote.bool("needs_payment")) return
        val invoice = quote.str("invoice") ?: throw CoreError(L("cashuSendFailed"))
        val id = quote.str("quote_id") ?: throw CoreError(L("cashuSendFailed"))
        if (!WalletService.isConnected) throw ZapError.NoWallet()
        WalletService.payBolt11(invoice)
        var lastError: Throwable = CoreError(L("cashuSendFailed"))
        repeat(12) { attempt ->
            try { cashuFundComplete(mint, id); return } catch (error: Exception) { lastError = error; delay(if (attempt < 4) 800 else 2000) }
        }
        throw lastError
    }
    private fun outbox(me: String) = Prefs.stringList("nutzap_outbox_$me") ?: emptyList()
    private suspend fun publishOutbox() = outboxLock.withLock {
        val me = Session.pubkey ?: return@withLock
        val remaining = mutableListOf<String>()
        for (entry in outbox(me)) {
            val obj = Json.obj(entry) ?: continue
            val event = obj.str("event") ?: continue
            val targeted = runCatching { SyncService.publish(event, obj.strings("relays")) }.isSuccess
            val general = runCatching { SyncService.publish(event) }.isSuccess
            if (!targeted && !general) remaining.add(entry)
        }
        Prefs.setStringList("nutzap_outbox_$me", remaining)
    }
    suspend fun redeemPending() {
        val me = Session.pubkey ?: return
        if (!Session.canSign) return
        if (!isReceiving || redeeming) return
        val unlock = runCatching { secret() }.getOrNull() ?: return
        redeeming = true
        val gen = generation
        try {
            val done = (Prefs.stringList("nutzap_redeemed_$me") ?: emptyList()).toMutableSet()
            val since = (Prefs.long("nutzap_checked_$me") - 172800).coerceAtLeast(0)
            val filter = mutableMapOf<String, Any?>("kinds" to listOf(nutzapKind), "#p" to listOf(me), "limit" to 200)
            if (since > 0) filter["since"] = since
            val events = SyncService.fetchEvents(filter, 8)
            if (gen != generation || runCatching { WalletService.prepareCashu() }.isFailure) return
            var received = 0L
            for (event in events.sortedBy { it.long("created_at") }) {
                if (gen != generation) return
                val id = event.str("id") ?: continue
                val sender = event.str("pubkey") ?: continue
                if (id in done || sender in Session.mutedPubkeys) continue
                val tags = event.tags()
                val proofs = tags.filter { it.size > 1 && it[0] == "proof" }.map { it[1] }
                val mint = tags.firstOrNull { it.size > 1 && it[0] == "u" }?.get(1)?.let(CashuMint::normalized)
                if (mint == null || mint !in mints || proofs.isEmpty()) { done.add(id); continue }
                try {
                    val amount = Json.obj(cashuRedeemProofs(mint, proofs, unlock, WalletService.lightningAddress ?: ""))?.long("received_sats") ?: 0
                    received += amount
                    done.add(id)
                    runCatching {
                        val payload = listOf(listOf("direction", "in"), listOf("amount", amount.toString()), listOf("unit", "sat"))
                        SyncService.publish(signEvent(historyKind.toUShort(), sessionNip44Encrypt(Json.string(payload), me), listOf(listOf("e", id, "", "redeemed"), listOf("p", sender))))
                    }
                } catch (error: Exception) {
                    val message = coreErrorMessage(error).lowercase()
                    if (listOf("spent", "invalid", "unlock").any { message.contains(it) }) done.add(id)
                }
            }
            if (gen != generation) return
            Prefs.setStringList("nutzap_redeemed_$me", done.toList().takeLast(2000))
            Prefs.set("nutzap_checked_$me", TimeFormat.now)
            if (received > 0) { receivedTick++; ToastCenter.show(L("nutzapReceived", "sats" to Sats.format(received)), ToastStyle.SUCCESS); WalletService.refresh() }
        } finally { redeeming = false }
    }
    private fun persist() { owner?.let { Prefs.setStringList("nutzap_mints_$it", mints); Prefs.set("nutzap_receiving_$it", isReceiving) } }
}
