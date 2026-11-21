package me.untreu.qiqstr.data.accounts

import com.qiqstr.core.generateMnemonic
import com.qiqstr.core.getPublicKey
import com.qiqstr.core.mnemonicToPrivateKey
import com.qiqstr.core.ncryptsecDecrypt
import com.qiqstr.core.ncryptsecEncrypt
import com.qiqstr.core.nip19Decode
import com.qiqstr.core.nip19EncodePubkey
import com.qiqstr.core.validateMnemonic
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.SecureStore
import me.untreu.qiqstr.core.str
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.bridge.isHex
import org.json.JSONObject

data class Account(val npub: String, val pubkeyHex: String, val isReadOnly: Boolean) {
    val id: String get() = npub
}

private data class StoredAccount(
    val npub: String,
    val privateKeyHex: String,
    val mnemonic: String? = null,
    val pubkey: String? = null,
) {
    val id: String get() = npub
    val isReadOnly: Boolean get() = privateKeyHex.isEmpty()
    val signingKey: String? get() = if (isReadOnly) null else privateKeyHex
    val pubkeyHex: String get() = pubkey ?: signingKey?.let { runCatching { getPublicKey(it) }.getOrNull() } ?: ""

    val summary: Account get() = Account(npub, pubkeyHex, isReadOnly)

    fun toJson() = JSONObject().apply {
        put("npub", npub)
        put("privateKeyHex", privateKeyHex)
        mnemonic?.let { put("mnemonic", it) }
        pubkey?.let { put("pubkey", it) }
    }

    companion object {
        fun from(json: JSONObject) = StoredAccount(
            npub = json.optString("npub"),
            privateKeyHex = json.optString("privateKeyHex"),
            mnemonic = json.str("mnemonic"),
            pubkey = json.str("pubkey"),
        )
    }
}

sealed class AuthError(private val key: String, private val args: Map<String, Any?> = emptyMap()) : Exception() {
    object InvalidKey : AuthError("invalidNsecError")
    object InvalidMnemonic : AuthError("invalidMnemonicError")
    object AccountNotFound : AuthError("authAccountNotFound")
    object KeyMismatch : AuthError("authKeyMismatch")
    object DifferentAccount : AuthError("addKeyMismatch")
    object WrongPassword : AuthError("authNcryptsecWrongPassword")
    object PasswordRequired : AuthError("authNcryptsecPasswordRequired")
    object StorageFailed : AuthError("authKeyStorageFailed")
    class Nip05NotFound(address: String) : AuthError("nip05NotFound", mapOf("address" to address))

    override val message: String get() = L(key, args)
}

object AccountStore {
    private const val ACCOUNTS_KEY = "stored_accounts"
    private const val ACTIVE_KEY = "active_npub"

    private val records: List<StoredAccount>
        get() = Json.array(SecureStore.get(ACCOUNTS_KEY)).map(StoredAccount::from)

    val accounts: List<Account> get() = records.map { it.summary }

    val active: Account?
        get() {
            val npub = SecureStore.get(ACTIVE_KEY) ?: return null
            return records.firstOrNull { it.npub == npub }?.summary
        }

    fun storedSigningKey(npub: String): String? = records.firstOrNull { it.npub == npub }?.signingKey

    fun storedMnemonic(npub: String): String? = records.firstOrNull { it.npub == npub }?.mnemonic?.ifEmpty { null }

    private fun save(list: List<StoredAccount>) {
        val array = org.json.JSONArray().apply { list.forEach { put(it.toJson()) } }
        if (!SecureStore.set(ACCOUNTS_KEY, array.toString())) throw AuthError.StorageFailed
    }

    fun store(privateKeyHex: String, mnemonic: String? = null): Account {
        val pub = getPublicKey(privateKeyHex)
        val npub = nip19EncodePubkey(pub)
        val list = records.toMutableList()
        val existing = list.firstOrNull { it.npub == npub }
        val account = StoredAccount(npub, privateKeyHex, mnemonic ?: existing?.mnemonic, pub)
        list.removeAll { it.npub == npub }
        list.add(account)
        save(list)
        SecureStore.set(ACTIVE_KEY, npub)
        return account.summary
    }

    fun storeReadOnly(pubkeyHex: String): Account {
        val pub = pubkeyHex.lowercase()
        val npub = nip19EncodePubkey(pub)
        val list = records.toMutableList()
        list.firstOrNull { it.npub == npub }?.let {
            SecureStore.set(ACTIVE_KEY, npub)
            return it.summary
        }
        val account = StoredAccount(npub, "", null, pub)
        list.add(account)
        save(list)
        SecureStore.set(ACTIVE_KEY, npub)
        return account.summary
    }

