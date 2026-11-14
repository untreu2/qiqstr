package me.untreu.qiqstr.ui.wallet

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.core.AppLanguage
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.Prefs
import okhttp3.OkHttpClient
import okhttp3.Request

object BitcoinPriceService {
    const val SHOW_FIAT_KEY = "wallet_show_fiat"
    val supportedCurrencies = setOf("USD", "EUR", "GBP", "CAD", "CHF", "AUD", "JPY")
    private const val CACHE_KEY = "btc_prices"
    private const val CACHE_DATE_KEY = "btc_prices_at"
    private const val MAX_AGE_MS = 600_000L
    private const val ENDPOINT = "https://mempool.space/api/v1/prices"

    private val client by lazy {
        OkHttpClient.Builder().callTimeout(10, TimeUnit.SECONDS).build()
    }

    var prices by mutableStateOf(loadCached())
        private set
    private var fetchedAt: Long? = Prefs.long(CACHE_DATE_KEY).takeIf { it > 0 }
    private var isFetching = false

    private var showFiatState by mutableStateOf(Prefs.bool(SHOW_FIAT_KEY, true))
    var isEnabled: Boolean
        get() = showFiatState
        set(value) {
            showFiatState = value
            Prefs.set(SHOW_FIAT_KEY, value)
        }

    private fun loadCached(): Map<String, Double> {
        val json = Json.obj(Prefs.string(CACHE_KEY)) ?: return emptyMap()
        return json.keys().asSequence().mapNotNull { key -> (json.opt(key) as? Number)?.let { key to it.toDouble() } }.toMap()
    }

    val currency: String
        get() {
            val code = runCatching { Currency.getInstance(Locale.getDefault()).currencyCode.uppercase() }.getOrDefault("USD")
            return if (code in supportedCurrencies) code else "USD"
        }

    val isStale: Boolean get() = fetchedAt?.let { System.currentTimeMillis() - it > MAX_AGE_MS } ?: true

    suspend fun refreshIfNeeded() {
        if (!isEnabled || !isStale || isFetching) return
        isFetching = true
        try {
            val body = withContext(Dispatchers.IO) {
                runCatching {
                    client.newCall(Request.Builder().url(ENDPOINT).build()).execute().use { if (it.code == 200) it.body?.string() else null }
                }.getOrNull()
            } ?: return
            val json = Json.obj(body) ?: return
            val parsed = HashMap<String, Double>()
            for (key in json.keys()) {
                if (key !in supportedCurrencies) continue
                val value = (json.opt(key) as? Number)?.toDouble() ?: continue
                if (value > 0) parsed[key] = value
            }
            if (parsed.isEmpty()) return
            prices = parsed
            val now = System.currentTimeMillis()
            fetchedAt = now
            Prefs.set(CACHE_KEY, Json.string(parsed))
            Prefs.set(CACHE_DATE_KEY, now)
        } finally {
            isFetching = false
        }
    }

    fun fiatValue(sats: Long): Double? {
        val rate = prices[currency] ?: return null
        return sats.toDouble() / 100_000_000 * rate
    }

    fun formatted(sats: Long): String? {
        if (!isEnabled) return null
        val value = fiatValue(sats) ?: return null
        val format = NumberFormat.getCurrencyInstance(AppLanguage.locale)
        format.currency = Currency.getInstance(currency)
        val digits = if (currency == "JPY") 0 else 2
        format.minimumFractionDigits = digits
        format.maximumFractionDigits = digits
        return format.format(value)
    }
}
