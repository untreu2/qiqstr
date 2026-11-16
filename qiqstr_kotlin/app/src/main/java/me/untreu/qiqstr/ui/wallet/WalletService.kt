package me.untreu.qiqstr.ui.wallet

import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.qiqstr.core.cashuGetBalance
import com.qiqstr.core.cashuMeltAll
import com.qiqstr.core.cashuReceiveAndMelt
import com.qiqstr.core.cashuSetAccount
import com.qiqstr.core.nwcGetBalance
import com.qiqstr.core.nwcListTransactions
import com.qiqstr.core.nwcLookupInvoice
import com.qiqstr.core.nwcMakeInvoice
import com.qiqstr.core.nwcPayInvoice
import com.qiqstr.core.parseNwcUri
import com.qiqstr.core.validateNwcUri
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.app.AppTab
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.CoreError
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.SecureStore
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.bool
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.objects
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.core.strings
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.Session
import org.json.JSONObject

data class WalletTransaction(
    val id: String,
    val isIncoming: Boolean,
    val amountSats: Long,
    val feesSats: Long,
    val description: String?,
    val invoice: String?,
    val createdAt: Long,
    val method: String,
    val reportedPaymentHash: String?,
) {
    val paymentHash: String? get() = reportedPaymentHash ?: invoice?.let { Bolt11Codec.decode(it)?.paymentHash }

    companion object {
        fun from(j: JSONObject): WalletTransaction {
            val isIncoming = j.bool("isIncoming") || j.str("type") == "incoming"
            val amount = j.long("amount")
            val description = j.str("description")
            val invoice = j.str("invoice")
            val createdAt = j.long("created_at")
            val hash = j.str("payment_hash")?.lowercase()
            return WalletTransaction(
                id = invoice ?: hash ?: "$createdAt-$amount-$isIncoming-${description ?: ""}",
                isIncoming = isIncoming,
                amountSats = amount,
                feesSats = j.long("fees_paid"),
                description = description,
                invoice = invoice,
                createdAt = createdAt,
                method = "lightning",
                reportedPaymentHash = hash,
            )
        }

        fun placeholder(index: Int): WalletTransaction = from(
            JSONObject()
                .put("type", if (index % 2 == 0) "incoming" else "outgoing")
                .put("amount", 21_000)
                .put("description", "Lightning payment")
                .put("created_at", TimeFormat.now - index * 3600L)
                .put("invoice", "placeholder-$index"),
        )
    }
}

data class PaymentResult(val preimage: String?, val feesSats: Long)

data class CreatedInvoice(
    val invoice: String,
    val paymentHash: String?,
    val amountSats: Long,
    val description: String?,
    val createdAt: Long,
    val expiresAt: Long?,
)

enum class WalletBackendKind { NWC }

interface WalletBackend {
    val kind: WalletBackendKind
    val lightningAddress: String?
    val displayName: String?
    suspend fun balanceSats(): Long
    suspend fun transactions(limit: Int, offset: Int): List<WalletTransaction>
    suspend fun payInvoice(invoice: String): PaymentResult
    suspend fun makeInvoice(amountSats: Long, description: String?): CreatedInvoice
}

class NWCWalletBackend(val uri: String) : WalletBackend {
    override val kind = WalletBackendKind.NWC
    override val lightningAddress: String?
    override val displayName: String?

    init {
        if (!validateNwcUri(uri)) throw WalletError.InvalidConnection()
        val info = Json.obj(parseNwcUri(uri)) ?: JSONObject()
        lightningAddress = info.str("lud16")
        displayName = info.strings("relays").firstOrNull()?.let { runCatching { Uri.parse(it).host }.getOrNull() }
    }

    override suspend fun balanceSats(): Long {
        val json = Json.obj(nwcGetBalance(uri)) ?: JSONObject()
        return json.long("balance") / 1000
    }

    override suspend fun transactions(limit: Int, offset: Int): List<WalletTransaction> {
        val raw = nwcListTransactions(uri, limit.toULong(), offset.toULong())
        return (Json.obj(raw)?.objects("transactions") ?: emptyList()).map(WalletTransaction::from)
    }

