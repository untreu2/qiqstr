import Foundation
import Observation
import QiqstrCore

nonisolated enum FollowInterest: String, CaseIterable, Identifiable, Hashable, Sendable {
    case bitcoin, nostr, art, photography, music, tech, science, news, sports, books, gaming, food, travel, memes, privacy, dev

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .bitcoin: "bitcoinsign.circle"
        case .nostr: "bolt.horizontal.circle"
        case .art: "paintpalette"
        case .photography: "camera"
        case .music: "music.note"
        case .tech: "cpu"
        case .science: "atom"
        case .news: "newspaper"
        case .sports: "figure.run"
        case .books: "book"
        case .gaming: "gamecontroller"
        case .food: "fork.knife"
        case .travel: "airplane"
        case .memes: "face.smiling"
        case .privacy: "lock.shield"
        case .dev: "chevron.left.forwardslash.chevron.right"
        }
    }

    var keywords: [String] {
        switch self {
        case .bitcoin: ["bitcoin", "bitcoiners", "btc", "sats", "satoshi", "lightning", "stacker", "stackers", "stacking", "hodl", "hodlers", "plebs", "zap", "einundzwanzig", "coretards", "cashu"]
        case .nostr: ["nostr", "nostrich", "nostriches", "napplet", "relay", "relays", "newbie", "starter", "welcome", "jumpstart", "recommended", "nip"]
        case .art: ["art", "arts", "artist", "artists", "artwork", "creative", "creatives", "aesthete", "aesthetes", "design", "designer", "designers", "illustration", "illustrator", "drawing", "painting", "painter", "anime"]
        case .photography: ["photo", "photos", "photography", "photographer", "photographers", "camera", "olas", "film"]
        case .music: ["music", "musician", "musicians", "wavlake", "band", "bands", "song", "songs", "dj", "musik", "muzik"]
        case .tech: ["tech", "technology", "software", "ai", "llm", "agi", "hardware", "computing", "engineering", "teknoloji", "technik"]
        case .science: ["science", "scientist", "scientists", "research", "researcher", "physics", "biology", "chemistry", "math", "space", "astronomy", "medicine", "health", "bilim", "wissenschaft"]
        case .news: ["news", "journalist", "journalists", "journalism", "media", "press", "reporter", "reporters", "noticias", "nachrichten", "haber", "новости"]
        case .sports: ["sport", "sports", "football", "soccer", "basketball", "fitness", "running", "cycling", "spor"]
        case .books: ["book", "books", "reading", "reader", "readers", "read", "writer", "writers", "author", "authors", "literature", "poetry", "poet", "poets", "kitap", "bücher"]
        case .gaming: ["game", "games", "gamer", "gamers", "gaming", "esports", "chess", "nintendo"]
        case .food: ["food", "foodie", "cook", "cooking", "chef", "chefs", "recipe", "recipes", "farm", "farmer", "farmers", "growers", "garden", "gardening", "homestead", "coffee", "bbq"]
        case .travel: ["travel", "traveler", "travelers", "traveller", "nomad", "nomads", "adventure", "hiking", "outdoors", "seyahat", "reisen"]
        case .memes: ["meme", "memes", "humor", "humour", "funny", "comedy", "shitpost", "shitposters", "jokes"]
        case .privacy: ["privacy", "cypherpunk", "cypherpunks", "monero", "xmr", "encryption", "freedom", "rights", "surveillance", "sovereign", "opsec", "tor"]
        case .dev: ["dev", "devs", "developer", "developers", "desenvolvedores", "programming", "programmer", "programmers", "coder", "coders", "code", "opensource", "engineer", "engineers", "github", "rust", "napplet"]
        }
    }

    func relevance(to pack: FollowPack) -> Int {
        if matches(pack.titleTokens) { return 2 }
        if self == .nostr { return 0 }
        return matches(pack.tokens) ? 1 : 0
    }

    func matches(_ tokens: Set<String>) -> Bool {
        keywords.contains { keyword in
            if tokens.contains(keyword) { return true }
            guard keyword.count >= 5 else { return false }
            return tokens.contains { $0.hasPrefix(keyword) }
        }
    }
}

