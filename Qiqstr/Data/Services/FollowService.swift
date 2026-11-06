import Foundation
import Observation

@MainActor
@Observable
final class FollowService {
    static let shared = FollowService()
    private(set) var following: Set<String> = []

    func isFollowing(_ pubkey: String) -> Bool { following.contains(pubkey) }
    func reset() {}
    func load() async {}
    func follow(_ pubkey: String) async throws {}
    func unfollow(_ pubkey: String) async throws {}
    func follow(many pubkeys: [String]) async throws {}
}