    override suspend fun payInvoice(invoice: String): PaymentResult {
        val raw = try {
            nwcPayInvoice(uri, invoice)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            if (!coreErrorMessage(error).contains("timed out", ignoreCase = true)) throw error
            return settledResult(invoice)
        }
        val json = Json.obj(raw) ?: JSONObject()
        return PaymentResult(json.str("preimage"), json.long("fees_paid") / 1000)
    }

    private suspend fun settledResult(invoice: String): PaymentResult {
        for (attempt in 0 until 2) {
            if (attempt > 0) delay(5000)
            val json = Json.obj(runCatching { nwcLookupInvoice(uri, invoice) }.getOrNull()) ?: continue
            when (json.str("state")) {
                "settled" -> return PaymentResult(json.str("preimage"), json.long("fees_paid") / 1000)
                "failed", "expired" -> throw WalletError.PaymentFailed()
            }
        }
        throw WalletError.PaymentPending()
    }

    override suspend fun makeInvoice(amountSats: Long, description: String?): CreatedInvoice {
        val amountMsat = SatsAmount.msat(amountSats) ?: throw WalletError.InvalidAmount()
        val raw = nwcMakeInvoice(uri, amountMsat.toULong(), description)
        val json = Json.obj(raw) ?: JSONObject()
        val invoice = json.str("invoice") ?: throw WalletError.EmptyInvoice()
        val decoded = Bolt11Codec.decode(invoice)
        return CreatedInvoice(
            invoice = invoice,
            paymentHash = json.str("payment_hash") ?: decoded?.paymentHash,
            amountSats = amountSats,
            description = description,
            createdAt = decoded?.createdAt ?: TimeFormat.now,
            expiresAt = decoded?.expiresAt,
        )
    }
}

enum class WalletConnectionState { DISCONNECTED, CONNECTED }

object WalletService {
    const val TRANSACTION_PAGE_SIZE = 20
    const val CALLBACK_SCHEME = "qiqstr"
    const val CALLBACK_HOST = "nwc"
    const val CALLBACK_URL = "$CALLBACK_SCHEME://$CALLBACK_HOST"
    const val DISCLAIMER_ACCEPTED_KEY = "nwc_disclaimer_accepted"
    private const val BALANCE_HIDDEN_KEY = "wallet_balance_hidden"

    var connectionState by mutableStateOf(WalletConnectionState.DISCONNECTED)
        private set
    var backend by mutableStateOf<WalletBackend?>(null)
        private set
    var balanceSats by mutableStateOf<Long?>(null)
        private set
    var balanceError by mutableStateOf<String?>(null)
        private set
    var isRefreshingBalance by mutableStateOf(false)
        private set
    var transactions by mutableStateOf<List<WalletTransaction>>(emptyList())
        private set
    var isLoadingTransactions by mutableStateOf(false)
        private set
    var hasLoadedTransactions by mutableStateOf(false)
        private set
    var canLoadMoreTransactions by mutableStateOf(false)
        private set
    var transactionsError by mutableStateOf<String?>(null)
        private set
    var cashuBalanceSats by mutableLongStateOf(0L)
        private set
    var isRedeemingCashu by mutableStateOf(false)
        private set
    var isPaying by mutableStateOf(false)
        private set
    var lastPaymentAt by mutableStateOf<Long?>(null)
        private set
    var incomingConnectURI by mutableStateOf<String?>(null)
        private set
    var incomingPaymentRequest by mutableStateOf<String?>(null)
        private set
    private var balanceHiddenState by mutableStateOf(Prefs.bool(BALANCE_HIDDEN_KEY))
    var balanceHidden: Boolean
        get() = balanceHiddenState
        set(value) {
            balanceHiddenState = value
            Prefs.set(BALANCE_HIDDEN_KEY, value)
        }

    private var generation = 0

