import Foundation
import QiqstrCore

struct Account: Hashable, Identifiable, Sendable {
    var npub: String
    var pubkeyHex: String
    var isReadOnly: Bool
    var id: String { npub }
}

private struct StoredAccount: Codable {
    var npub: String
    var privateKeyHex: String
    var mnemonic: String?
    var pubkey: String?
    var isReadOnly: Bool { privateKeyHex.isEmpty }
    var signingKey: String? { isReadOnly ? nil : privateKeyHex }
    var pubkeyHex: String { pubkey ?? signingKey.flatMap { try? getPublicKey(privateKeyHex: $0) } ?? "" }
    var summary: Account { Account(npub: npub, pubkeyHex: pubkeyHex, isReadOnly: isReadOnly) }
}

enum AuthError: LocalizedError {
    case invalidKey, invalidMnemonic, accountNotFound, keyMismatch, differentAccount, wrongPassword, passwordRequired, storageFailed
    case nip05NotFound(String)
    var errorDescription: String? {
        switch self {
        case .invalidKey: L("invalidNsecError")
        case .invalidMnemonic: L("invalidMnemonicError")
        case .accountNotFound: L("authAccountNotFound")
        case .keyMismatch: L("authKeyMismatch")
        case .differentAccount: L("addKeyMismatch")
        case .wrongPassword: L("authNcryptsecWrongPassword")
        case .passwordRequired: L("authNcryptsecPasswordRequired")
        case .storageFailed: L("authKeyStorageFailed")
        case .nip05NotFound(let address): L("nip05NotFound", ["address": address])
        }
    }
}

final class AccountStore {
    static let shared = AccountStore()
    private let accountsKey = "stored_accounts"
    private let activeKey = "active_npub"

