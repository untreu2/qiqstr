package me.untreu.qiqstr.ui.wallet

import com.qiqstr.core.cashuDecodeToken
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.core.TimeFormat
import me.untreu.qiqstr.core.bool
import me.untreu.qiqstr.core.int
import me.untreu.qiqstr.core.long
import me.untreu.qiqstr.core.str
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject

object SatsAmount {
    const val MAXIMUM = 2_100_000_000_000_000L

    fun isValid(sats: Long): Boolean = sats in 1..MAXIMUM

    fun msat(sats: Long): Long? {
        if (!isValid(sats)) return null
        return runCatching { Math.multiplyExact(sats, 1000L) }.getOrNull()
    }
}

sealed class WalletError(private val text: () -> String) : Exception() {
    override val message: String get() = text()

    class NotConnected : WalletError({ L("pleaseConnectWalletFirst") })
    class InvalidConnection : WalletError({ L("nwcInvalidConnectionString") })
    class NoAccount : WalletError({ L("walletNoAccount") })
    class EmptyInvoice : WalletError({ L("walletEmptyInvoice") })
    class InvalidAmount : WalletError({ L("enterValidAmount") })
    class AmountOutOfRange(val min: Long, val max: Long) : WalletError({ L("walletAmountRange", "min" to Sats.format(min), "max" to Sats.format(max)) })
    class AmountlessInvoice : WalletError({ L("walletAmountlessInvoice") })
    class InvoiceExpired : WalletError({ L("walletInvoiceExpired") })
    class InvoiceAmountMismatch : WalletError({ L("walletInvoiceAmountMismatch") })
    class Unrecognized : WalletError({ L("unrecognizedPaymentFormat") })
    class Lnurl(val reason: String) : WalletError({ reason })
    class ResolveFailed : WalletError({ L("resolveAddressFailed") })
    class CashuTooSmall : WalletError({ L("walletCashuTooSmall") })
    class NothingToMelt : WalletError({ L("walletNothingToMelt") })
    class PaymentPending : WalletError({ L("walletPaymentPending") })
    class PaymentFailed : WalletError({ L("paymentFailed") })
}

data class CashuTokenInfo(val token: String, val mintUrl: String, val amountSats: Long) {
    companion object {
        fun normalized(text: String): String {
            var s = text.trim()
            if (s.lowercase().startsWith("cashu:")) s = s.drop(6)
            return s
        }

        fun looksLikeToken(text: String): Boolean {
            val s = normalized(text)
            return s.startsWith("cashuA") || s.startsWith("cashuB")
        }

        fun decode(text: String): CashuTokenInfo? {
            val token = normalized(text)
            if (!looksLikeToken(token)) return null
            val json = Json.obj(runCatching { cashuDecodeToken(token) }.getOrNull()) ?: return null
            return CashuTokenInfo(token, json.str("mint_url") ?: "", json.long("amount_sats"))
        }
    }
}

sealed interface PaymentRequest {
    data class Bolt11(val raw: String, val invoice: Bolt11Invoice) : PaymentRequest
    data class LightningAddress(val address: String) : PaymentRequest
    data class LnurlRequest(val url: HttpUrl) : PaymentRequest
    data class Cashu(val info: CashuTokenInfo) : PaymentRequest

    val needsAmount: Boolean
        get() = when (this) {
            is Bolt11 -> invoice.amountMsat == null
            is LightningAddress, is LnurlRequest -> true
            is Cashu -> false
        }

    companion object {
        fun parse(text: String): PaymentRequest? {
            var s = text.trim()
            if (s.isEmpty()) return null
            if (CashuTokenInfo.looksLikeToken(s)) return CashuTokenInfo.decode(s)?.let { Cashu(it) }
            if (s.lowercase().startsWith("bitcoin:")) {
                lightningParam(s)?.let { s = it }
            }
            if (s.lowercase().startsWith("lightning:")) s = s.drop(10)
            if (s.startsWith("//")) s = s.drop(2)
            val lower = s.lowercase()
            if (lower.startsWith("lnurl1")) return Lnurl.decode(lower)?.let { LnurlRequest(it) }
            if (lower.startsWith("lnurlp://")) return ("https://" + s.drop(9)).toHttpUrlOrNull()?.let { LnurlRequest(it) }
            if (lower.startsWith("ln")) Bolt11Codec.decode(lower)?.let { return Bolt11(lower, it) }
            if (Lnurl.isLightningAddress(s)) return LightningAddress(lower)
            return null
        }

        private fun lightningParam(uri: String): String? {
            val query = uri.substringAfter('?', "").ifEmpty { return null }
            for (pair in query.split('&')) {
                val name = pair.substringBefore('=')
                if (name.lowercase() == "lightning") {
                    val value = pair.substringAfter('=', "")
                    return runCatching { java.net.URLDecoder.decode(value, "UTF-8") }.getOrDefault(value).ifEmpty { null }
                }
            }
            return null
        }
    }
}