    val isConnected: Boolean get() = connectionState == WalletConnectionState.CONNECTED && backend != null
    val lightningAddress: String? get() = backend?.lightningAddress
    val walletName: String? get() = backend?.displayName

    fun credentialKey(pubkey: String): String = "nwc_uri_$pubkey"

    private fun storageKey(pubkey: String) = credentialKey(pubkey)

    fun reset() {
        generation += 1
        connectionState = WalletConnectionState.DISCONNECTED
        backend = null
        balanceSats = null
        balanceError = null
        isRefreshingBalance = false
        transactions = emptyList()
        isLoadingTransactions = false
        hasLoadedTransactions = false
        canLoadMoreTransactions = false
        transactionsError = null
        cashuBalanceSats = 0
        isRedeemingCashu = false
        isPaying = false
        lastPaymentAt = null
        incomingConnectURI = null
        ZapService.reset()
    }

    suspend fun load() {
        val pubkey = Session.pubkey ?: return
        val uri = SecureStore.get(storageKey(pubkey)) ?: return
        val backend = runCatching { NWCWalletBackend(uri) }.getOrNull() ?: return
        this.backend = backend
        connectionState = WalletConnectionState.CONNECTED
        refresh()
    }

    fun handleIncoming(uri: Uri): Boolean {
        val raw = uri.toString()
        if (isWalletConnectURI(raw)) {
            deliverIncoming(raw)
            return true
        }
        if (uri.scheme?.lowercase() == "lightning") {
            val value = raw.drop("lightning:".length).trim('/', ' ')
            if (value.isEmpty()) return true
            incomingPaymentRequest = runCatching { Uri.decode(value) }.getOrDefault(value)
            Router.selectedTab = AppTab.WALLET
            return true
        }
        if (uri.scheme?.lowercase() != CALLBACK_SCHEME || uri.host?.lowercase() != CALLBACK_HOST) return false
        val value = runCatching { uri.getQueryParameter("value") }.getOrNull()
        if (value != null && isWalletConnectURI(value)) {
            deliverIncoming(value)
        } else {
            Router.selectedTab = AppTab.WALLET
            ToastCenter.show(L("nwcInvalidConnectionString"), ToastStyle.ERROR)
        }
        return true
    }

    fun consumeIncomingConnectURI(): String? = incomingConnectURI.also { incomingConnectURI = null }

    fun consumeIncomingPaymentRequest(): String? = incomingPaymentRequest.also { incomingPaymentRequest = null }

    private fun deliverIncoming(uri: String) {
        incomingConnectURI = uri.trim()
        Router.selectedTab = AppTab.WALLET
    }

    fun isWalletConnectURI(text: String): Boolean {
        val lower = text.trim().lowercase()
        return lower.startsWith("nostr+walletconnect://") || lower.startsWith("nostrwalletconnect://")
    }

    fun validate(uri: String): Boolean = runCatching { validateNwcUri(uri.trim()) }.getOrDefault(false)

    suspend fun connect(uri: String) {
        val pubkey = Session.pubkey ?: throw WalletError.NoAccount()
        val trimmed = uri.trim()
        val backend = NWCWalletBackend(trimmed)
        SecureStore.set(storageKey(pubkey), trimmed)
        Prefs.set(DISCLAIMER_ACCEPTED_KEY, true)
        generation += 1
        this.backend = backend
        connectionState = WalletConnectionState.CONNECTED
        isRefreshingBalance = false
        isLoadingTransactions = false
        canLoadMoreTransactions = false
        balanceError = null
        transactionsError = null
        balanceSats = null
        transactions = emptyList()
        hasLoadedTransactions = false
        refresh()
    }

    fun disconnect() {
        Session.pubkey?.let { SecureStore.set(storageKey(it), null) }
        reset()
    }

    suspend fun refresh() = coroutineScope {
        launch { refreshBalance() }
        launch { loadTransactions() }
        launch { refreshCashuBalance() }
    }

