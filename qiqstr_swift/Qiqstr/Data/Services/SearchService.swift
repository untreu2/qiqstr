import Foundation
import QiqstrCore

enum SearchKind: CaseIterable, Sendable {
    case people, notes, articles

    var eventKind: Int {
        switch self {
        case .people: 0
        case .notes: 1
        case .articles: 30023
        }
    }

    var relays: [String] {
        switch self {
        case .people: [RelayConfig.vertexRelayUrl, "wss://search.nos.today", "wss://nostr.wine"]
        case .notes, .articles: ["wss://search.nos.today", "wss://nostr.wine", "wss://relay.ditto.pub"]
        }
    }
}

struct SearchContext: Sendable {
    var pubkey: String?
    var mutedPubkeys: [String]
    var mutedWords: [String]

    @MainActor static var current: SearchContext {
        let session = Session.shared
        return SearchContext(pubkey: session.pubkey, mutedPubkeys: session.mutedPubkeys, mutedWords: session.mutedWords)
    }
}

struct SearchBatch: Sendable {
    var events: [JSONObject]
    var failed: Bool
}

nonisolated enum SearchService {
    static let remoteTimeout: UInt32 = 6
    private static let entityPrefixes = ["npub1", "nprofile1", "note1", "nevent1", "naddr1"]

    @MainActor
    static func entityURL(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if let url = URL(string: text), let host = url.host(), !host.isEmpty, let last = url.pathComponents.last {
            text = last
        }
        text = Nip19.stripScheme(text).lowercased()
        guard entityPrefixes.contains(where: text.hasPrefix) else { return nil }
        return Nip19.decode(text) == nil ? nil : URL(string: "nostr:\(text)")
    }

    static func hexId(from input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count == 64, text.allSatisfy(\.isHexDigit) else { return nil }
        return text.lowercased()
    }

    static func hashtag(from input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard !tag.isEmpty, tag.count <= 40, tag.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
        return tag.lowercased()
    }

    static func localProfiles(_ query: String, limit: Int, context: SearchContext) async -> [Profile] {
        let muted = Set(context.mutedPubkeys)
        return JSON.array(try? await dbSearchProfiles(query: query, limit: UInt32(limit)))
            .map { Profile(json: $0) }
            .filter { !$0.pubkey.isEmpty && !muted.contains($0.pubkey) }
    }

    static func localNotes(_ query: String, limit: Int, context: SearchContext) async -> [Note] {
        let ids = JSON.array(try? await dbSearchNotes(query: query, limit: UInt32(limit))).compactMap { $0.str("id") }
        return await notes(ids: ids, context: context).sorted { $0.createdAt > $1.createdAt }
    }

    static func localArticles(_ query: String, limit: Int, context: SearchContext) async -> [Article] {
        let needle = query.lowercased()
        let raw = try? await dbGetHydratedArticles(authorsHex: nil, limit: 250, mutedPubkeys: context.mutedPubkeys, mutedWords: context.mutedWords)
        var seen = Set<String>()
        let matches = JSON.array(raw).map(Article.init(json:)).filter { article in
            guard !article.id.isEmpty, seen.insert("\(article.pubkey):\(article.dTag)").inserted else { return false }
            return article.title.lowercased().contains(needle)
                || (article.summary ?? "").lowercased().contains(needle)
                || (article.authorName ?? "").lowercased().contains(needle)
                || article.hashtags.contains { $0.lowercased().contains(needle) }
        }
        return Array(matches.prefix(limit))
    }

    static func remote(_ kind: SearchKind, query: String, limit: Int) -> AsyncStream<SearchBatch> {
        AsyncStream { continuation in
            let task = Task.detached {
                await withTaskGroup(of: SearchBatch.self) { group in
                    for relay in kind.relays {
                        group.addTask { await fetch(kind: kind, query: query, limit: limit, relay: relay) }
                    }
                    for await batch in group {
                        continuation.yield(batch)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func fetch(kind: SearchKind, query: String, limit: Int, relay: String) async -> SearchBatch {
        let filter: JSONObject = ["kinds": [kind.eventKind], "search": query, "limit": limit]
        do {
            let raw = try await fetchEventsFromRelays(filterJson: JSON.string(filter), relayUrls: [relay], timeoutSecs: remoteTimeout)
            let events = JSON.array(raw).filter { $0.int("kind") == kind.eventKind && $0.str("id") != nil && !isLikelySpam($0) }
            return SearchBatch(events: events, failed: false)
        } catch {
            return SearchBatch(events: [], failed: true)
        }
    }

    private static func isLikelySpam(_ event: JSONObject) -> Bool {
        guard event.int("kind") == 1 else { return false }
        let words = ((event["content"] as? String) ?? "").split(whereSeparator: \.isWhitespace)
        guard words.count >= 4 else { return false }
        let tags = words.filter { $0.hasPrefix("#") }.count
        return Double(tags) / Double(words.count) > 0.6
    }

    static func store(_ events: [JSONObject]) async {
        guard !events.isEmpty else { return }
        _ = try? await dbSaveEvents(eventsJson: JSON.string(events))
    }

    static func notes(ids: [String], context: SearchContext) async -> [Note] {
        guard !ids.isEmpty else { return [] }
        let raw = try? await dbGetHydratedNotesByIds(eventIds: ids, mutedPubkeys: context.mutedPubkeys, mutedWords: context.mutedWords, currentUserPubkeyHex: context.pubkey)
        let byId = Dictionary(Note.list(raw).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byId[$0] }
    }

    static func profiles(from events: [JSONObject], context: SearchContext) -> [Profile] {
        let muted = Set(context.mutedPubkeys)
        var seen = Set<String>()
        return events.compactMap { event in
            guard let pubkey = event.str("pubkey"), !muted.contains(pubkey), seen.insert(pubkey).inserted,
                  let metadata = JSON.object(event["content"] as? String) else { return nil }
            var profile = Profile(json: metadata, fallbackPubkey: pubkey)
            profile.pubkey = pubkey
            return profile
        }
    }

    static func articles(from events: [JSONObject]) async -> [Article] {
        var result: [Article] = []
        var seen = Set<String>()
        for id in events.compactMap({ $0.str("id") }) {
            guard let raw = try? await dbGetHydratedArticle(eventId: id), let json = JSON.object(raw) else { continue }
            let article = Article(json: json)
            guard !article.id.isEmpty, !article.title.isEmpty, seen.insert("\(article.pubkey):\(article.dTag)").inserted else { continue }
            result.append(article)
        }
        return result
    }

    static func pubkeys(in events: [JSONObject]) -> [String] {
        Array(Set(events.compactMap { $0.str("pubkey") }))
    }
}
