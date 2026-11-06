import Foundation
import QiqstrCore

enum Nip19 {
    static func npub(_ hex: String) -> String? { try? nip19EncodePubkey(pubkeyHex: hex) }
    static func nsec(_ hex: String) -> String? { try? nip19EncodePrivkey(privkeyHex: hex) }
    static func note(_ hex: String) -> String? { try? nip19EncodeNote(eventIdHex: hex) }
    static func nevent(_ hex: String, author: String? = nil) -> String? { try? nip19EncodeNevent(eventIdHex: hex, authorHex: author) }
    static func nprofile(_ hex: String) -> String? { try? nip19EncodeNprofile(pubkeyHex: hex) }
    static func naddr(kind: UInt16 = 30023, pubkey: String, identifier: String) -> String? {
        try? nip19EncodeNaddr(kind: kind, pubkeyHex: pubkey, identifier: identifier)
    }

    static func decode(_ bech32: String) -> String? {
        try? nip19Decode(bech32Str: stripScheme(bech32))
    }

    static func decodeTLV(_ bech32: String) -> JSONObject? {
        JSON.object(try? nip19DecodeTlv(bech32Str: stripScheme(bech32)))
    }

    static func pubkeyHex(from input: String) -> String? {
        let s = stripScheme(input.trimmingCharacters(in: .whitespacesAndNewlines))
        if s.count == 64, s.allSatisfy(\.isHexDigit) { return s.lowercased() }
        if s.hasPrefix("npub1") || s.hasPrefix("nprofile1") { return decode(s) }
        return nil
    }

    static func stripScheme(_ s: String) -> String {
        s.hasPrefix("nostr:") ? String(s.dropFirst(6)) : s
    }
}
