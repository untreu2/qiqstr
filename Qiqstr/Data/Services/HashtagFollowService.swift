import Foundation
import Observation
import QiqstrCore

@MainActor
@Observable
final class HashtagFollowService {
    static let shared = HashtagFollowService()
    private static let kind = 10015

    private(set) var tags: [String] = []
    private(set) var isLoaded = false
    private var intents: [String: Bool] = [:]

    @ObservationIgnored private var confirmed: [String] = []
    @ObservationIgnored private var extraTags: [[String]] = []
    @ObservationIgnored private var content = ""
    @ObservationIgnored private var latestCreatedAt = -1
    @ObservationIgnored private var hasAuthoritative = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var queue: Task<Void, Never>?

    func isFollowing(_ tag: String) -> Bool {
        guard let tag = Self.normalize(tag) else { return false }
        return tags.contains(tag)
    }

    func isPending(_ tag: String) -> Bool {
        guard let tag = Self.normalize(tag) else { return false }
        return intents[tag] != nil
    }

    static func normalize(_ raw: String) -> String? {
        let value = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).drop { $0 == "#" }).lowercased()
        guard !value.isEmpty, value.count <= 64, value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
        return value
    }

    func reset() {
        generation += 1
        tags = []
        intents = [:]
        confirmed = []
        extraTags = []
        content = ""
        latestCreatedAt = -1
        hasAuthoritative = false
        isLoaded = false
        queue = nil
    }

    func load() async {
        guard let me = Session.shared.pubkey else { return }
        let generation = self.generation
        if let local = await localEvent(me), generation == self.generation { adopt(local) }
        guard generation == self.generation else { return }
        await fetchRemote(me, generation: generation)
        guard generation == self.generation else { return }
        isLoaded = true
    }

    func follow(_ tag: String) async throws {
        try await setFollowing(tag, true)
    }

    func unfollow(_ tag: String) async throws {
        try await setFollowing(tag, false)
    }

    func toggle(_ tag: String) async throws {
        try await setFollowing(tag, !isFollowing(tag))
    }

    func recentCount(_ tag: String, window: Int = 86400) async -> Int? {
        guard let tag = Self.normalize(tag) else { return nil }
        let filter: JSONObject = ["kinds": [1], "#t": [tag], "since": TimeFormat.now - window]
        guard let count = try? await dbCountEvents(filterJson: JSON.string(filter)) else { return nil }
        return Int(count)
    }

    private func setFollowing(_ raw: String, _ follow: Bool) async throws {
        guard let tag = Self.normalize(raw) else { throw CoreError(L("feedTopicInvalid")) }
        let key = try Session.shared.requireSigner()
        guard let me = Session.shared.pubkey else { throw CoreError(L("privateKeyNotFound")) }
        let generation = self.generation
        intents[tag] = follow
        tags = projected()
        let previous = queue
        let task = Task { () throws -> Void in
            await previous?.value
            try await self.commit(tag, follow, key: key, me: me, generation: generation)
        }
        queue = Task { _ = try? await task.value }
        do {
            try await task.value
        } catch {
            if generation == self.generation { settle(tag, follow) }
            throw error
        }
    }

    private func commit(_ tag: String, _ follow: Bool, key: String, me: String, generation: Int) async throws {
        guard generation == self.generation else { return }
        if !isLoaded || !hasAuthoritative || confirmed.isEmpty {
            await fetchRemote(me, generation: generation)
            guard generation == self.generation else { return }
            guard hasAuthoritative else { throw CoreError(L("feedTopicsUnavailable")) }
        }
        var list = confirmed
        if follow {
            guard !list.contains(tag) else { return settle(tag, follow) }
            list.append(tag)
        } else {
            guard list.contains(tag) else { return settle(tag, follow) }
            list.removeAll { $0 == tag }
        }
        let eventJson = try createSignedEvent(kind: UInt16(Self.kind), content: content, tags: list.map { ["t", $0] } + extraTags, privateKeyHex: key)
        let event = try await SyncService.shared.publish(eventJson)
        guard generation == self.generation else { return }
        latestCreatedAt = max(latestCreatedAt, event.int("created_at"))
        confirmed = list
        settle(tag, follow)
    }

    private func settle(_ tag: String, _ follow: Bool) {
        if intents[tag] == follow { intents[tag] = nil }
        tags = projected()
    }

    private func projected() -> [String] {
        var list = confirmed
        for (tag, follow) in intents.sorted(by: { $0.key < $1.key }) {
            if follow, !list.contains(tag) { list.append(tag) }
            if !follow { list.removeAll { $0 == tag } }
        }
        return list
    }

    private func fetchRemote(_ me: String, generation: Int) async {
        let remote = await SyncService.shared
            .fetchEvents(["kinds": [Self.kind], "authors": [me], "limit": 1], timeout: 8)
            .filter { $0.str("pubkey") == me && $0.int("kind") == Self.kind }
            .max { $0.int("created_at") < $1.int("created_at") }
        guard generation == self.generation else { return }
        if let remote {
            if remote.int("created_at") > latestCreatedAt {
                _ = try? await dbSaveEvents(eventsJson: JSON.string([remote]))
                guard generation == self.generation else { return }
            }
            adopt(remote)
            return
        }
        guard !hasAuthoritative else { return }
        let connected = (try? await getConnectedRelayCount()) ?? 0
        guard generation == self.generation else { return }
        if connected > 0 { hasAuthoritative = true }
    }

    private func adopt(_ event: JSONObject) {
        let created = event.int("created_at")
        guard created >= latestCreatedAt else { return }
        latestCreatedAt = created
        hasAuthoritative = true
        content = event.str("content") ?? ""
        extraTags = event.tags().filter { !($0.first == "t" && $0.count > 1 && Self.normalize($0[1]) != nil) }
        var seen = Set<String>()
        confirmed = event.tags().compactMap { tag in
            guard tag.count > 1, tag[0] == "t", let value = Self.normalize(tag[1]), seen.insert(value).inserted else { return nil }
            return value
        }
        tags = projected()
    }

    private func localEvent(_ pubkey: String) async -> JSONObject? {
        let filter = JSON.string(["kinds": [Self.kind], "authors": [pubkey]])
        return JSON.array(try? await dbQueryEvents(filterJson: filter, limit: 1))
            .filter { $0.str("pubkey") == pubkey }
            .max { $0.int("created_at") < $1.int("created_at") }
    }
}
