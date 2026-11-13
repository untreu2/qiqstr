import Foundation
import Observation
import QiqstrCore

@MainActor
@Observable
final class WebOfTrustService {
    static let shared = WebOfTrustService()

    static let filterNotificationsKey = "wot_filter_notifications"
    static let filterRepliesKey = "wot_filter_replies"
    static let showSensitiveContentKey = "show_sensitive_content"
    static let minimumMutualFollows = 2
    static let maxSampledFollows = 1000
    static let refreshInterval: TimeInterval = 6 * 3600

    static var filtersNotifications: Bool { UserDefaults.standard.object(forKey: filterNotificationsKey) as? Bool ?? true }
    static var filtersReplies: Bool { UserDefaults.standard.object(forKey: filterRepliesKey) as? Bool ?? true }
    static var showsSensitiveContent: Bool {
        AppStorePolicy.allowsSensitiveContentToggle && UserDefaults.standard.bool(forKey: showSensitiveContentKey)
    }

    private(set) var follows: Set<String> = []
    private(set) var scores: [String: Int] = [:]
    private(set) var trustedCount = 0
    private(set) var isBuilding = false
    private(set) var progress: Double = 0
    private(set) var updatedAt: Date?

    private var owner: String?
    private var generation = 0
    private var buildTask: Task<Void, Never>?

    var isReady: Bool { owner != nil && !follows.isEmpty && (updatedAt != nil || !scores.isEmpty) }

    func isTrusted(_ pubkey: String) -> Bool {
        guard let owner, isReady else { return true }
        if pubkey == owner || follows.contains(pubkey) || FollowService.shared.isFollowing(pubkey) { return true }
        return (scores[pubkey] ?? 0) >= Self.minimumMutualFollows
    }

    func score(_ pubkey: String) -> Int {
        scores[pubkey] ?? 0
    }

    func reset() {
        generation += 1
        buildTask?.cancel()
        buildTask = nil
        owner = nil
        follows = []
        scores = [:]
        trustedCount = 0
        isBuilding = false
        progress = 0
        updatedAt = nil
    }

    func load(for pubkey: String) async {
        guard owner != pubkey else { return }
        reset()
        owner = pubkey
        let generation = self.generation
        if let cached = await WebOfTrustGraph.readCache(owner: pubkey) {
            guard generation == self.generation else { return }
            apply(cached)
            if Date().timeIntervalSince(cached.updatedAt) < Self.refreshInterval { return }
        }
        rebuild()
    }

    func rebuild() {
        guard let owner, !isBuilding else { return }
        let generation = self.generation
        isBuilding = true
        progress = 0
        buildTask = Task { [weak self] in
            await self?.build(owner: owner, generation: generation)
        }
    }

    private func build(owner: String, generation: Int) async {
        var followList = FollowService.shared.following
        if followList.isEmpty {
            followList = Set((try? await dbGetFollowingList(pubkeyHex: owner)) ?? [])
        }
        followList.remove(owner)
        guard generation == self.generation else { return }
        follows = followList
        let sample = Array(followList.shuffled().prefix(Self.maxSampledFollows))
        let graph = WebOfTrustGraph(owner: owner, follows: followList, minimum: Self.minimumMutualFollows)
        let chunks = stride(from: 0, to: sample.count, by: 100).map { Array(sample[$0..<min($0 + 100, sample.count)]) }

        for chunk in chunks {
            await graph.ingestLocal(authors: chunk)
        }
        guard generation == self.generation, !Task.isCancelled else { return }
        if !chunks.isEmpty { apply(await graph.snapshot(), finished: false) }

        var done = 0
        for wave in stride(from: 0, to: chunks.count, by: 3).map({ Array(chunks[$0..<min($0 + 3, chunks.count)]) }) {
            await withTaskGroup(of: Void.self) { group in
                for chunk in wave {
                    group.addTask { await graph.ingestRemote(authors: chunk) }
                }
            }
            guard generation == self.generation, !Task.isCancelled else { return }
            done += wave.count
            progress = Double(done) / Double(chunks.count)
            apply(await graph.snapshot(), finished: false)
        }

        let final = await graph.snapshot()
        guard generation == self.generation else { return }
        apply(final, finished: true)
        await graph.writeCache(final)
    }

    private func apply(_ snapshot: WebOfTrustSnapshot, finished: Bool = true) {
        if !finished, updatedAt != nil, snapshot.trustedCount < trustedCount { return }
        if !snapshot.follows.isEmpty || follows.isEmpty { follows = snapshot.follows }
        scores = snapshot.scores
        trustedCount = snapshot.trustedCount
        if finished {
            updatedAt = snapshot.updatedAt
            isBuilding = false
            progress = 1
        }
    }
}

