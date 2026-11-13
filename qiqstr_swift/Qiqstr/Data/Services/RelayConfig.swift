import Foundation

enum GossipMode: String, CaseIterable, Identifiable {
    case normal, aggressive, psycho
    var id: String { rawValue }
    var maxOutboxRelays: Int { switch self { case .normal: 30; case .aggressive: 100; case .psycho: 1000 } }
    var minRelayFrequency: Int { switch self { case .normal: 2; case .aggressive: 1; case .psycho: 0 } }
}

enum RelayConfig {
    static let defaultMainRelays = ["wss://relay.damus.io", "wss://nos.lol", "wss://relay.primal.net", "wss://vitor.nostr1.com"]
    static let discoveryRelays = ["wss://relay.damus.io", "wss://nos.lol", "wss://relay.primal.net", "wss://vitor.nostr1.com", "wss://nostr.bitcoiner.social", "wss://nostr.mom"]
    static let indexerRelays = ["wss://purplepag.es", "wss://nostr.mom", "wss://relay.primal.net"]
    nonisolated static let primalCacheUrl = "wss://cache2.primal.net/v1"
    nonisolated static let vertexRelayUrl = "wss://relay.vertexlab.io"
    static let blossomServer = "https://blossom.primal.net"
    static let encryptedMediaServers = [blossomServer, "https://nostr.download"]

    static var mainRelays: [String] {
        get {
            guard let stored = UserDefaults.standard.stringArray(forKey: "custom_main_relays") else { return defaultMainRelays }
            let valid = stored.filter(isUsableRelayURL)
            return valid.isEmpty ? defaultMainRelays : valid
        }
        set { UserDefaults.standard.set(newValue.filter(isUsableRelayURL), forKey: "custom_main_relays") }
    }

    nonisolated static func isUsableRelayURL(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value == raw, !value.contains(where: \.isWhitespace),
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), scheme == "wss" || scheme == "ws",
              let host = components.host, !host.isEmpty,
              value.components(separatedBy: "://").count == 2 else { return false }
        if let port = components.port, !(1...65535).contains(port) { return false }
        return true
    }

    static func resetRelays() { UserDefaults.standard.removeObject(forKey: "custom_main_relays") }

    static var gossipMode: GossipMode {
        get { GossipMode(rawValue: UserDefaults.standard.string(forKey: "gossip_mode") ?? "") ?? .normal }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "gossip_mode") }
    }

    static var databaseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("nostr-lmdb", isDirectory: true)
    }
}
