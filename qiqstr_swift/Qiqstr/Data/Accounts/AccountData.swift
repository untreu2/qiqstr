import Foundation
import QiqstrCore

enum AccountData {
    static func removeCredentials(pubkey: String) {
        guard !pubkey.isEmpty else { return }
        Keychain.set(nil, for: WalletService.credentialKey(pubkey))
    }

    static func erase(pubkey: String, isLastAccount: Bool) async {
        guard !pubkey.isEmpty else { return }
        removeCredentials(pubkey: pubkey)
        await MarmotEngine.shared.close()
        let files = FileManager.default
        if let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            for path in ["marmot/\(pubkey)", "Drafts/\(pubkey).json", "WebOfTrust/\(pubkey).json"] {
                try? files.removeItem(at: support.appendingPathComponent(path))
            }
        }
        try? files.removeItem(at: files.temporaryDirectory.appendingPathComponent("decrypted_media", isDirectory: true))
        let defaults = UserDefaults.standard
        let npub = Nip19.npub(pubkey) ?? pubkey
        for key in defaults.dictionaryRepresentation().keys where key.contains(pubkey) || key.contains(npub) {
            defaults.removeObject(forKey: key)
        }
        if isLastAccount {
            _ = try? await dbWipeDirectory()
            try? files.removeItem(at: RelayConfig.databaseURL)
        } else {
            await eraseCachedEvents(of: pubkey)
        }
    }

    private static func eraseCachedEvents(of pubkey: String) async {
        let filter = JSON.string(["authors": [pubkey]] as JSONObject)
        for _ in 0..<20 {
            let ids = JSON.array(try? await dbQueryEvents(filterJson: filter, limit: 500)).compactMap { $0.str("id") }
            guard !ids.isEmpty, let removed = try? await dbDeleteEventsByIds(eventIds: ids), removed > 0 else { return }
        }
    }
}