nonisolated struct WebOfTrustSnapshot: Sendable {
    var owner: String
    var follows: Set<String>
    var scores: [String: Int]
    var trustedCount: Int
    var updatedAt: Date
}

actor WebOfTrustGraph {
    private let owner: String
    private let follows: Set<String>
    private let minimum: Int
    private var index: [String: Int32] = [:]
    private var keys: [String] = []
    private var latest: [String: (createdAt: Int, contacts: [Int32])] = [:]

    init(owner: String, follows: Set<String>, minimum: Int) {
        self.owner = owner
        self.follows = follows
        self.minimum = minimum
    }

    func ingestLocal(authors: [String]) async {
        let filter = JSON.string(["kinds": [3], "authors": authors])
        guard let raw = try? await dbQueryEvents(filterJson: filter, limit: UInt32(authors.count * 2)) else { return }
        ingest(JSON.array(raw))
    }

    func ingestRemote(authors: [String]) async {
        let filter = JSON.string(["kinds": [3], "authors": authors, "limit": authors.count * 2])
        guard let raw = try? await fetchEvents(filterJson: filter, timeoutSecs: 8) else { return }
        let events = JSON.array(raw)
        let fresh = events.filter { event in
            guard let author = event.str("pubkey") else { return false }
            return event.int("created_at") > (latest[author]?.createdAt ?? -1)
        }
        ingest(fresh)
        if !fresh.isEmpty {
            _ = try? await dbSaveEvents(eventsJson: JSON.string(fresh))
        }
    }

    private func ingest(_ events: [JSONObject]) {
        for event in events {
            guard event.int("kind") == 3, let author = event.str("pubkey") else { continue }
            let createdAt = event.int("created_at")
            if let existing = latest[author], existing.createdAt >= createdAt { continue }
            var seen = Set<Int32>()
            var contacts: [Int32] = []
            for tag in (event["tags"] as? [[Any]]) ?? [] {
                guard tag.count > 1, tag[0] as? String == "p", let pubkey = tag[1] as? String, pubkey.count == 64, pubkey != author else { continue }
                let id = intern(pubkey.lowercased())
                if seen.insert(id).inserted { contacts.append(id) }
            }
            latest[author] = (createdAt, contacts)
        }
    }

    private func intern(_ pubkey: String) -> Int32 {
        if let id = index[pubkey] { return id }
        let id = Int32(keys.count)
        keys.append(pubkey)
        index[pubkey] = id
        return id
    }

    func snapshot() -> WebOfTrustSnapshot {
        var counts = [Int](repeating: 0, count: keys.count)
        for entry in latest.values {
            for id in entry.contacts { counts[Int(id)] += 1 }
        }
        var scores: [String: Int] = [:]
        var trusted = follows
        trusted.insert(owner)
        for (i, count) in counts.enumerated() where count >= minimum {
            scores[keys[i]] = count
            trusted.insert(keys[i])
        }
        return WebOfTrustSnapshot(owner: owner, follows: follows, scores: scores, trustedCount: trusted.count, updatedAt: Date())
    }

    func writeCache(_ snapshot: WebOfTrustSnapshot) {
        guard let url = Self.cacheURL(owner: snapshot.owner) else { return }
        let payload: JSONObject = [
            "updatedAt": snapshot.updatedAt.timeIntervalSince1970,
            "follows": Array(snapshot.follows),
            "scores": snapshot.scores,
            "trustedCount": snapshot.trustedCount,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    nonisolated static func readCache(owner: String) async -> WebOfTrustSnapshot? {
        await Task.detached(priority: .utility) {
            guard let url = cacheURL(owner: owner),
                  let data = try? Data(contentsOf: url),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject else { return nil }
            let follows = Set((json["follows"] as? [String]) ?? [])
            let scores = (json["scores"] as? [String: Int]) ?? [:]
            let updatedAt = Date(timeIntervalSince1970: (json["updatedAt"] as? Double) ?? 0)
            return WebOfTrustSnapshot(owner: owner, follows: follows, scores: scores, trustedCount: json.int("trustedCount"), updatedAt: updatedAt)
        }.value
    }

    nonisolated static func cacheURL(owner: String) -> URL? {
        guard owner.count == 64, owner.allSatisfy(\.isHexDigit),
              let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("WebOfTrust", isDirectory: true).appendingPathComponent("\(owner).json")
    }
}
