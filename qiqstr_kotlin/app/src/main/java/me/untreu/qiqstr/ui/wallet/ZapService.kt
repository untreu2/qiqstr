package me.untreu.qiqstr.ui.wallet

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.qiqstr.core.createZapRequestEvent
import com.qiqstr.core.dbGetProfile
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.data.services.RelayConfig
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.domain.Profile
import okhttp3.HttpUrl

sealed class ZapError(private val key: String) : Exception() {
    override val message: String get() = L(key)

    class NoWallet : ZapError("pleaseConnectWalletFirst")
    class NoAccount : ZapError("walletNoAccount")
    class NoLightningAddress : ZapError("userNoLightningAddress")
    class ZapsNotSupported : ZapError("zapNotSupported")
    class InvalidAmount : ZapError("enterValidAmount")
    class InProgress : ZapError("zapInProgress")
}

sealed interface QuickZapResult {
    data class Zapped(val sats: Long) : QuickZapResult
    object NeedsSheet : QuickZapResult
    data class Failed(val message: String) : QuickZapResult
}

data class ZapFailure(
    val note: Note,
    val amountSats: Long,
    val message: String,
    val mayHaveSettled: Boolean = false,
    val id: String = UUID.randomUUID().toString(),
)

data class ZapRecipient(
    val pubkey: String,
    val name: String,
    val lightningAddress: String?,
    val lnurl: HttpUrl?,
)

object ZapService {
    val presetAmounts = listOf(21L, 100L, 500L, 1000L, 5000L, 10000L)
    const val ONE_TAP_KEY = "one_tap_zap"
    const val DEFAULT_AMOUNT_KEY = "default_zap_amount"
    const val QUICK_ZAP_LIMIT = 5_000L
    const val LAST_AMOUNT_KEY = "last_zap_amount"

    private var defaultAmountState by mutableStateOf(Prefs.long(DEFAULT_AMOUNT_KEY))
    var defaultAmount: Long
        get() = defaultAmountState.takeIf { it > 0 } ?: 21L
        set(value) {
            defaultAmountState = value
            Prefs.set(DEFAULT_AMOUNT_KEY, value)
        }

    var lastAmount: Long?
        get() = Prefs.long(LAST_AMOUNT_KEY).takeIf { it > 0 }
        set(value) {
            if (value == null) Prefs.remove(LAST_AMOUNT_KEY) else Prefs.set(LAST_AMOUNT_KEY, value)
        }

    private var oneTapState by mutableStateOf(Prefs.bool(ONE_TAP_KEY))
    var isOneTapEnabled: Boolean
        get() = oneTapState
        set(value) {
            oneTapState = value
            Prefs.set(ONE_TAP_KEY, value)
        }

    val pendingSats = mutableStateMapOf<String, Long>()
    val zappedSats = mutableStateMapOf<String, Long>()
    private val zappedIds = mutableStateMapOf<String, Boolean>()
    val zappedNoteIds: Set<String> get() = zappedIds.keys
    var failure by mutableStateOf<ZapFailure?>(null)
        private set
    var successTick by mutableIntStateOf(0)
        private set
    var failureTick by mutableIntStateOf(0)
        private set
    private var failureHosts = 0

    val canZap: Boolean get() = WalletService.isConnected
    val prefersQuickZap: Boolean get() = canZap && isOneTapEnabled

    fun isPending(noteId: String): Boolean = pendingSats.containsKey(noteId)
    fun optimisticSats(noteId: String): Long = zappedSats[noteId] ?: 0L
    fun hasZapped(noteId: String): Boolean = zappedIds.containsKey(noteId)

    fun reset() {
        pendingSats.clear()
        zappedSats.clear()
        zappedIds.clear()
        failure = null
    }

    suspend fun quickZap(note: Note): QuickZapResult {
        if (!prefersQuickZap) return QuickZapResult.NeedsSheet
        return quickZap(note, defaultAmount)
    }

    suspend fun retry(failure: ZapFailure): QuickZapResult {
        if (this.failure?.id == failure.id) this.failure = null
        if (!canZap || failure.mayHaveSettled) return QuickZapResult.NeedsSheet
        return quickZap(failure.note, failure.amountSats)
    }

    fun dismissFailure() { failure = null }