    private var records: [StoredAccount] {
        guard let raw = Keychain.get(accountsKey), let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([StoredAccount].self, from: data)) ?? []
    }

    var accounts: [Account] { records.map(\.summary) }

    var active: Account? {
        guard let npub = Keychain.get(activeKey) else { return nil }
        return records.first { $0.npub == npub }?.summary
    }

    func signingKey(for npub: String) -> String? {
        records.first { $0.npub == npub }?.signingKey
    }

    func mnemonic(for npub: String) -> String? {
        records.first { $0.npub == npub }?.mnemonic?.nilIfEmpty
    }

    private func save(_ list: [StoredAccount]) throws {
        let data = try JSONEncoder().encode(list)
        guard Keychain.set(String(decoding: data, as: UTF8.self), for: accountsKey) else { throw AuthError.storageFailed }
    }

    @discardableResult
    func store(privateKeyHex: String, mnemonic: String? = nil) throws -> Account {
        let pub = try getPublicKey(privateKeyHex: privateKeyHex)
        let npub = try nip19EncodePubkey(pubkeyHex: pub)
        var list = records
        let existing = list.first { $0.npub == npub }
        let account = StoredAccount(npub: npub, privateKeyHex: privateKeyHex, mnemonic: mnemonic ?? existing?.mnemonic, pubkey: pub)
        list.removeAll { $0.npub == npub }
        list.append(account)
        try save(list)
        Keychain.set(npub, for: activeKey)
        return account.summary
    }

    @discardableResult
    func storeReadOnly(pubkeyHex: String) throws -> Account {
        let pub = pubkeyHex.lowercased()
        let npub = try nip19EncodePubkey(pubkeyHex: pub)
        var list = records
        if let existing = list.first(where: { $0.npub == npub }) {
            Keychain.set(npub, for: activeKey)
            return existing.summary
        }
        let account = StoredAccount(npub: npub, privateKeyHex: "", mnemonic: nil, pubkey: pub)
        list.append(account)
        try save(list)
        Keychain.set(npub, for: activeKey)
        return account.summary
    }

    func login(input: String, password: String) throws -> Account {
        guard Ncryptsec.matches(input) else { return try login(input: input) }
        let hex = try Ncryptsec.decryptSync(input, password: password)
        return try store(privateKeyHex: hex)
    }

    func login(input: String) throws -> Account {
        if Ncryptsec.matches(input) { throw AuthError.passwordRequired }
        if let pubkey = Self.readOnlyPubkey(input) { return try storeReadOnly(pubkeyHex: pubkey) }
        let key = try Self.signingKey(from: input)
        return try store(privateKeyHex: key.hex, mnemonic: key.mnemonic)
    }

    static func readOnlyPubkey(_ input: String) -> String? {
        let trimmed = Nip19.stripScheme(input.trimmingCharacters(in: .whitespacesAndNewlines))
        guard trimmed.hasPrefix("npub1") || trimmed.hasPrefix("nprofile1") else { return nil }
        return Nip19.pubkeyHex(from: trimmed)
    }

    static func signingKey(from input: String) throws -> (hex: String, mnemonic: String?) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        if words.count >= 12 {
            let phrase = words.joined(separator: " ").lowercased()
            guard validateMnemonic(mnemonic: phrase), let key = try? mnemonicToPrivateKey(mnemonic: phrase) else { throw AuthError.invalidMnemonic }
            return (key, phrase)
        }
        var hex = trimmed
        let bech = Nip19.stripScheme(trimmed).lowercased()
        if bech.hasPrefix("nsec1") {
            guard let decoded = try? nip19Decode(bech32Str: bech) else { throw AuthError.invalidKey }
            hex = decoded
        }
        guard hex.count == 64, hex.allSatisfy(\.isHexDigit), (try? getPublicKey(privateKeyHex: hex)) != nil else { throw AuthError.invalidKey }
        return (hex.lowercased(), nil)
    }

    func upgrade(npub: String, input: String) throws -> Account {
        guard let target = records.first(where: { $0.npub == npub }) else { throw AuthError.accountNotFound }
        let key = try Self.signingKey(from: input)
        guard (try? getPublicKey(privateKeyHex: key.hex)) == target.pubkeyHex else { throw AuthError.differentAccount }
        return try store(privateKeyHex: key.hex, mnemonic: key.mnemonic)
    }

    func upgrade(npub: String, input: String, password: String) throws -> Account {
        guard Ncryptsec.matches(input) else { return try upgrade(npub: npub, input: input) }
        return try upgrade(npub: npub, input: Ncryptsec.decryptSync(input, password: password))
    }

    func createAccount() throws -> Account {
        let phrase = try generateMnemonic()
        let key = try mnemonicToPrivateKey(mnemonic: phrase)
        let account = try store(privateKeyHex: key, mnemonic: phrase)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.createdHereKey(account.pubkeyHex))
        return account
    }

    static func wasCreatedHere(_ pubkeyHex: String) -> Bool {
        let created = UserDefaults.standard.double(forKey: createdHereKey(pubkeyHex))
        return created > 0 && Date().timeIntervalSince1970 - created < 86_400
    }

    private static func createdHereKey(_ pubkeyHex: String) -> String { "account_created_here_\(pubkeyHex.lowercased())" }

    func switchTo(npub: String) throws -> Account {
        guard let target = records.first(where: { $0.npub == npub }) else { throw AuthError.accountNotFound }
        guard Nip19.npub(target.pubkeyHex) == target.npub else { throw AuthError.keyMismatch }
        Keychain.set(npub, for: activeKey)
        return target.summary
    }

    func remove(npub: String) {
        try? save(records.filter { $0.npub != npub })
        if Keychain.get(activeKey) == npub {
            Keychain.set(records.first?.npub, for: activeKey)
        }
    }

    func logoutActive() -> Account? {
        if let current = active { remove(npub: current.npub) }
        return active
    }
}

enum Ncryptsec {
    nonisolated static let minimumPasswordLength = 8

    nonisolated static func normalized(_ input: String) -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.hasPrefix("nostr:") ? String(value.dropFirst(6)) : value
    }

    nonisolated static func matches(_ input: String) -> Bool {
        normalized(input).hasPrefix("ncryptsec1")
    }

    nonisolated static func decryptSync(_ input: String, password: String) throws -> String {
        let value = normalized(input)
        let hex: String
        do {
            hex = try ncryptsecDecrypt(ncryptsec: value, password: password)
        } catch {
            throw AuthError.wrongPassword
        }
        guard hex.count == 64, hex.allSatisfy(\.isHexDigit) else { throw AuthError.wrongPassword }
        return hex.lowercased()
    }

    nonisolated static func decrypt(_ input: String, password: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) { try decryptSync(input, password: password) }.value
    }

    nonisolated static func encrypt(privateKeyHex: String, password: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) { try ncryptsecEncrypt(privateKeyHex: privateKeyHex, password: password) }.value
    }
}
