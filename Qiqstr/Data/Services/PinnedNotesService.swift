import Foundation
import Observation

@MainActor
@Observable
final class PinnedNotesService {
    static let shared = PinnedNotesService()
    private(set) var pinnedIds: [String] = []

    func isPinned(_ noteId: String) -> Bool { pinnedIds.contains(noteId) }
    func reset() {}
    func load(for pubkey: String) async -> [String] { [] }
    func toggle(_ noteId: String) async throws {}
}