data class LnurlPayParams(
    val callback: HttpUrl,
    val minSendableMsat: Long,
    val maxSendableMsat: Long,
    val commentAllowed: Int,
    val allowsNostr: Boolean,
    val nostrPubkey: String?,
    val description: String?,
    val lnurl: String,
    val domain: String,
) {
    val minSats: Long get() = minSendableMsat / 1000 + (if (minSendableMsat % 1000 == 0L) 0 else 1)
    val maxSats: Long get() = maxSendableMsat / 1000
    val isFixedAmount: Boolean get() = minSendableMsat == maxSendableMsat
}

object Lnurl {
    private val client by lazy {
        OkHttpClient.Builder()
            .callTimeout(15, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .connectTimeout(15, TimeUnit.SECONDS)
            .cache(null)
            .build()
    }

    private const val UNRESERVED = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"

    fun isLightningAddress(text: String): Boolean {
        val parts = text.split("@")
        if (parts.size != 2 || parts[0].isEmpty()) return false
        val domain = parts[1]
        return domain.contains(".") && !domain.startsWith(".") && !domain.endsWith(".") && !domain.contains(" ") && !parts[0].contains(" ")
    }

    fun wellKnownUrl(address: String): HttpUrl? {
        val parts = address.lowercase().split("@").filter { it.isNotEmpty() }
        if (parts.size != 2) return null
        val domain = parts[1]
        val scheme = if (domain.endsWith(".onion")) "http" else "https"
        return "$scheme://$domain/.well-known/lnurlp/${parts[0]}".toHttpUrlOrNull()
    }

    fun decode(bech32: String): HttpUrl? {
        val (hrp, data) = Bech32.decode(bech32) ?: return null
        if (hrp != "lnurl") return null
        val bytes = Bech32.convertBits(data, 5, 8, false) ?: return null
        val string = runCatching { String(ByteArray(bytes.size) { bytes[it].toByte() }, Charsets.UTF_8) }.getOrNull() ?: return null
        return string.toHttpUrlOrNull()
    }

    fun encode(url: HttpUrl): String? {
        val words = Bech32.convertBits(url.toString().toByteArray(Charsets.UTF_8).map { it.toInt() and 0xff }.toIntArray(), 8, 5, true) ?: return null
        return Bech32.encode("lnurl", words)
    }

    suspend fun payParams(address: String): LnurlPayParams {
        val url = wellKnownUrl(address) ?: throw WalletError.ResolveFailed()
        return payParams(url)
    }

    suspend fun payParams(url: HttpUrl): LnurlPayParams {
        val json = fetchJson(url)
        val callbackString = json.str("callback")
        val callback = callbackString?.toHttpUrlOrNull()
        if (json.str("tag") != "payRequest" || callback == null) throw WalletError.ResolveFailed()
        val metadata = Json.any(json.str("metadata")) as? JSONArray
        val description = metadata?.let { array ->
            (0 until array.length()).mapNotNull { array.optJSONArray(it) }
                .firstOrNull { it.optString(0) == "text/plain" }
                ?.let { if (it.length() > 1) it.opt(1) as? String else null }
        }
        val minSendable = int64(json.opt("minSendable")) ?: 1000L
        val maxSendable = int64(json.opt("maxSendable")) ?: 100_000_000_000L
        val cap = SatsAmount.MAXIMUM * 1000
        if (callback.scheme.lowercase() != "https" || minSendable < 1 || maxSendable < minSendable || maxSendable > cap) {
            throw WalletError.ResolveFailed()
        }
        return LnurlPayParams(
            callback = callback,
            minSendableMsat = minSendable,
            maxSendableMsat = maxSendable,
            commentAllowed = json.int("commentAllowed"),
            allowsNostr = json.bool("allowsNostr"),
            nostrPubkey = json.str("nostrPubkey"),
            description = description,
            lnurl = encode(url) ?: url.toString(),
            domain = url.host,
        )
    }

    suspend fun requestInvoice(params: LnurlPayParams, amountMsat: Long, comment: String? = null, zapRequest: String? = null): String {
        if (amountMsat < params.minSendableMsat || amountMsat > params.maxSendableMsat) {
            throw WalletError.AmountOutOfRange(params.minSats, params.maxSats)
        }
        val builder = params.callback.newBuilder()
        fun add(name: String, value: String) { builder.addEncodedQueryParameter(name, percentEncode(value)) }
        add("amount", amountMsat.toString())
        val trimmedComment = comment?.trim()
        if (zapRequest != null) {
            add("nostr", zapRequest)
            add("lnurl", params.lnurl)
        } else if (!trimmedComment.isNullOrEmpty() && params.commentAllowed > 0) {
            add("comment", trimmedComment.take(params.commentAllowed))
        }
        val json = fetchJson(builder.build())
        val pr = json.str("pr") ?: throw WalletError.EmptyInvoice()
        val decoded = Bolt11Codec.decode(pr)
        if (decoded != null && (decoded.amountMsat != amountMsat || decoded.isExpired)) throw WalletError.InvoiceAmountMismatch()
        return pr
    }

    private fun percentEncode(value: String): String {
        val out = StringBuilder()
        for (byte in value.toByteArray(Charsets.UTF_8)) {
            val c = (byte.toInt() and 0xff).toChar()
            if (c in UNRESERVED) out.append(c) else out.append('%').append(String.format("%02X", byte.toInt() and 0xff))
        }
        return out.toString()
    }

    private suspend fun fetchJson(url: HttpUrl): JSONObject = withContext(Dispatchers.IO) {
        val (code, body) = try {
            client.newCall(Request.Builder().url(url).build()).execute().use { it.code to (it.body?.string() ?: "") }
        } catch (error: Exception) {
            throw WalletError.ResolveFailed()
        }
        val json = Json.obj(body)
        if (json != null && json.str("status")?.uppercase() == "ERROR") {
            throw WalletError.Lnurl(json.str("reason") ?: L("resolveAddressFailed"))
        }
        if (code !in 200..299 || json == null) throw WalletError.ResolveFailed()
        json
    }

    private fun int64(value: Any?): Long? = when (value) {
        is Number -> value.toLong()
        is String -> value.toLongOrNull()
        else -> null
    }
}

data class Bolt11Invoice(
    val network: String,
    val amountMsat: Long?,
    val createdAt: Long,
    val expirySeconds: Long = 3600,
    val paymentHash: String? = null,
    val description: String? = null,
    val descriptionHash: String? = null,
    val payeePubkey: String? = null,
) {
    val amountSats: Long? get() = amountMsat?.let { it / 1000 }
    val expiresAt: Long get() = createdAt + expirySeconds
    val isExpired: Boolean get() = expiresAt < TimeFormat.now
    val isMainnet: Boolean get() = network == "bc"
}

object Bolt11Codec {
    fun decode(raw: String): Bolt11Invoice? {
        var s = raw.trim().lowercase()
        if (s.startsWith("lightning:")) s = s.drop(10)
        if (!s.startsWith("ln")) return null
        val (hrp, words) = Bech32.decode(s) ?: return null
        if (words.size <= 7 + 104) return null
        val hrpBody = hrp.drop(2)
        val digitStart = hrpBody.indexOfFirst { it.isDigit() }
        if (digitStart < 0) return parse(words, hrpBody, null)
        val network = hrpBody.substring(0, digitStart)
        var amountPart = hrpBody.substring(digitStart)
        var multiplier: Char? = null
        val last = amountPart.lastOrNull()
        if (last != null && last in "munp") {
            multiplier = last
            amountPart = amountPart.dropLast(1)
        }
        val value = amountPart.toLongOrNull() ?: return null
        fun times(factor: Long): Long? = runCatching { Math.multiplyExact(value, factor) }.getOrNull()
        val msat = when (multiplier) {
            'm' -> times(100_000_000)
            'u' -> times(100_000)
            'n' -> times(100)
            'p' -> if (value % 10 == 0L) value / 10 else null
            else -> times(100_000_000_000)
        } ?: return null
        return parse(words, network, msat)
    }

