import Foundation
import Observation
import QiqstrCore

nonisolated struct DiscoverFeed: Identifiable, Hashable, Codable, Sendable {
    enum Content: String, Codable, Sendable { case notes, reads }

    var pubkey: String
    var dTag: String
    var name: String
    var about: String
    var image: String?
    var content: Content

    var id: String { "\(pubkey):\(dTag)" }
}

nonisolated struct RisingPerson: Identifiable, Hashable, Sendable {
    var pubkey: String
    var increase: Int
    var followers: Int
    var id: String { pubkey }
}

nonisolated struct TopZap: Identifiable, Hashable, Sendable {
    var id: String
    var sender: String
    var receiver: String
    var sats: Int
    var comment: String
    var noteId: String?
    var createdAt: Int
}

nonisolated struct TrendingTopic: Identifiable, Hashable, Sendable {
    var tag: String
    var count: Int
    var id: String { tag }
}

@MainActor
@Observable
final class ExploreService {
    static let shared = ExploreService()

    private static let ttl: TimeInterval = 600
    private static let mediaPage = 30
    private static let pinnedKey = "explore_pinned_feeds"
    private static let storedKinds: Set<Int> = [0, 1, 6, 30023]

    private(set) var feeds: [DiscoverFeed] = []
    private(set) var people: [RisingPerson] = []
    private(set) var zaps: [TopZap] = []
    private(set) var topics: [TrendingTopic] = []
    private(set) var media: [ProfileMediaEntry] = []
    private(set) var zapNotes: [String: Note] = [:]
    private(set) var loading: Set<String> = []
    private(set) var failed: Set<String> = []
    private(set) var mediaExhausted = false
    private(set) var isLoadingMoreMedia = false
    private(set) var pinned: [DiscoverFeed] = []

    @ObservationIgnored private var loadedAt: [String: Date] = [:]
    @ObservationIgnored private var mediaCursor: Int?
    @ObservationIgnored private var mediaIds: Set<String> = []
    @ObservationIgnored private var pinnedOwner: String?

    func isLoading(_ key: String) -> Bool { loading.contains(key) }

    func loadAll(force: Bool = false) async {
        async let f: Void = loadFeeds(force: force)
        async let p: Void = loadPeople(force: force)
        async let z: Void = loadZaps(force: force)
        async let t: Void = loadTopics(force: force)
        async let m: Void = loadMedia(force: force)
        _ = await (f, p, z, t, m)
    }

    private func begin(_ key: String, force: Bool, isEmpty: Bool) -> Bool {
        if loading.contains(key) { return false }
        if !force, !isEmpty, let at = loadedAt[key], Date().timeIntervalSince(at) < Self.ttl { return false }
        loading.insert(key)
        return true
    }

    private func finish(_ key: String, ok: Bool) {
        loading.remove(key)
        if ok {
            failed.remove(key)
            loadedAt[key] = Date()
        } else {
            failed.insert(key)
        }
    }

    private static func store(_ events: [JSONObject]) async {
        let keep = PrimalCache.signed(events, kinds: storedKinds)
        guard !keep.isEmpty else { return }
        _ = try? await dbSaveEvents(eventsJson: JSON.string(keep))
    }

