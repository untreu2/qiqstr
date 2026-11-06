import Foundation
import Observation

@MainActor
@Observable
final class MuteService {
    static let shared = MuteService()
    private(set) var mutedPubkeys: [String] = []
    private(set) var mutedWords: [String] = []

    func isMuted(_ pubkey: String) -> Bool { mutedPubkeys.contains(pubkey) }
    func reset() {}
    func load() async {}
    func mute(_ pubkey: String) async throws {}
    func unmute(_ pubkey: String) async throws {}
    func addWord(_ word: String) async throws {}
    func removeWord(_ word: String) async throws {}
}
