import Foundation
import Observation

@MainActor
@Observable
final class BookmarkService {
    static let shared = BookmarkService()
    private(set) var bookmarkedIds: [String] = []

    func isBookmarked(_ noteId: String) -> Bool { bookmarkedIds.contains(noteId) }
    func reset() {}
    func load() async {}
    func toggle(_ noteId: String) async throws {}
}
