import Foundation
import Observation
import QiqstrCore

enum FollowError: LocalizedError {
    case listUnavailable
    case listNotFound
    var errorDescription: String? { L("followListUnavailable") }
}

@MainActor
@Observable
final class FollowService {
    static let shared = FollowService()
    private(set) var following: Set<String> = []
    private(set) var pending: Set<String> = []
    private(set) var isLoaded = false
    private var generation = 0
    private var queue: Task<Void, Never>?
    @ObservationIgnored private var verifiedAt: Date?
    private let verificationWindow: TimeInterval = 60

    var count: Int { following.count }

    func isFollowing(_ pubkey: String) -> Bool { following.contains(pubkey) }
    func isPending(_ pubkey: String) -> Bool { pending.contains(pubkey) }

    func reset() {
        generation += 1
        following = []
        pending = []
        isLoaded = false
        queue = nil
        verifiedAt = nil
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

    func follow(_ pubkey: String, creatingList: Bool = false) async throws {
        try await mutate([pubkey], creatingList: creatingList) { $0.insert(pubkey) }
    }

    func unfollow(_ pubkey: String) async throws {
        try await mutate([pubkey], creatingList: false) { $0.remove(pubkey) }
    }

    func follow(many pubkeys: [String], creatingList: Bool = false) async throws {
        let targets = Set(pubkeys.filter { !$0.isEmpty })
        guard !targets.isEmpty else { return }
        try await mutate(targets, creatingList: creatingList) { $0.formUnion(targets) }
    }

    private func mutate(_ targets: Set<String>, creatingList: Bool, _ change: @escaping (inout Set<String>) -> Void) async throws {
        let previous = queue
        let task = Task { () throws -> Void in
            await previous?.value
            try await self.apply(targets, creatingList: creatingList, change)
        }
        queue = Task { _ = try? await task.value }
        try await task.value
    }

    private func apply(_ targets: Set<String>, creatingList: Bool, _ change: (inout Set<String>) -> Void) async throws {
        let key = try Session.shared.requireSigner()
        guard let me = Session.shared.pubkey?.lowercased() else { throw CoreError(L("privateKeyNotFound")) }
        let generation = self.generation
        let snapshot = following
        var optimistic = following
        change(&optimistic)
        optimistic.remove(me)
        following = optimistic
        pending.formUnion(targets)
        defer { if generation == self.generation { pending.subtract(targets) } }
        do {
            let base = try await latestContactList(me, creatingList: creatingList)
            guard generation == self.generation else { return }
            let baseTags = try Self.tags(in: base)
            var list = Self.pubkeys(in: baseTags)
            change(&list)
            list.remove(me)
            let event = try createSignedEvent(kind: 3, content: (base?["content"] as? String) ?? "", tags: Self.mergedTags(baseTags, list: list), privateKeyHex: key)
            try await SyncService.shared.publish(event)
            guard generation == self.generation else { return }
            verifiedAt = Date()
            following = list
            DataBus.shared.feedChanged()
            Task { await SyncService.shared.syncFeed(force: true) }
        } catch {
            if generation == self.generation { following = snapshot }
            throw error
        }
    }

    private func latestContactList(_ me: String, creatingList: Bool) async throws -> JSONObject? {
        let filter: JSONObject = ["kinds": [3], "authors": [me], "limit": 1]
        var candidates = JSON.array(try? await dbQueryEvents(filterJson: JSON.string(filter), limit: 1))
        let isFresh = verifiedAt.map { Date().timeIntervalSince($0) < verificationWindow } ?? false
        if !isFresh || candidates.isEmpty {
            let remote = await SyncService.shared.fetchContactLists(of: me)
            if remote.isEmpty {
                if !candidates.isEmpty { throw FollowError.listUnavailable }
            } else {
                verifiedAt = Date()
            }
            candidates += remote
        }
        let newest = candidates
            .filter { $0.int("kind") == 3 && $0.str("pubkey")?.lowercased() == me }
            .max { ($0.int("created_at"), $0.str("id") ?? "") < ($1.int("created_at"), $1.str("id") ?? "") }
        if let newest {
            try? await dbSaveFollowingListFromEvent(eventJson: JSON.string(newest), selfPubkeyHex: me)
            return newest
        }
        if ((try? await getConnectedRelayCount()) ?? 0) == 0 { throw FollowError.listUnavailable }
        guard creatingList || Session.shared.isNewAccount || AccountStore.wasCreatedHere(me) else { throw FollowError.listNotFound }
        return nil
    }

    private static func tags(in event: JSONObject?) throws -> [[String]] {
        guard let event else { return [] }
        guard let tags = event["tags"] as? [[String]] else { throw FollowError.listUnavailable }
        return tags
    }

    private static func pubkeys(in tags: [[String]]) -> Set<String> {
        Set(tags.filter { $0.count > 1 && $0[0] == "p" && !$0[1].isEmpty }.map { $0[1].lowercased() })
    }

    private static func mergedTags(_ base: [[String]], list: Set<String>) -> [[String]] {
        var tags: [[String]] = []
        var kept: Set<String> = []
        for tag in base where !tag.isEmpty {
            guard tag.count > 1, tag[0] == "p" else {
                tags.append(tag)
                continue
            }
            let pubkey = tag[1].lowercased()
            if list.contains(pubkey), kept.insert(pubkey).inserted { tags.append(tag) }
        }
        return tags + list.subtracting(kept).sorted().map { ["p", $0] }
    }

    private func localList(_ me: String) async -> Set<String> {
        Set(((try? await dbGetFollowingList(pubkeyHex: me)) ?? []).filter { !$0.isEmpty && $0.lowercased() != me.lowercased() })
    }
}