    private fun parse(words: IntArray, network: String, amountMsat: Long?): Bolt11Invoice? {
        val payload = words.copyOfRange(0, words.size - 104)
        if (payload.size < 7) return null
        var invoice = Bolt11Invoice(network, amountMsat, number(payload, 0, 7))
        var i = 7
        while (i + 3 <= payload.size) {
            val type = payload[i]
            val length = payload[i + 1] * 32 + payload[i + 2]
            val start = i + 3
            val end = start + length
            if (end > payload.size) break
            val field = payload.copyOfRange(start, end)
            invoice = when {
                type == 1 && length == 52 -> invoice.copy(paymentHash = hex(field))
                type == 13 -> invoice.copy(description = Bech32.convertBits(field, 5, 8, false)?.let { b -> runCatching { String(ByteArray(b.size) { b[it].toByte() }, Charsets.UTF_8) }.getOrNull() })
                type == 23 && length == 52 -> invoice.copy(descriptionHash = hex(field))
                type == 6 -> invoice.copy(expirySeconds = number(field, 0, field.size))
                type == 19 && length == 53 -> invoice.copy(payeePubkey = hex(field))
                else -> invoice
            }
            i = end
        }
        return invoice
    }

    private fun number(words: IntArray, from: Int, to: Int): Long {
        var result = 0L
        for (index in from until minOf(to, from + 12)) result = result * 32 + words[index]
        return result
    }

