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
    static let primalCacheUrl = "wss://cache2.primal.net/v1"
    static let vertexRelayUrl = "wss://relay.vertexlab.io"
    static let blossomServer = "https://blossom.primal.net"
    static let encryptedMediaServers = [blossomServer, "https://nostr.download"]

    static var mainRelays: [String] {
        get { UserDefaults.standard.stringArray(forKey: "custom_main_relays") ?? defaultMainRelays }
        set { UserDefaults.standard.set(newValue, forKey: "custom_main_relays") }
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