nonisolated struct FollowPack: Identifiable, Hashable, Sendable {
    let id: String
    let kind: Int
    let author: String
    let title: String
    let summary: String
    let image: String
    let members: [String]
    let topics: [String]
    let createdAt: Int
    let tokens: Set<String>
    let titleTokens: Set<String>

    static func tokenize(_ values: [String]) -> Set<String> {
        let text = values.joined(separator: " ").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        return Set(text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
    }

    init(id: String, kind: Int, author: String, title: String, summary: String, image: String, members: [String], topics: [String], createdAt: Int) {
        self.id = id
        self.kind = kind
        self.author = author
        self.title = title
        self.summary = summary
        self.image = image
        self.members = members
        self.topics = topics
        self.createdAt = createdAt
        self.tokens = Self.tokenize([title, summary] + topics)
        self.titleTokens = Self.tokenize([title] + topics)
    }

    init?(event: JSONObject) {
        let kind = event.int("kind")
        guard kind == 39089 || kind == 30000, let author = event.str("pubkey") else { return nil }
        let tags = event.tags()
        func value(_ name: String) -> String {
            (tags.first { $0.count > 1 && $0[0] == name }?[1] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func first(_ names: String...) -> String { names.lazy.map(value).first { !$0.isEmpty } ?? "" }
        let title = first("title", "name")
        guard !title.isEmpty else { return nil }
        var seen = Set<String>()
        let members = tags.compactMap { tag -> String? in
            guard tag.count > 1, tag[0] == "p" else { return nil }
            let key = tag[1].lowercased()
            guard key.count == 64, key.allSatisfy(\.isHexDigit), seen.insert(key).inserted else { return nil }
            return key
        }
        let content = (event["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let usableContent = kind == 39089 && content.count < 400 && !content.contains("?iv=") ? content : ""
        self.init(
            id: "\(kind):\(author):\(value("d"))",
            kind: kind,
            author: author,
            title: title,
            summary: first("description", "summary").isEmpty ? usableContent : first("description", "summary"),
            image: value("image"),
            members: members,
            topics: tags.filter { $0.count > 1 && $0[0] == "t" }.map { $0[1].lowercased() },
            createdAt: event.int("created_at")
        )
    }

    var isAcceptable: Bool {
        guard (Self.minimumMembers...Self.maximumMembers).contains(members.count) else { return false }
        let tokens = self.tokens
        guard tokens.isDisjoint(with: Self.blockedWords) else { return false }
        return !tokens.contains { token in Self.blockedPrefixes.contains { token.hasPrefix($0) } }
    }

    static let minimumMembers = 5
    static let maximumMembers = 300
    private static let blockedWords: Set<String> = ["bot", "bots", "mute", "muted", "mutes", "nsfw", "porn", "xxx", "test", "chuds"]
    private static let blockedPrefixes = ["scam", "spam", "blacklist", "blocklist", "blocked"]
}

@MainActor
@Observable
final class FollowPackService {
    static let shared = FollowPackService()

    private(set) var packs: [FollowPack] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private var lastLoad: Date?
    private var task: Task<Void, Never>?

    private static let packRelays = ["wss://relay.damus.io", "wss://nos.lol", "wss://nostr.wine", "wss://relay.nostr.band"]
    private static let listRelays = ["wss://nos.lol", "wss://nostr.wine"]
    private static let freshness: TimeInterval = 1800

    func prefetch() {
        if task != nil { return }
        if let lastLoad, Date().timeIntervalSince(lastLoad) < Self.freshness, !packs.isEmpty { return }
        isLoading = true
        task = Task { [weak self] in
            await self?.fetchAll()
            self?.finish()
        }
    }

    func reload() async {
        lastLoad = nil
        prefetch()
        await task?.value
    }

    func waitUntilLoaded() async {
        prefetch()
        await task?.value
    }

    func ranked(for interests: Set<FollowInterest>) -> [FollowPack] {
        let primary = scored(interests, requireMatch: !interests.isEmpty)
        guard primary.count < 4, !interests.isEmpty else { return primary }
        let ids = Set(primary.map(\.id))
        let general = scored([.nostr], requireMatch: true).filter { !ids.contains($0.id) }
        return primary + general.prefix(4 - primary.count)
    }

    private func scored(_ interests: Set<FollowInterest>, requireMatch: Bool) -> [FollowPack] {
        packs.compactMap { pack -> (FollowPack, Double)? in
            let relevance = interests.reduce(0) { $0 + $1.relevance(to: pack) }
            if requireMatch && relevance == 0 { return nil }
            return (pack, Double(relevance) * 5 + Self.quality(pack))
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }

    private static func quality(_ pack: FollowPack) -> Double {
        var score = log2(Double(max(pack.members.count, 1)))
        if !pack.image.isEmpty { score += 1 }
        if !pack.summary.isEmpty { score += 1.5 }
        if pack.kind == 39089 { score += 1 }
        if pack.members.count > 150 { score -= 2.5 }
        return score
    }

    private func finish() {
        isLoading = false
        hasLoaded = true
        lastLoad = Date()
        task = nil
    }

    private func fetchAll() async {
        let requests = Self.packRelays.map { ($0, 39089, 300) } + Self.listRelays.map { ($0, 30000, 250) }
        await withTaskGroup(of: [FollowPack].self) { group in
            for (relay, kind, limit) in requests {
                group.addTask { await Self.fetch(relay: relay, kind: kind, limit: limit) }
            }
            for await batch in group where !batch.isEmpty {
                merge(batch)
            }
        }
    }

    private func merge(_ batch: [FollowPack]) {
        var byId = Dictionary(packs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for pack in batch where (byId[pack.id]?.createdAt ?? -1) < pack.createdAt {
            byId[pack.id] = pack
        }
        var byTitle: [String: FollowPack] = [:]
        for pack in byId.values {
            let key = pack.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = byTitle[key], existing.createdAt >= pack.createdAt { continue }
            byTitle[key] = pack
        }
        packs = byTitle.values.sorted { $0.createdAt > $1.createdAt }
    }

    nonisolated private static func fetch(relay: String, kind: Int, limit: Int) async -> [FollowPack] {
        let filter = JSON.string(["kinds": [kind], "limit": limit])
        guard let raw = try? await fetchEventsFromRelays(filterJson: filter, relayUrls: [relay], timeoutSecs: 6) else { return [] }
        return JSON.array(raw).compactMap(FollowPack.init(event:)).filter(\.isAcceptable)
    }
}
