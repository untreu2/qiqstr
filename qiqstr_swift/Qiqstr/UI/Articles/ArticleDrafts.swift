import Foundation
import Observation
import QiqstrCore

/// A long-form article (NIP-23, kind 30023) being written or edited.
nonisolated struct ArticleDraft: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    /// The article's `d` identifier. Empty until the first publish, then fixed so updates replace the same article.
    var dTag: String = ""
    var title: String = ""
    var summary: String = ""
    var image: String = ""
    var hashtags: [String] = []
    var content: String = ""
    /// Set when the draft edits an article that is already published.
    var publishedAt: Int?
    var updatedAt = Date()

    init() {}

    init(article: Article) {
        dTag = article.dTag
        title = article.title
        summary = article.summary ?? ""
        image = article.image ?? ""
        hashtags = article.hashtags
        content = article.content
        publishedAt = article.publishedAt
    }

    var isEditingPublished: Bool { publishedAt != nil }

    var isBlank: Bool {
        [title, summary, image, content].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } && hashtags.isEmpty
    }

    var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var wordCount: Int { content.split(whereSeparator: \.isWhitespace).count }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L("untitledArticle") : trimmed
    }

    /// Hashtags typed as "nostr, #bitcoin writing" become ["nostr", "bitcoin", "writing"].
    static func parseHashtags(_ text: String) -> [String] {
        var seen = Set<String>()
        return text
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// A readable, URL-safe identifier such as "my-first-article-3f9a".
    static func makeIdentifier(title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        var slug = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                slug.unicodeScalars.append(scalar)
            } else if !slug.isEmpty, !slug.hasSuffix("-") {
                slug.append("-")
            }
            if slug.count >= 48 { break }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(6))
        return slug.isEmpty ? suffix : "\(slug)-\(suffix)"
    }
}

/// Unpublished article drafts, stored on this device for each account.
@MainActor
@Observable
final class ArticleDraftStore {
    static let shared = ArticleDraftStore()

    private(set) var drafts: [ArticleDraft] = []
    @ObservationIgnored private var owner: String?

    func all() -> [ArticleDraft] {
        ensureLoaded()
        return drafts
    }

    func draft(id: String) -> ArticleDraft? {
        all().first { $0.id == id }
    }

    /// The saved draft that edits the published article with this identifier, if there is one.
    func draft(editing dTag: String) -> ArticleDraft? {
        guard !dTag.isEmpty else { return nil }
        return all().first { $0.dTag == dTag && $0.isEditingPublished }
    }

    func save(_ draft: ArticleDraft) {
        ensureLoaded()
        if draft.isBlank {
            delete(draft.id)
            return
        }
        var updated = draft
        updated.updatedAt = Date()
        drafts.removeAll { $0.id == draft.id }
        drafts.insert(updated, at: 0)
        persist()
    }

    func delete(_ id: String) {
        ensureLoaded()
        guard drafts.contains(where: { $0.id == id }) else { return }
        drafts.removeAll { $0.id == id }
        persist()
    }

    func reset() {
        owner = nil
        drafts = []
    }

    private func ensureLoaded() {
        let pubkey = Session.shared.pubkey
        guard pubkey != owner else { return }
        owner = pubkey
        drafts = pubkey.flatMap(Self.read) ?? []
    }

    private func persist() {
        guard let owner, let url = Self.fileURL(owner) else { return }
        if drafts.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(drafts) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func read(_ owner: String) -> [ArticleDraft]? {
        guard let url = fileURL(owner), let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode([ArticleDraft].self, from: data))?.sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func fileURL(_ owner: String) -> URL? {
        guard owner.count == 64, owner.allSatisfy(\.isHexDigit) else { return nil }
        return AppDirectories.support.appendingPathComponent("ArticleDrafts", isDirectory: true).appendingPathComponent("\(owner).json")
    }
}

@MainActor
enum ArticlePublisher {
    static let kind = 30023

    /// Signs and publishes the draft as a kind 30023 event. Returns the published article's address.
    @discardableResult
    static func publish(_ draft: ArticleDraft) async throws -> ArticleAddress {
        guard let me = Session.shared.pubkey else { throw CoreError(L("noRelayConnection")) }
        try Session.shared.requireSigner()
        guard draft.canPublish else { throw CoreError(L("articleNeedsTitleAndText")) }
        let identifier = draft.dTag.isEmpty ? ArticleDraft.makeIdentifier(title: draft.title) : draft.dTag
        let now = TimeFormat.now
        let content = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
        var tags: [[String]] = [
            ["d", identifier],
            ["title", draft.title.trimmingCharacters(in: .whitespacesAndNewlines)],
            ["published_at", String(draft.publishedAt ?? now)],
        ]
        let summary = draft.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty { tags.append(["summary", summary]) }
        let image = draft.image.trimmingCharacters(in: .whitespacesAndNewlines)
        if !image.isEmpty { tags.append(["image", image]) }
        tags += draft.hashtags.map { ["t", $0] }
        tags += MarkdownParser.pubkeys(in: content).filter { $0 != me }.map { ["p", $0] }
        let event = try signEvent(kind: UInt16(kind), content: content, tags: tags)
        try await SyncService.shared.publish(event)
        ArticleDraftStore.shared.delete(draft.id)
        DataBus.shared.feedChanged()
        return ArticleAddress(pubkey: me, identifier: identifier)
    }

    /// Asks relays to delete the article (NIP-09) and removes it from the local database.
    static func delete(_ article: Article) async throws {
        try Session.shared.requireSigner()
        let tags: [[String]] = [
            ["e", article.id],
            ["a", "\(kind):\(article.pubkey):\(article.dTag)"],
            ["k", String(kind)],
        ]
        let event = try signEvent(kind: 5, content: "", tags: tags)
        try await SyncService.shared.publish(event)
        _ = try? await dbDeleteEventsByIds(eventIds: [article.id])
        if let draft = ArticleDraftStore.shared.draft(editing: article.dTag) { ArticleDraftStore.shared.delete(draft.id) }
        DataBus.shared.feedChanged()
    }
}