    suspend fun refreshBalance() {
        val backend = backend ?: return
        if (isRefreshingBalance) return
        val generation = generation
        isRefreshingBalance = true
        try {
            val sats = backend.balanceSats()
            if (generation != this.generation) return
            balanceSats = sats
            balanceError = null
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            if (generation != this.generation) return
            balanceError = coreErrorMessage(error)
        } finally {
            if (generation == this.generation) isRefreshingBalance = false
        }
    }

    suspend fun loadTransactions() {
        val backend = backend ?: return
        if (isLoadingTransactions) return
        val generation = generation
        isLoadingTransactions = true
        try {
            val page = backend.transactions(TRANSACTION_PAGE_SIZE, 0)
            if (generation != this.generation) return
            transactions = sorted(page)
            canLoadMoreTransactions = page.size >= TRANSACTION_PAGE_SIZE
            transactionsError = null
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            if (generation != this.generation) return
            transactionsError = coreErrorMessage(error)
        } finally {
            if (generation == this.generation) {
                isLoadingTransactions = false
                hasLoadedTransactions = true
            }
        }
    }

    suspend fun loadMoreTransactions() {
        val backend = backend ?: return
        if (!canLoadMoreTransactions || isLoadingTransactions) return
        val generation = generation
        isLoadingTransactions = true
        try {
            val page = backend.transactions(TRANSACTION_PAGE_SIZE, transactions.size)
            if (generation != this.generation) return
            val known = transactions.map { it.id }.toSet()
            transactions = sorted(transactions + page.filter { it.id !in known })
            canLoadMoreTransactions = page.size >= TRANSACTION_PAGE_SIZE
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            if (generation != this.generation) return
            ToastCenter.error(error)
        } finally {
            if (generation == this.generation) isLoadingTransactions = false
        }
    }

    private fun sorted(list: List<WalletTransaction>) = list.sortedByDescending { it.createdAt }

    fun prepareCashu() {
        val pubkey = Session.pubkey ?: throw WalletError.NoAccount()
        cashuSetAccount(pubkey)
    }

    suspend fun refreshCashuBalance() {
        val generation = generation
        if (runCatching { prepareCashu() }.isFailure) return
        val json = Json.obj(runCatching { cashuGetBalance() }.getOrNull()) ?: return
        if (generation != this.generation) return
        cashuBalanceSats = json.long("total_sats")
    }

    fun resolve(text: String): PaymentRequest? = PaymentRequest.parse(text)

    suspend fun pay(invoice: String, amountSats: Long? = null, comment: String? = null): PaymentResult {
        return when (val request = PaymentRequest.parse(invoice) ?: throw WalletError.Unrecognized()) {
            is PaymentRequest.Bolt11 -> payBolt11(request.raw)
            is PaymentRequest.LightningAddress -> pay(Lnurl.payParams(request.address), amountSats, comment)
            is PaymentRequest.LnurlRequest -> pay(Lnurl.payParams(request.url), amountSats, comment)
            is PaymentRequest.Cashu -> throw WalletError.Unrecognized()
        }
    }

    suspend fun pay(params: LnurlPayParams, amountSats: Long?, comment: String?): PaymentResult {
        val amountMsat = amountSats?.let { SatsAmount.msat(it) } ?: throw WalletError.InvalidAmount()
        val invoice = Lnurl.requestInvoice(params, amountMsat, comment)
        return payBolt11(invoice)
    }

    suspend fun payBolt11(invoice: String): PaymentResult {
        val backend = backend ?: throw WalletError.NotConnected()
        val trimmed = invoice.trim()
        Bolt11Codec.decode(trimmed)?.let { decoded ->
            if (decoded.amountMsat == null) throw WalletError.AmountlessInvoice()
            if (decoded.isExpired) throw WalletError.InvoiceExpired()
        }
        val generation = generation
        isPaying = true
        val result = try {
            backend.payInvoice(trimmed)
        } finally {
            if (generation == this.generation) isPaying = false
        }
        if (generation != this.generation) return result
        lastPaymentAt = System.currentTimeMillis()
        App.scope.launch {
            refreshBalance()
            loadTransactions()
        }
        return result
    }

