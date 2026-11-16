import Foundation
import QiqstrCore

nonisolated struct GifItem: Identifiable, Hashable, Sendable {
    var id: String { url }
    var url: String
    var preview: String
    var title: String
    var size: CGSize?
    var blurhash: String?
    var sha256: String?

    init?(event: JSONObject) {
        let tags = event.tags()
        func value(_ name: String) -> String? { tags.first { $0.count > 1 && $0[0] == name && !$0[1].isEmpty }?[1] }
        guard let url = value("url"), url.hasPrefix("https://") else { return nil }
        let mime = value("m")?.lowercased()
        guard mime == "image/gif" || (URL(string: url)?.path.lowercased().hasSuffix(".gif") ?? false) else { return nil }
        guard Note.contentWarning(content: "", tags: tags) == nil else { return nil }
        self.url = url
        preview = tags.first { $0.count > 1 && $0[0] == "thumb" && $0[1].lowercased().hasSuffix(".gif") }?[1] ?? url
        let content = (event["content"] as? String) ?? ""
        let described = value("summary") ?? value("alt") ?? JSON.object(content)?.str("title") ?? (content.hasPrefix("{") ? "" : content)
        title = described.components(separatedBy: .newlines).first.map { String($0.prefix(120)) } ?? ""
        if let dim = value("dim") {
            let parts = dim.lowercased().split(separator: "x").compactMap { Double($0) }
            if parts.count == 2, parts[0] > 0, parts[1] > 0 { size = CGSize(width: parts[0], height: parts[1]) }
        }
        blurhash = value("blurhash") ?? value("bh")
        sha256 = value("x")?.nilIfEmpty
    }
}

@MainActor
final class GifService {
    static let shared = GifService()
    static let searchRelays = ["wss://relay.ditto.pub"]
    static let browseRelays = ["wss://relay.ditto.pub", "wss://relay.primal.net"]

    private var cache: [String: [GifItem]] = [:]

    func recent() async -> [GifItem] {
        await load(key: "", filter: ["kinds": [1063], "#m": ["image/gif"], "limit": 60], relays: Self.browseRelays)
    }

    func search(_ query: String) async -> [GifItem] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return await recent() }
        async let searched = load(key: "s:\(term)", filter: ["kinds": [1063], "#m": ["image/gif"], "search": term, "limit": 60], relays: Self.searchRelays)
        async let tagged = load(key: "t:\(term)", filter: ["kinds": [1063], "#m": ["image/gif"], "#t": [term], "limit": 60], relays: Self.browseRelays)
        var seen: Set<String> = []
        return (await searched + tagged).filter { seen.insert($0.url).inserted }
    }

    private func load(key: String, filter: JSONObject, relays: [String]) async -> [GifItem] {
        if let hit = cache[key] { return hit }
        let muted = Set(Session.shared.mutedPubkeys)
        let raw = try? await fetchEventsFromRelays(filterJson: JSON.string(filter), relayUrls: relays, timeoutSecs: 8)
        var seen: Set<String> = []
        let items = JSON.array(raw)
            .filter { !muted.contains($0.str("pubkey") ?? "") }
            .sorted { $0.int("created_at") > $1.int("created_at") }
            .compactMap(GifItem.init(event:))
            .filter { seen.insert($0.url).inserted }
        if !items.isEmpty { cache[key] = items }
        return items
    }
}
