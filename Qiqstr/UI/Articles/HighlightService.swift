import Foundation
import QiqstrCore

struct ArticleHighlight: Identifiable, Hashable, Sendable {
    var id: String
    var pubkey: String
    var content: String
    var comment: String?
    var createdAt: Int

    init?(json j: JSONObject) {
        guard j.int("kind") == 9802, let id = j.str("id"), let pubkey = j.str("pubkey") else { return nil }
        let content = ((j["content"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        self.id = id
        self.pubkey = pubkey
        self.content = content
        self.createdAt = j.int("created_at")
        self.comment = j.tags().first { $0.first == "comment" && $0.count > 1 }?[1].trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

extension ArticleAddress {
    var coordinate: String { "\(kind):\(pubkey):\(identifier)" }
}

@MainActor
enum HighlightService {
    static func local(for address: ArticleAddress) async -> [ArticleHighlight] {
        let filter = JSON.string(["kinds": [9802], "#a": [address.coordinate], "limit": 300] as JSONObject)
        return parse(JSON.array(try? await dbQueryEvents(filterJson: filter, limit: 300)))
    }

    static func fetch(for address: ArticleAddress) async -> [ArticleHighlight] {
        let events = await SyncService.shared.fetchEvents(["kinds": [9802], "#a": [address.coordinate], "limit": 300], timeout: 8)
        if !events.isEmpty {
            _ = try? await dbSaveEvents(eventsJson: JSON.string(events))
            SyncService.shared.fetchMissingProfiles(Array(Set(events.compactMap { $0.str("pubkey") })))
        }
        return await local(for: address)
    }

    static func publish(text: String, context: String, comment: String, article: Article) async throws -> ArticleHighlight {
        guard let key = Session.shared.privateKey, Session.shared.pubkey != nil else { throw CoreError(L("authenticationRequired")) }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw CoreError(L("highlightEmpty")) }
        var tags: [[String]] = [
            ["a", article.address.coordinate],
            ["p", article.pubkey, "", "author"],
            ["alt", "Highlight: \(content.prefix(80))"],
        ]
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContext.isEmpty, trimmedContext != content { tags.append(["context", trimmedContext]) }
        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedComment.isEmpty { tags.append(["comment", trimmedComment]) }
        let json = try createSignedEvent(kind: 9802, content: content, tags: tags, privateKeyHex: key)
        let event = try await SyncService.shared.publish(json)
        guard let highlight = ArticleHighlight(json: event) else { throw CoreError(L("highlightFailed")) }
        return highlight
    }

    private static func parse(_ events: [JSONObject]) -> [ArticleHighlight] {
        let muted = Set(Session.shared.mutedPubkeys)
        var seen = Set<String>()
        return events.compactMap(ArticleHighlight.init(json:))
            .filter { !muted.contains($0.pubkey) && seen.insert($0.id).inserted }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
