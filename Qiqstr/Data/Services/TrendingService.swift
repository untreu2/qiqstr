import Foundation
import QiqstrCore

struct TrendingSnapshot: Sendable {
    var noteIds: [String]
    var hashtags: [String]
}

@MainActor
final class TrendingService {
    static let shared = TrendingService()
    static let ttl: TimeInterval = 600
    private static let noteLimit = 40
    private static let hashtagLimit = 16
    private static let fallbackRelays = ["wss://nostr.wine", "wss://relay.damus.io", "wss://relay.primal.net", "wss://nos.lol"]

    private var noteIds: [String] = []
    private var notesLoadedAt: Date?
    private var hashtags: [String] = []
    private var hashtagsLoadedAt: Date?
    private var inflightNotes: Task<[String], Never>?
    private var inflightHashtags: Task<[String], Never>?

    func cachedNoteIds() -> [String] { noteIds }
    func cachedHashtags() -> [String] { hashtags }

    func trendingNoteIds(force: Bool = false) async -> [String] {
        if !force, let loaded = notesLoadedAt, Date().timeIntervalSince(loaded) < Self.ttl, !noteIds.isEmpty { return noteIds }
        if let inflightNotes { return await inflightNotes.value }
        let task = Task.detached { await Self.fetchTrendingNotes() }
        inflightNotes = task
        let ids = await task.value
        inflightNotes = nil
        if !ids.isEmpty {
            noteIds = ids
            notesLoadedAt = Date()
        }
        return noteIds
    }

    func trendingHashtags(force: Bool = false) async -> [String] {
        if !force, let loaded = hashtagsLoadedAt, Date().timeIntervalSince(loaded) < Self.ttl, !hashtags.isEmpty { return hashtags }
        if let inflightHashtags { return await inflightHashtags.value }
        let task = Task.detached { await Self.fetchTrendingHashtags() }
        inflightHashtags = task
        let tags = await task.value
        inflightHashtags = nil
        if !tags.isEmpty {
            hashtags = tags
            hashtagsLoadedAt = Date()
        }
        return hashtags
    }

    func hydratedNotes(_ ids: [String]) async -> [Note] {
        await SearchService.notes(ids: ids, context: .current)
    }

    nonisolated private static func fetchTrendingNotes() async -> [String] {
        let primal = await primalCache("explore_global_trending_24h", args: ["limit": noteLimit], timeout: 10)
        if let ids = await storeTrending(primal), !ids.isEmpty { return ids }
        return await nostrWineTrending()
    }

    nonisolated private static func storeTrending(_ events: [JSONObject]) async -> [String]? {
        let notes = events.filter { $0.int("kind") == 1 && $0.str("id") != nil && $0.str("sig") != nil }
        guard !notes.isEmpty else { return nil }
        let profiles = events.filter { $0.int("kind") == 0 && $0.str("sig") != nil }
        _ = try? await dbSaveEvents(eventsJson: JSON.string(notes + profiles))
        let order = events.first { $0.int("kind") == 10000113 }
            .flatMap { JSON.object($0["content"] as? String) }
            .map { ($0["elements"] as? [String]) ?? [] } ?? []
        let available = Set(notes.compactMap { $0.str("id") })
        var ids = order.filter(available.contains)
        var seen = Set(ids)
        ids += notes.compactMap { $0.str("id") }.filter { seen.insert($0).inserted }
        await fetchProfiles(for: notes)
        return Array(ids.prefix(noteLimit))
    }

    nonisolated private static func nostrWineTrending() async -> [String] {
        guard let url = URL(string: "https://api.nostr.wine/trending?order=reactions&hours=24&limit=\(noteLimit)") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [JSONObject] else { return [] }
        let ids = rows.compactMap { $0.str("event_id") }
        guard !ids.isEmpty else { return [] }
        let raw = try? await fetchEventsFromRelays(filterJson: JSON.string(["ids": ids, "kinds": [1]]), relayUrls: fallbackRelays, timeoutSecs: 8)
        let events = JSON.array(raw)
        guard !events.isEmpty else { return [] }
        _ = try? await dbSaveEvents(eventsJson: JSON.string(events))
        await fetchProfiles(for: events)
        let found = Set(events.compactMap { $0.str("id") })
        return ids.filter(found.contains)
    }

    nonisolated private static func fetchTrendingHashtags() async -> [String] {
        let events = await primalCache("trending_hashtags_4h", args: [:], timeout: 12)
        let rows = events.first { $0.int("kind") == 10000116 }.flatMap { JSON.any($0["content"] as? String) as? [[Any]] } ?? []
        var seen = Set<String>()
        return rows.compactMap { row in
            guard let tag = (row.first as? String)?.lowercased(), SearchService.hashtag(from: tag) == tag, seen.insert(tag).inserted else { return nil }
            return tag
        }
        .prefix(hashtagLimit)
        .map { $0 }
    }

    static func hashtags(from notes: [Note], limit: Int = 12) -> [String] {
        var counts: [String: Int] = [:]
        for note in notes {
            for tag in Set(note.hashtags.map { $0.lowercased() }) where SearchService.hashtag(from: tag) == tag {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(limit).map(\.key)
    }

    nonisolated private static func fetchProfiles(for events: [JSONObject]) async {
        let pubkeys = SearchService.pubkeys(in: events)
        guard !pubkeys.isEmpty else { return }
        await MainActor.run { SyncService.shared.fetchMissingProfiles(pubkeys) }
    }

    nonisolated private static func primalCache(_ name: String, args: JSONObject, timeout: Int) async -> [JSONObject] {
        guard let url = URL(string: RelayConfig.primalCacheUrl) else { return [] }
        let socket = URLSession.shared.webSocketTask(with: url)
        socket.maximumMessageSize = 4 * 1024 * 1024
        socket.resume()
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(timeout))
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer {
            watchdog.cancel()
            socket.cancel(with: .normalClosure, reason: nil)
        }
        let subscription = "qt_\(Int(Date().timeIntervalSince1970 * 1000))"
        let request: [Any] = ["REQ", subscription, ["cache": [name, args]]]
        do { try await socket.send(.string(JSON.string(request))) } catch { return [] }
        var events: [JSONObject] = []
        while !Task.isCancelled {
            guard let message = try? await socket.receive() else { break }
            guard case .string(let raw) = message, let frame = JSON.any(raw) as? [Any], let type = frame.first as? String else { continue }
            if type == "EOSE" || type == "CLOSED" || type == "NOTICE" { break }
            if type == "EVENT", frame.count >= 3, let event = frame[2] as? JSONObject { events.append(event) }
        }
        try? await socket.send(.string(JSON.string(["CLOSE", subscription])))
        return events
    }
}
