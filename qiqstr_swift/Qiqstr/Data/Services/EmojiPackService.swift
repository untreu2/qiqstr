import Foundation
import Observation
import QiqstrCore

nonisolated struct EmojiPack: Identifiable, Hashable, Sendable, Codable {
    var id: String { coordinate }
    var coordinate: String
    var title: String
    var author: String
    var emojis: [CustomEmoji]

    init(coordinate: String, title: String, author: String, emojis: [CustomEmoji]) {
        self.coordinate = coordinate
        self.title = title
        self.author = author
        self.emojis = emojis
    }

    init?(event: JSONObject) {
        guard event.int("kind") == EmojiPackService.packKind, let pubkey = event.str("pubkey") else { return nil }
        let tags = event.tags()
        guard let dTag = tags.first(where: { $0.count > 1 && $0[0] == "d" })?[1], !dTag.isEmpty else { return nil }
        let emojis = Self.unique(tags.compactMap(CustomEmoji.init(tag:)))
        guard !emojis.isEmpty else { return nil }
        coordinate = "\(EmojiPackService.packKind):\(pubkey):\(dTag)"
        title = tags.first { $0.count > 1 && ($0[0] == "title" || $0[0] == "name") && !$0[1].isEmpty }?[1] ?? dTag
        author = pubkey
        self.emojis = emojis
    }

    static func unique(_ emojis: [CustomEmoji]) -> [CustomEmoji] {
        var seen: Set<String> = []
        return emojis.filter { seen.insert($0.shortcode).inserted }
    }
}

@MainActor
@Observable
final class EmojiPackService {
    static let shared = EmojiPackService()
    static let listKind = 10030
    static let packKind = 30030
    static let ownCoordinate = "own"

    private(set) var packs: [EmojiPack] = []
    private(set) var discovered: [EmojiPack] = []
    private(set) var isLoaded = false
    private(set) var isDiscovering = false
    private(set) var busy: Set<String> = []
    @ObservationIgnored private var owner: String?
    @ObservationIgnored private var generation = 0

    var allEmojis: [CustomEmoji] { EmojiPack.unique(packs.flatMap(\.emojis)) }

    func contains(_ coordinate: String) -> Bool { packs.contains { $0.coordinate == coordinate } }

    func reset() {
        generation += 1
        owner = nil
        packs = []
        discovered = []
        isLoaded = false
        busy = []
    }

    func load() async {
        guard let me = Session.shared.pubkey else { return }
        let generation = self.generation
        if owner != me {
            owner = me
            packs = Self.cached(me)
        }
        let events = await SyncService.shared.fetchReplaceable(kind: Self.listKind, author: me)
        guard generation == self.generation else { return }
        if let newest = events.max(by: { $0.int("created_at") < $1.int("created_at") }) {
            let resolved = await resolve(newest)
            guard generation == self.generation else { return }
            packs = resolved
            persist()
        }
        isLoaded = true
    }

    private func resolve(_ list: JSONObject) async -> [EmojiPack] {
        let tags = list.tags()
        var result: [EmojiPack] = []
        let own = EmojiPack.unique(tags.compactMap(CustomEmoji.init(tag:)))
        if !own.isEmpty { result.append(EmojiPack(coordinate: Self.ownCoordinate, title: L("emojiMyEmoji"), author: list.str("pubkey") ?? "", emojis: own)) }
        let coordinates = tags.filter { $0.count > 1 && $0[0] == "a" && $0[1].hasPrefix("\(Self.packKind):") }.map { $0[1] }
        guard !coordinates.isEmpty else { return result }
        let fetched = await fetchPacks(coordinates)
        for coordinate in coordinates {
            if let pack = fetched[coordinate] ?? packs.first(where: { $0.coordinate == coordinate }) { result.append(pack) }
        }
        return result
    }

