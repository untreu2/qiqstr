import Foundation
import Observation

nonisolated struct ComposeDraftMedia: Codable, Hashable, Sendable {
    var url: String
    var sha256: String
    var mimeType: String
    var size: Int
    var width: Double?
    var height: Double?
    var blurhash: String?
    var altText: String
    var isVideo: Bool
}

nonisolated struct ComposeDraftPoll: Codable, Hashable, Sendable {
    var options: [String]
    var multiple: Bool
    var endsAt: Date?
}

nonisolated struct ComposeDraft: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case newNote, reply, quote
    }

    var id: String
    var kind: Kind
    var targetId: String?
    var targetPubkey: String?
    var text: String
    var mentions: [String: String]
    var media: [ComposeDraftMedia]
    var contentWarningEnabled: Bool
    var contentWarningReason: String
    var poll: ComposeDraftPoll?
    var updatedAt: Date

    var contextKey: String {
        switch kind {
        case .newNote: "new"
        case .reply: "reply-\(targetId ?? "")"
        case .quote: "quote-\(targetId ?? "")"
        }
    }

    var preview: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
    }
}

@MainActor
@Observable
final class DraftStore {
    static let shared = DraftStore()

    private(set) var drafts: [ComposeDraft] = []
    @ObservationIgnored private var owner: String?
    @ObservationIgnored var pendingDraftId: String?

    func all() -> [ComposeDraft] {
        ensureLoaded()
        return drafts
    }

    func draft(_ id: String) -> ComposeDraft? {
        all().first { $0.id == id }
    }

    func latest(contextKey: String) -> ComposeDraft? {
        all().filter { $0.contextKey == contextKey }.max { $0.updatedAt < $1.updatedAt }
    }

    func save(_ draft: ComposeDraft) {
        ensureLoaded()
        drafts.removeAll { $0.id == draft.id }
        drafts.insert(draft, at: 0)
        drafts.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func delete(_ id: String) {
        ensureLoaded()
        guard drafts.contains(where: { $0.id == id }) else { return }
        drafts.removeAll { $0.id == id }
        persist()
    }

    private func ensureLoaded() {
        let pubkey = Session.shared.pubkey
        guard pubkey != owner else { return }
        owner = pubkey
        drafts = pubkey.flatMap(Self.read) ?? []
    }

    private func persist() {
        guard let owner, let url = Self.fileURL(owner) else { return }
        guard let data = try? JSONEncoder().encode(drafts) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func read(_ owner: String) -> [ComposeDraft]? {
        guard let url = fileURL(owner), let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode([ComposeDraft].self, from: data))?.sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func fileURL(_ owner: String) -> URL? {
        guard owner.count == 64, owner.allSatisfy(\.isHexDigit),
              let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("Drafts", isDirectory: true).appendingPathComponent("\(owner).json")
    }
}