    func loadFeeds(force: Bool = false) async {
        guard begin("feeds", force: force, isEmpty: feeds.isEmpty) else { return }
        let events = await PrimalCache.request("get_featured_dvm_feeds", args: [:], timeout: 12)
        await Self.store(events)
        let kinds = Dictionary(PrimalCache.contents(events, kind: 10000159).compactMap { info -> (String, String)? in
            guard let id = info.str("event_id"), let kind = info.str("kind") else { return nil }
            return (id, kind)
        }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let parsed = events.filter { $0.int("kind") == 31990 }.compactMap { event -> DiscoverFeed? in
            guard let pubkey = event.str("pubkey"),
                  let dTag = event.tags().first(where: { $0.count > 1 && $0[0] == "d" })?[1],
                  let info = JSON.object(event["content"] as? String),
                  let name = info.str("name") else { return nil }
            let amount = info.str("amount") ?? "free"
            guard amount == "free" || amount == "0" else { return nil }
            let content: DiscoverFeed.Content = kinds[event.str("id") ?? ""] == "reads" ? .reads : .notes
            let feed = DiscoverFeed(pubkey: pubkey, dTag: dTag, name: name, about: info.str("about") ?? "", image: info.str("picture") ?? info.str("image"), content: content)
            return seen.insert(feed.id).inserted ? feed : nil
        }
        if !parsed.isEmpty { feeds = parsed.filter { $0.content == .notes } + parsed.filter { $0.content == .reads } }
        finish("feeds", ok: !parsed.isEmpty)
    }

    func feed(id: String) -> DiscoverFeed? {
        feeds.first { $0.id == id } ?? pinnedFeeds.first { $0.id == id }
    }

    private func feedArgs(_ feed: DiscoverFeed, limit: Int) -> JSONObject {
        var args: JSONObject = ["dvm_pubkey": feed.pubkey, "dvm_id": feed.dTag, "limit": limit]
        if let me = Session.shared.pubkey { args["user_pubkey"] = me }
        return args
    }

    func feedNotes(_ feed: DiscoverFeed, limit: Int = 40) async -> [Note]? {
        let events = await PrimalCache.request("dvm_feed", args: feedArgs(feed, limit: limit), timeout: 15)
        guard !events.isEmpty else { return nil }
        await Self.store(events)
        let notes = PrimalCache.signed(events, kinds: [1])
        var ids = PrimalCache.order(events).filter { id in notes.contains { $0.str("id") == id } }
        if ids.isEmpty { ids = notes.compactMap { $0.str("id") } }
        SyncService.shared.fetchMissingProfiles(SearchService.pubkeys(in: notes))
        return await SearchService.notes(ids: ids, context: .current)
    }

    func feedArticles(_ feed: DiscoverFeed, limit: Int = 30) async -> [Article]? {
        let events = await PrimalCache.request("dvm_feed", args: feedArgs(feed, limit: limit), timeout: 15)
        guard !events.isEmpty else { return nil }
        await Self.store(events)
        let raw = PrimalCache.signed(events, kinds: [30023])
        var ids = PrimalCache.order(events).filter { id in raw.contains { $0.str("id") == id } }
        if ids.isEmpty { ids = raw.compactMap { $0.str("id") } }
        SyncService.shared.fetchMissingProfiles(SearchService.pubkeys(in: raw))
        var articles: [Article] = []
        for id in ids {
            if let json = try? await dbGetHydratedArticle(eventId: id), let obj = JSON.object(json) {
                let article = Article(json: obj)
                if !article.id.isEmpty { articles.append(article) }
            }
        }
        return articles
    }

    func loadPeople(force: Bool = false) async {
        guard begin("people", force: force, isEmpty: people.isEmpty) else { return }
        let events = await PrimalCache.request("explore_people", args: ["limit": 40], timeout: 12)
        await Self.store(events)
        let stats = (PrimalCache.content(events, kind: 10000157) as? JSONObject) ?? [:]
        let followers = (PrimalCache.content(events, kind: 10000133) as? JSONObject) ?? [:]
        var order = PrimalCache.order(events)
        if order.isEmpty { order = Array(stats.keys) }
        let me = Session.shared.pubkey
        let parsed = order.compactMap { pubkey -> RisingPerson? in
            guard pubkey != me, let info = stats[pubkey] as? JSONObject else { return nil }
            let total = (followers[pubkey] as? NSNumber)?.intValue ?? info.int("count")
            return RisingPerson(pubkey: pubkey, increase: info.int("increase"), followers: total)
        }
        if !parsed.isEmpty {
            people = parsed
            await ProfileCache.shared.load(parsed.map(\.pubkey))
        }
        finish("people", ok: !parsed.isEmpty)
    }

    func loadZaps(force: Bool = false) async {
        guard begin("zaps", force: force, isEmpty: zaps.isEmpty) else { return }
        let events = await PrimalCache.request("explore_zaps", args: ["limit": 30], timeout: 12)
        await Self.store(events)
        let receipts = Dictionary(events.filter { $0.int("kind") == 9735 }.compactMap { e in e.str("id").map { ($0, e) } }, uniquingKeysWith: { first, _ in first })
        let parsed = PrimalCache.contents(events, kind: 10000129).compactMap { info -> TopZap? in
            guard let id = info.str("zap_receipt_id"), let sender = info.str("sender"), let receiver = info.str("receiver") else { return nil }
            var comment = ""
            if let receipt = receipts[id],
               let description = receipt.tags().first(where: { $0.count > 1 && $0[0] == "description" })?[1],
               let request = JSON.object(description) {
                comment = ((request["content"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return TopZap(id: id, sender: sender, receiver: receiver, sats: info.int("amount_sats"), comment: comment, noteId: info.str("event_id"), createdAt: info.int("created_at"))
        }
        .sorted { $0.sats > $1.sats }
        if !parsed.isEmpty {
            zaps = parsed
            let noteIds = Array(Set(parsed.compactMap(\.noteId)))
            let notes = await SearchService.notes(ids: noteIds, context: .current)
            zapNotes = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            await ProfileCache.shared.load(Array(Set(parsed.flatMap { [$0.sender, $0.receiver] })))
        }
        finish("zaps", ok: !parsed.isEmpty)
    }

    func loadTopics(force: Bool = false) async {
        guard begin("topics", force: force, isEmpty: topics.isEmpty) else { return }
        let events = await PrimalCache.request("explore_topics", args: [:], timeout: 12)
        let counts = (PrimalCache.content(events, kind: 10000160) as? JSONObject) ?? [:]
        let parsed = counts.compactMap { key, value -> TrendingTopic? in
            let tag = key.lowercased()
            guard SearchService.hashtag(from: tag) == tag, let count = (value as? NSNumber)?.intValue, count > 0 else { return nil }
            return TrendingTopic(tag: tag, count: count)
        }
        .sorted { $0.count == $1.count ? $0.tag < $1.tag : $0.count > $1.count }
        if !parsed.isEmpty { topics = Array(parsed.prefix(60)) }
        finish("topics", ok: !parsed.isEmpty)
    }

    func loadMedia(force: Bool = false) async {
        guard begin("media", force: force, isEmpty: media.isEmpty) else { return }
        let (entries, cursor) = await fetchMedia(until: nil)
        if !entries.isEmpty {
            media = entries
            mediaIds = Set(entries.map(\.id))
            mediaCursor = cursor
            mediaExhausted = cursor == nil
        }
        finish("media", ok: !entries.isEmpty)
    }

    func loadMoreMedia() async {
        guard !isLoadingMoreMedia, !mediaExhausted, let cursor = mediaCursor else { return }
        isLoadingMoreMedia = true
        defer { isLoadingMoreMedia = false }
        let (entries, next) = await fetchMedia(until: cursor)
        let fresh = entries.filter { mediaIds.insert($0.id).inserted }
        media.append(contentsOf: fresh)
        mediaCursor = next
        if fresh.isEmpty || next == nil { mediaExhausted = true }
    }

    private func fetchMedia(until: Int?) async -> ([ProfileMediaEntry], Int?) {
        var args: JSONObject = ["limit": Self.mediaPage]
        if let until { args["until"] = until }
        let events = await PrimalCache.request("explore_media", args: args, timeout: 12)
        await Self.store(events)
        let raw = PrimalCache.signed(events, kinds: [1])
        var ids = PrimalCache.order(events).filter { id in raw.contains { $0.str("id") == id } }
        if ids.isEmpty { ids = raw.sorted { $0.int("created_at") > $1.int("created_at") }.compactMap { $0.str("id") } }
        let notes = await SearchService.notes(ids: ids, context: .current)
        var seen = Set<String>()
        var entries: [ProfileMediaEntry] = []
        for note in notes where !note.isRepost && !Self.isSensitive(note) {
            for item in NoteContentCache.content(for: note).media where seen.insert(item.url).inserted {
                entries.append(ProfileMediaEntry(item: item, noteId: note.id))
            }
        }
        let cursor = PrimalCache.page(events).map(\.since).flatMap { $0 > 0 && $0 != until ? $0 : nil }
        return (entries, raw.isEmpty ? nil : cursor)
    }

    private static let adultTags: Set<String> = [
        "nsfw", "nude", "nudes", "nudity", "naked", "porn", "porno", "adult", "18plus", "18", "xxx", "sexy", "sex",
        "boobs", "tits", "ass", "lewd", "hentai", "erotic", "erotica", "onlyfans", "nsfwart", "milf", "fetish", "lingerie",
    ]

    static func isSensitive(_ note: Note) -> Bool {
        if note.contentWarning != nil { return true }
        if note.hashtags.contains(where: { adultTags.contains($0.lowercased()) }) { return true }
        let text = note.content.lowercased()
        if text.contains("🔞") { return true }
        return text.range(of: #"#(nsfw|nude|nudes|porn|xxx|lewd|onlyfans)(?![\p{L}\p{N}_])"#, options: .regularExpression) != nil
    }

    private var pinnedStorageKey: String { "\(Self.pinnedKey)_\(Session.shared.pubkey ?? "anon")" }

    var pinnedFeeds: [DiscoverFeed] {
        refreshPinnedIfNeeded()
        return pinned
    }

    private func refreshPinnedIfNeeded() {
        let owner = Session.shared.pubkey
        guard owner != pinnedOwner else { return }
        pinnedOwner = owner
        let data = UserDefaults.standard.data(forKey: pinnedStorageKey)
        pinned = data.flatMap { try? JSONDecoder().decode([DiscoverFeed].self, from: $0) } ?? []
    }

    func isPinned(_ feed: DiscoverFeed) -> Bool { pinnedFeeds.contains { $0.id == feed.id } }

    func togglePin(_ feed: DiscoverFeed) {
        refreshPinnedIfNeeded()
        if let index = pinned.firstIndex(where: { $0.id == feed.id }) {
            pinned.remove(at: index)
        } else {
            pinned.append(feed)
        }
        if let data = try? JSONEncoder().encode(pinned) { UserDefaults.standard.set(data, forKey: pinnedStorageKey) }
    }
}
