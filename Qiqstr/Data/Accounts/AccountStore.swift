import Foundation
import QiqstrCore

struct StoredAccount: Codable, Hashable, Identifiable, Sendable {
    var npub: String
    var privateKeyHex: String
    var mnemonic: String?
    var id: String { npub }
    var pubkeyHex: String { (try? getPublicKey(privateKeyHex: privateKeyHex)) ?? "" }
}

enum AuthError: LocalizedError {
    case invalidKey, invalidMnemonic, accountNotFound, keyMismatch
    var errorDescription: String? {
        switch self {
        case .invalidKey: L("invalidNsecError")
        case .invalidMnemonic: L("invalidMnemonicError")
        case .accountNotFound: "Account not found"
        case .keyMismatch: "Stored account keys do not match"
        }
    }
}

final class AccountStore {
    static let shared = AccountStore()
    private let accountsKey = "stored_accounts"
    private let activeKey = "active_npub"

    var accounts: [StoredAccount] {
        guard let raw = Keychain.get(accountsKey), let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([StoredAccount].self, from: data)) ?? []
    }

    var active: StoredAccount? {
        guard let npub = Keychain.get(activeKey) else { return nil }
        return accounts.first { $0.npub == npub }
    }

    private func save(_ list: [StoredAccount]) {
        let data = (try? JSONEncoder().encode(list)) ?? Data("[]".utf8)
        Keychain.set(String(decoding: data, as: UTF8.self), for: accountsKey)
    }

    @discardableResult
    func store(privateKeyHex: String, mnemonic: String? = nil) throws -> StoredAccount {
        let pub = try getPublicKey(privateKeyHex: privateKeyHex)
        let npub = try nip19EncodePubkey(pubkeyHex: pub)
        var list = accounts
        let existing = list.first { $0.npub == npub }
        let account = StoredAccount(npub: npub, privateKeyHex: privateKeyHex, mnemonic: mnemonic ?? existing?.mnemonic)
        list.removeAll { $0.npub == npub }
        list.append(account)
        save(list)
        Keychain.set(npub, for: activeKey)
        return account
    }

    func login(input: String) throws -> StoredAccount {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        if words.count >= 12 {
            let phrase = words.joined(separator: " ").lowercased()
            guard validateMnemonic(mnemonic: phrase), let key = try? mnemonicToPrivateKey(mnemonic: phrase) else { throw AuthError.invalidMnemonic }
            return try store(privateKeyHex: key, mnemonic: phrase)
        }
        var hex = trimmed
        if trimmed.hasPrefix("nsec1") {
            guard let decoded = try? nip19Decode(bech32Str: trimmed) else { throw AuthError.invalidKey }
            hex = decoded
        }
        guard hex.count == 64, hex.allSatisfy(\.isHexDigit), (try? getPublicKey(privateKeyHex: hex)) != nil else { throw AuthError.invalidKey }
        return try store(privateKeyHex: hex.lowercased())
    }

    func createAccount() throws -> StoredAccount {
        let phrase = try generateMnemonic()
        let key = try mnemonicToPrivateKey(mnemonic: phrase)
        return try store(privateKeyHex: key, mnemonic: phrase)
    }

    func switchTo(npub: String) throws -> StoredAccount {
        guard let target = accounts.first(where: { $0.npub == npub }) else { throw AuthError.accountNotFound }
        guard Nip19.npub(target.pubkeyHex) == target.npub else { throw AuthError.keyMismatch }
        Keychain.set(npub, for: activeKey)
        return target
    }

    func remove(npub: String) {
        save(accounts.filter { $0.npub != npub })
        if Keychain.get(activeKey) == npub {
            Keychain.set(accounts.first?.npub, for: activeKey)
        }
    }

    func logoutActive() -> StoredAccount? {
        if let current = active { remove(npub: current.npub) }
        return active
    }
}
