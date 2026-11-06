import Foundation

@MainActor
final class InteractionService {
    static let shared = InteractionService()

    func react(to note: Note, content: String = "+") async throws {}
    func repost(_ note: Note) async throws {}
    func undoRepost(_ note: Note) async throws {}
    func delete(_ note: Note) async throws {}
    func publishNote(content: String, mediaUrls: [String]) async throws -> String { "" }
    func publishReply(to note: Note, content: String, mediaUrls: [String]) async throws -> String { "" }
    func publishQuote(of note: Note, content: String, mediaUrls: [String]) async throws -> String { "" }
    func report(pubkey: String, noteId: String?, reason: String) async throws {}
}