    fun registerFailureHost() { failureHosts += 1 }
    fun unregisterFailureHost() { failureHosts = maxOf(0, failureHosts - 1) }

    private suspend fun quickZap(note: Note, amountSats: Long): QuickZapResult {
        if (isPending(note.id)) return QuickZapResult.NeedsSheet
        return try {
            zap(note, note.pubkey, amountSats, "")
            successTick += 1
            QuickZapResult.Zapped(amountSats)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            val message = coreErrorMessage(error)
            failureTick += 1
            failure = ZapFailure(note, amountSats, message, mayHaveSettled = error is WalletError.PaymentPending)
            if (failureHosts == 0) ToastCenter.show("${L("failedToZap")}: $message", ToastStyle.ERROR)
            QuickZapResult.Failed(message)
        }
    }

    suspend fun recipient(pubkey: String): ZapRecipient {
        if (ProfileCache.profile(pubkey) == null) ProfileCache.refresh(pubkey)
        var raw = Json.obj(runCatching { dbGetProfile(pubkey) }.getOrNull())
        if (ProfileCache.profile(pubkey)?.lud16.isNullOrEmpty() && raw?.str("lud06") == null) {
            SyncService.syncProfile(pubkey, force = true)
            ProfileCache.refresh(pubkey)
            raw = Json.obj(runCatching { dbGetProfile(pubkey) }.getOrNull())
        }
        val profile = ProfileCache.profile(pubkey)
        val address = (profile?.lud16?.ifEmpty { null } ?: raw?.str("lud16"))?.trim()?.ifEmpty { null }
        val lud06 = raw?.str("lud06") ?: address?.takeIf { it.lowercase().startsWith("lnurl1") }
        return ZapRecipient(
            pubkey = pubkey,
            name = profile?.bestName ?: Profile.shortNpub(pubkey),
            lightningAddress = address?.takeIf { Lnurl.isLightningAddress(it) }?.lowercase(),
            lnurl = lud06?.let { Lnurl.decode(it.lowercase()) },
        )
    }

    suspend fun zap(note: Note?, pubkey: String, amountSats: Long, comment: String) {
        if (!canZap) throw ZapError.NoWallet()
        val amountMsat = SatsAmount.msat(amountSats) ?: throw ZapError.InvalidAmount()
        if (note != null) {
            if (pendingSats.containsKey(note.id)) throw ZapError.InProgress()
            pendingSats[note.id] = amountSats
        }
        try {
            val privateKey = Session.requireSigner()
            val recipient = recipient(pubkey)
            val address = recipient.lightningAddress
            val url = recipient.lnurl
            val params = when {
                address != null -> Lnurl.payParams(address).also { ZapperDirectory.record(pubkey, address, it) }
                url != null -> Lnurl.payParams(url)
                else -> throw ZapError.NoLightningAddress()
            }
            val nostrPubkey = params.nostrPubkey
            if (!params.allowsNostr || nostrPubkey.isNullOrEmpty()) throw ZapError.ZapsNotSupported()
            val tags = mutableListOf(
                listOf("relays") + RelayConfig.mainRelays,
                listOf("amount", amountMsat.toString()),
                listOf("lnurl", params.lnurl),
                listOf("p", pubkey),
            )
            if (note != null) {
                tags.add(listOf("e", note.id))
                tags.add(listOf("k", "1"))
            }
            val zapRequest = createZapRequestEvent(tags, comment.trim(), privateKey)
            val invoice = Lnurl.requestInvoice(params, amountMsat, zapRequest = zapRequest)
            WalletService.payBolt11(invoice)
            if (note != null) {
                zappedSats[note.id] = (zappedSats[note.id] ?: 0L) + amountSats
                zappedIds[note.id] = true
                scheduleReceiptSync(note.id)
            }
        } finally {
            if (note != null) pendingSats.remove(note.id)
        }
    }

    private fun scheduleReceiptSync(noteId: String) {
        App.scope.launch {
            for (seconds in listOf(3L, 8L)) {
                delay(seconds * 1000)
                runCatching { SyncService.syncInteractions(listOf(noteId)) }
                if (seconds == 8L) zappedSats.remove(noteId)
                DataBus.interactionsChanged()
            }
        }
    }
}
