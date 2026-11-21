import Foundation
import Observation
import QiqstrCore

@MainActor
@Observable
final class MediaServerStore {
    static let shared = MediaServerStore()
    static let kind = 10063
    static let presets = ["https://blossom.primal.net", "https://nostr.download", "https://blossom.band", "https://blossom.nostr.build"]

    private(set) var servers: [String] = []
    private(set) var isSaving = false
    @ObservationIgnored private var owner: String?

    var current: String {
        ensureLoaded()
        return servers.first ?? RelayConfig.defaultBlossomServer
    }

    var options: [String] {
        ensureLoaded()
        var seen: Set<String> = []
        return (servers + Self.presets).filter { seen.insert($0).inserted }
    }

    func reset() {
        owner = nil
        servers = []
    }

    func load() async {
        ensureLoaded()
        guard let me = Session.shared.pubkey else { return }
        let events = await SyncService.shared.fetchReplaceable(kind: Self.kind, author: me)
        guard me == Session.shared.pubkey, let newest = events.max(by: { $0.int("created_at") < $1.int("created_at") }) else { return }
        let remote = Self.servers(in: newest)
        guard !remote.isEmpty, remote != servers else { return }
        servers = remote
        persist()
    }

    func select(_ server: String) async throws {
        guard let url = Self.normalized(server) else { throw CoreError(L("settingsMediaServerInvalid")) }
        ensureLoaded()
        guard url != servers.first else { return }
        var next = servers
        next.removeAll { $0 == url }
        next.insert(url, at: 0)
        try await publish(next)
    }

    func remove(_ server: String) async throws {
        ensureLoaded()
        guard servers.contains(server) else { return }
        try await publish(servers.filter { $0 != server })
    }

    private func publish(_ next: [String]) async throws {
        guard let me = Session.shared.pubkey else { return }
        try Session.shared.requireSigner()
        isSaving = true
        defer { isSaving = false }
        let base = try await SyncService.shared.latestEditableEvent(kind: Self.kind, author: me, allowingNew: true)
        let kept = (base?.tags() ?? []).filter { $0.first != "server" }
        let event = try signEvent(kind: UInt16(Self.kind), content: (base?["content"] as? String) ?? "", tags: next.map { ["server", $0] } + kept)
        try await SyncService.shared.publish(event)
        guard me == Session.shared.pubkey else { return }
        servers = next
        persist()
    }

    static func normalized(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") { value = "https://\(value)" }
        while value.hasSuffix("/") { value.removeLast() }
        guard let components = URLComponents(string: value), components.scheme == "https", let host = components.host, host.contains("."), !value.contains(where: \.isWhitespace) else { return nil }
        return value
    }

    static func displayName(_ server: String) -> String {
        URL(string: server)?.host ?? server
    }

    private static func servers(in event: JSONObject) -> [String] {
        var seen: Set<String> = []
        return event.tags().filter { $0.count > 1 && $0[0] == "server" }.compactMap { normalized($0[1]) }.filter { seen.insert($0).inserted }
    }

    private func ensureLoaded() {
        let pubkey = Session.shared.pubkey
        guard pubkey != owner else { return }
        owner = pubkey
        servers = pubkey.flatMap { UserDefaults.standard.stringArray(forKey: Self.storageKey($0)) } ?? []
    }

    private func persist() {
        guard let owner else { return }
        UserDefaults.standard.set(servers, forKey: Self.storageKey(owner))
    }

    private static func storageKey(_ pubkey: String) -> String { "blossom_servers_\(pubkey)" }
}