    fun login(input: String, password: String): Account {
        if (!Ncryptsec.matches(input)) return login(input)
        return store(Ncryptsec.decryptSync(input, password))
    }

    fun login(input: String): Account {
        if (Ncryptsec.matches(input)) throw AuthError.PasswordRequired
        readOnlyPubkey(input)?.let { return storeReadOnly(it) }
        val (hex, mnemonic) = signingKey(input)
        return store(hex, mnemonic)
    }

    fun readOnlyPubkey(input: String): String? {
        val trimmed = Nip19.stripScheme(input.trim())
        if (!trimmed.startsWith("npub1") && !trimmed.startsWith("nprofile1")) return null
        return Nip19.pubkeyHex(trimmed)
    }

    fun signingKey(input: String): Pair<String, String?> {
        val trimmed = input.trim()
        val words = trimmed.split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (words.size >= 12) {
            val phrase = words.joinToString(" ").lowercase()
            if (!validateMnemonic(phrase)) throw AuthError.InvalidMnemonic
            val key = runCatching { mnemonicToPrivateKey(phrase) }.getOrNull() ?: throw AuthError.InvalidMnemonic
            return key to phrase
        }
        var hex = trimmed
        val bech = Nip19.stripScheme(trimmed).lowercase()
        if (bech.startsWith("nsec1")) hex = runCatching { nip19Decode(bech) }.getOrNull() ?: throw AuthError.InvalidKey
        if (hex.length != 64 || !hex.all { it.isHex() } || runCatching { getPublicKey(hex) }.isFailure) throw AuthError.InvalidKey
        return hex.lowercase() to null
    }

    fun upgrade(npub: String, input: String): Account {
        val target = records.firstOrNull { it.npub == npub } ?: throw AuthError.AccountNotFound
        val (hex, mnemonic) = signingKey(input)
        if (runCatching { getPublicKey(hex) }.getOrNull() != target.pubkeyHex) throw AuthError.DifferentAccount
        return store(hex, mnemonic)
    }

    fun upgrade(npub: String, input: String, password: String): Account {
        if (!Ncryptsec.matches(input)) return upgrade(npub, input)
        return upgrade(npub, Ncryptsec.decryptSync(input, password))
    }

    fun createAccount(): Account {
        val phrase = generateMnemonic()
        val key = mnemonicToPrivateKey(phrase)
        val account = store(key, phrase)
        Prefs.setDouble(createdHereKey(account.pubkeyHex), System.currentTimeMillis() / 1000.0)
        return account
    }

    fun wasCreatedHere(pubkeyHex: String): Boolean {
        val created = Prefs.double(createdHereKey(pubkeyHex))
        return created > 0 && System.currentTimeMillis() / 1000.0 - created < 86_400
    }

    private fun createdHereKey(pubkeyHex: String) = "account_created_here_${pubkeyHex.lowercase()}"

    fun switchTo(npub: String): Account {
        val target = records.firstOrNull { it.npub == npub } ?: throw AuthError.AccountNotFound
        if (Nip19.npub(target.pubkeyHex) != target.npub) throw AuthError.KeyMismatch
        SecureStore.set(ACTIVE_KEY, npub)
        return target.summary
    }

    fun remove(npub: String) {
        runCatching { save(records.filter { it.npub != npub }) }
        if (SecureStore.get(ACTIVE_KEY) == npub) SecureStore.set(ACTIVE_KEY, records.firstOrNull()?.npub)
    }

    fun logoutActive(): Account? {
        active?.let { remove(it.npub) }
        return active
    }
}

object Ncryptsec {
    const val MINIMUM_PASSWORD_LENGTH = 8

    fun normalized(input: String): String {
        val value = input.trim().lowercase()
        return value.removePrefix("nostr:")
    }

    fun matches(input: String) = normalized(input).startsWith("ncryptsec1")

    fun decryptSync(input: String, password: String): String {
        val hex = runCatching { ncryptsecDecrypt(normalized(input), password) }.getOrNull() ?: throw AuthError.WrongPassword
        if (hex.length != 64 || !hex.all { it.isHex() }) throw AuthError.WrongPassword
        return hex.lowercase()
    }

    suspend fun decrypt(input: String, password: String): String = withContext(Dispatchers.Default) { decryptSync(input, password) }

    suspend fun encrypt(privateKeyHex: String, password: String): String =
        withContext(Dispatchers.Default) { ncryptsecEncrypt(privateKeyHex, password) }
}
