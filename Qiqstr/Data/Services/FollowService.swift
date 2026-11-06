import Foundation
import Observation
import QiqstrCore

@MainActor
@Observable
final class FollowService {
    static let shared = FollowService()
    private(set) var following: Set<String> = []
    private(set) var pending: Set<String> = []
    private(set) var isLoaded = false
    private var generation = 0
    private var queue: Task<Void, Never>?

    var count: Int { following.count }

    func isFollowing(_ pubkey: String) -> Bool { following.contains(pubkey) }
    func isPending(_ pubkey: String) -> Bool { pending.contains(pubkey) }

    func reset() {
        generation += 1
        following = []
        pending = []
        isLoaded = false
        queue = nil
    }

    func load() async {
        guard let me = Session.shared.pubkey else { return }
        let generation = self.generation
        await SyncService.shared.syncFollowingList(me)
        guard generation == self.generation else { return }
        let list = await localList(me)
        guard generation == self.generation else { return }
        if pending.isEmpty { following = list }
        isLoaded = true
    }

    func refresh() async {
        guard let me = Session.shared.pubkey else { return }
        let generation = self.generation
        let list = await localList(me)
        guard generation == self.generation, pending.isEmpty else { return }
        following = list
    }

    func follow(_ pubkey: String) async throws {
        try await mutate([pubkey]) { $0.insert(pubkey) }
    }

    func unfollow(_ pubkey: String) async throws {
        try await mutate([pubkey]) { $0.remove(pubkey) }
    }

    func follow(many pubkeys: [String]) async throws {
        let targets = Set(pubkeys.filter { !$0.isEmpty })
        guard !targets.isEmpty else { return }
        try await mutate(targets) { $0.formUnion(targets) }
    }

    private func mutate(_ targets: Set<String>, _ change: @escaping (inout Set<String>) -> Void) async throws {
        let previous = queue
        let task = Task { () throws -> Void in
            await previous?.value
            try await self.apply(targets, change)
        }
        queue = Task { _ = try? await task.value }
        try await task.value
    }

    private func apply(_ targets: Set<String>, _ change: (inout Set<String>) -> Void) async throws {
        guard let me = Session.shared.pubkey, let key = Session.shared.privateKey else { throw CoreError(L("privateKeyNotFound")) }
        let generation = self.generation
        let snapshot = following
        var optimistic = following
        change(&optimistic)
        optimistic.remove(me)
        following = optimistic
        pending.formUnion(targets)
        defer { if generation == self.generation { pending.subtract(targets) } }
        do {
            var list = try await authoritativeList(me)
            guard generation == self.generation else { return }
            change(&list)
            list.remove(me)
            let event = try createFollowEvent(followingPubkeys: list.sorted(), privateKeyHex: key)
            try await SyncService.shared.publish(event)
            guard generation == self.generation else { return }
            try? await dbSaveFollowingList(pubkeyHex: me, followsHex: Array(list))
            following = list
            DataBus.shared.feedChanged()
        } catch {
            if generation == self.generation { following = snapshot }
            throw error
        }
    }

    private func authoritativeList(_ me: String) async throws -> Set<String> {
        let local = await localList(me)
        if !local.isEmpty { return local }
        let events = await SyncService.shared.fetchEvents(["kinds": [3], "authors": [me], "limit": 1], timeout: 8)
        if let latest = events.max(by: { $0.int("created_at") < $1.int("created_at") }) {
            try? await dbSaveFollowingListFromEvent(eventJson: JSON.string(latest), selfPubkeyHex: me)
            let fromEvent = Set(latest.tags().filter { $0.count > 1 && $0[0] == "p" }.map { $0[1] })
            return fromEvent.union(await localList(me)).subtracting([me])
        }
        let connected = (try? await getConnectedRelayCount()) ?? 0
        if connected == 0 && !Session.shared.isNewAccount { throw CoreError(L("followListUnavailable")) }
        return []
    }

    private func localList(_ me: String) async -> Set<String> {
        Set(((try? await dbGetFollowingList(pubkeyHex: me)) ?? []).filter { !$0.isEmpty && $0.lowercased() != me.lowercased() })
    }
}