    private fun hex(words: IntArray): String? =
        Bech32.convertBits(words, 5, 8, false)?.joinToString("") { String.format("%02x", it) }
}

object Bech32 {
    private const val CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    private val generators = intArrayOf(0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3)

    private fun polymod(values: IntArray): Int {
        var chk = 1
        for (v in values) {
            val top = chk ushr 25
            chk = ((chk and 0x1ffffff) shl 5) xor v
            for (i in 0 until 5) if ((top ushr i) and 1 == 1) chk = chk xor generators[i]
        }
        return chk
    }

    private fun expand(hrp: String): IntArray {
        val bytes = hrp.toByteArray(Charsets.UTF_8).map { it.toInt() and 0xff }
        return (bytes.map { it shr 5 } + 0 + bytes.map { it and 31 }).toIntArray()
    }

    fun decode(string: String): Pair<String, IntArray>? {
        val s = string.lowercase()
        val separator = s.lastIndexOf('1')
        if (separator < 0) return null
        val hrp = s.substring(0, separator)
        val dataPart = s.substring(separator + 1)
        if (hrp.isEmpty() || dataPart.length < 6) return null
        val data = IntArray(dataPart.length)
        for ((index, c) in dataPart.withIndex()) {
            val v = CHARSET.indexOf(c)
            if (v < 0) return null
            data[index] = v
        }
        if (polymod(expand(hrp) + data) != 1) return null
        return hrp to data.copyOfRange(0, data.size - 6)
    }

    fun encode(hrp: String, data: IntArray): String {
        val values = expand(hrp) + data + IntArray(6)
        val mod = polymod(values) xor 1
        val checksum = IntArray(6) { (mod ushr (5 * (5 - it))) and 31 }
        return hrp + "1" + (data + checksum).joinToString("") { CHARSET[it].toString() }
    }

    fun convertBits(data: IntArray, from: Int, to: Int, pad: Boolean): IntArray? {
        var acc = 0
        var bits = 0
        val out = ArrayList<Int>(data.size * from / to + 1)
        val maxv = (1 shl to) - 1
        for (v in data) {
            if (v shr from != 0) return null
            acc = ((acc shl from) or v) and 0xfffffff
            bits += from
            while (bits >= to) {
                bits -= to
                out.add((acc shr bits) and maxv)
            }
        }
        if (pad && bits > 0) out.add((acc shl (to - bits)) and maxv)
        if (!pad && bits >= from) return null
        return out.toIntArray()
    }
}
