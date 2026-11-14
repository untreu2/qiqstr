package me.untreu.qiqstr.data.bridge

import com.qiqstr.core.nip19Decode
import com.qiqstr.core.nip19DecodeTlv
import com.qiqstr.core.nip19EncodeNaddr
import com.qiqstr.core.nip19EncodeNevent
import com.qiqstr.core.nip19EncodeNote
import com.qiqstr.core.nip19EncodeNprofile
import com.qiqstr.core.nip19EncodePrivkey
import com.qiqstr.core.nip19EncodePubkey
import me.untreu.qiqstr.core.Json
import org.json.JSONObject

object Nip19 {
    fun npub(hex: String): String? = runCatching { nip19EncodePubkey(hex) }.getOrNull()
    fun nsec(hex: String): String? = runCatching { nip19EncodePrivkey(hex) }.getOrNull()
    fun note(hex: String): String? = runCatching { nip19EncodeNote(hex) }.getOrNull()
    fun nevent(hex: String, author: String? = null): String? = runCatching { nip19EncodeNevent(hex, author) }.getOrNull()
    fun nprofile(hex: String): String? = runCatching { nip19EncodeNprofile(hex) }.getOrNull()
    fun naddr(kind: Int = 30023, pubkey: String, identifier: String): String? =
        runCatching { nip19EncodeNaddr(kind.toUShort(), pubkey, identifier) }.getOrNull()

    fun decode(bech32: String): String? = runCatching { nip19Decode(stripScheme(bech32)) }.getOrNull()

    fun decodeTLV(bech32: String): JSONObject? = runCatching { Json.obj(nip19DecodeTlv(stripScheme(bech32))) }.getOrNull()

    fun pubkeyHex(input: String): String? {
        val s = stripScheme(input.trim())
        if (s.length == 64 && s.all { it.isHex() }) return s.lowercase()
        if (s.startsWith("npub1") || s.startsWith("nprofile1")) return decode(s)
        return null
    }

    fun stripScheme(s: String): String = if (s.startsWith("nostr:")) s.removePrefix("nostr:") else s
}

fun Char.isHex() = this in '0'..'9' || this in 'a'..'f' || this in 'A'..'F'