    private func fetchPacks(_ coordinates: [String]) async -> [String: EmojiPack] {
        var authors: Set<String> = []
        var names: Set<String> = []
        for coordinate in coordinates {
            let parts = coordinate.split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { continue }
            authors.insert(parts[1])
            names.insert(parts[2])
        }
        guard !authors.isEmpty else { return [:] }
        let filter: JSONObject = ["kinds": [Self.packKind], "authors": Array(authors), "#d": Array(names), "limit": 200]
        let events = await SyncService.shared.fetchEvents(filter, timeout: 8)
        var newest: [String: (Int, EmojiPack)] = [:]
        for event in events {
            guard let pack = EmojiPack(event: event) else { continue }
            let created = event.int("created_at")
            if (newest[pack.coordinate]?.0 ?? -1) < created { newest[pack.coordinate] = (created, pack) }
        }
        return newest.mapValues(\.1)
    }

    func discover() async {
        guard !isDiscovering else { return }
        isDiscovering = true
        defer { isDiscovering = false }
        let follows = FollowService.shared.following
        async let fromFollows: [JSONObject] = follows.isEmpty ? [] : SyncService.shared.fetchEvents(["kinds": [Self.packKind], "authors": Array(follows.prefix(400)), "limit": 150], timeout: 8)
        async let recent = SyncService.shared.fetchEvents(["kinds": [Self.packKind], "limit": 150], timeout: 8)
        let muted = Set(Session.shared.mutedPubkeys)
        let trust = WebOfTrustService.shared
        var newest: [String: (Int, EmojiPack)] = [:]
        for event in await fromFollows + recent {
            guard let pack = EmojiPack(event: event), !muted.contains(pack.author), pack.emojis.count >= 2 else { continue }
            if trust.isReady, !trust.isTrusted(pack.author) { continue }
            let created = event.int("created_at")
            if (newest[pack.coordinate]?.0 ?? -1) < created { newest[pack.coordinate] = (created, pack) }
        }
        let followed = Set(follows)
        discovered = newest.values.map(\.1).sorted { a, b in
            let af = followed.contains(a.author), bf = followed.contains(b.author)
            return af != bf ? af : a.emojis.count > b.emojis.count
        }
        await ProfileCache.shared.load(Array(Set(discovered.prefix(60).map(\.author))))
    }

    func add(_ pack: EmojiPack) async throws {
        guard !contains(pack.coordinate) else { return }
        try await edit(pack.coordinate) { tags in tags + [["a", pack.coordinate]] }
        packs.append(pack)
        persist()
    }

    func remove(_ pack: EmojiPack) async throws {
        guard pack.coordinate != Self.ownCoordinate else { return }
        try await edit(pack.coordinate) { tags in tags.filter { !($0.count > 1 && $0[0] == "a" && $0[1] == pack.coordinate) } }
        packs.removeAll { $0.coordinate == pack.coordinate }
        persist()
    }

    private func edit(_ coordinate: String, _ change: ([[String]]) -> [[String]]) async throws {
        guard let me = Session.shared.pubkey else { return }
        let key = try Session.shared.requireSigner()
        guard busy.insert(coordinate).inserted else { return }
        defer { busy.remove(coordinate) }
        let base = try await SyncService.shared.latestEditableEvent(kind: Self.listKind, author: me, allowingNew: true)
        let event = try createSignedEvent(kind: UInt16(Self.listKind), content: (base?["content"] as? String) ?? "", tags: change(base?.tags() ?? []), privateKeyHex: key)
        try await SyncService.shared.publish(event)
    }

    private func persist() {
        guard let owner, let data = try? JSONEncoder().encode(packs) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey(owner))
    }

    private static func cached(_ pubkey: String) -> [EmojiPack] {
        guard let data = UserDefaults.standard.data(forKey: storageKey(pubkey)) else { return [] }
        return (try? JSONDecoder().decode([EmojiPack].self, from: data)) ?? []
    }

    private static func storageKey(_ pubkey: String) -> String { "emoji_packs_\(pubkey)" }
}