    suspend fun makeInvoice(amount: Long, description: String?): CreatedInvoice {
        val backend = backend ?: throw WalletError.NotConnected()
        if (amount <= 0) throw WalletError.InvalidAmount()
        val memo = description?.trim()?.ifEmpty { null }
        return backend.makeInvoice(amount, memo)
    }

    suspend fun isInvoicePaid(invoice: CreatedInvoice): Boolean {
        val backend = backend ?: return false
        val page = runCatching { backend.transactions(10, 0) }.getOrNull() ?: return false
        val target = invoice.invoice.lowercase()
        val since = invoice.createdAt - 5
        val paid = page.any { tx ->
            if (!tx.isIncoming) return@any false
            tx.invoice?.lowercase()?.let { return@any it == target }
            val hash = invoice.paymentHash?.lowercase()
            val txHash = tx.paymentHash?.lowercase()
            if (hash != null && txHash != null) return@any hash == txHash
            if (invoice.paymentHash != null || tx.paymentHash != null) return@any false
            tx.amountSats == invoice.amountSats && tx.createdAt >= since
        }
        if (paid) {
            val ids = page.map { it.id }.toSet()
            transactions = sorted(page + transactions.filter { it.id !in ids })
            App.scope.launch { refreshBalance() }
        }
        return paid
    }

    fun decodeCashu(token: String): CashuTokenInfo? = CashuTokenInfo.decode(token)

    suspend fun redeemCashu(token: String): Long {
        if (!isConnected) throw WalletError.NotConnected()
        val info = CashuTokenInfo.decode(token) ?: throw CoreError(L("cashuInvalidToken"))
        isRedeemingCashu = true
        try {
            prepareCashu()
            refreshCashuBalance()
            val balanceBefore = cashuBalanceSats
            return try {
                val target = lightningTarget(info.amountSats, 0)
                prepareCashu()
                val json = Json.obj(cashuReceiveAndMelt(info.token, target)) ?: JSONObject()
                afterCashuMelt()
                json.long("amount_sats")
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                refreshCashuBalance()
                if (cashuBalanceSats <= balanceBefore || lightningAddress != null) throw error
                val melted = meltCashuViaInvoices(1)
                afterCashuMelt()
                melted
            }
        } finally {
            isRedeemingCashu = false
        }
    }

    suspend fun meltAllCashu(): Long {
        if (!isConnected) throw WalletError.NotConnected()
        isRedeemingCashu = true
        try {
            prepareCashu()
            return try {
                val address = lightningAddress
                val melted = if (address != null) {
                    Json.obj(cashuMeltAll(address))?.long("total_sats") ?: 0L
                } else {
                    meltCashuViaInvoices(0)
                }
                afterCashuMelt()
                melted
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                refreshCashuBalance()
                throw error
            }
        } finally {
            isRedeemingCashu = false
        }
    }

    private suspend fun afterCashuMelt() {
        refreshCashuBalance()
        App.scope.launch {
            delay(2000)
            refresh()
        }
    }

    private suspend fun meltCashuViaInvoices(startAttempt: Int): Long {
        var lastError: Exception = WalletError.NothingToMelt()
        for (attempt in startAttempt until 4) {
            refreshCashuBalance()
            if (cashuBalanceSats <= 0) throw lastError
            try {
                val target = lightningTarget(cashuBalanceSats, attempt)
                prepareCashu()
                return Json.obj(cashuMeltAll(target))?.long("total_sats") ?: 0L
            } catch (error: WalletError.CashuTooSmall) {
                throw error
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                lastError = error
            }
        }
        throw lastError
    }

    private suspend fun lightningTarget(sats: Long, attempt: Int): String {
        lightningAddress?.let { return it }
        val percent = longArrayOf(1, 2, 4, 8)[minOf(attempt, 3)]
        val buffer = maxOf(2L shl attempt, (sats * percent + 99) / 100)
        val amount = sats - buffer
        if (amount <= 0) throw WalletError.CashuTooSmall()
        return makeInvoice(amount, L("cashuToken")).invoice
    }
}
