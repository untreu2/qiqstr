import Foundation
import Observation
import QiqstrCore

@MainActor
@Observable
final class MuteService {
    static let shared = MuteService()
    private(set) var mutedPubkeys: [String] = []
    private(set) var mutedWords: [String] = []
    private(set) var mutedHashtags: [String] = []
    private(set) var mutedThreads: [String] = []
    private(set) var isLoaded = false
    private(set) var hasSyncedRemote = false
    private var generation = 0
    private var queue: Task<Void, Never>?
    @ObservationIgnored private var remote = RemoteMuteList()
    @ObservationIgnored private var pending = PendingMutes()

    private enum Change {
        case add(MuteEntry, String), remove(MuteEntry, String)
    }

    func isMuted(_ pubkey: String) -> Bool { mutedPubkeys.contains(pubkey) }

    func isHashtagMuted(_ tag: String) -> Bool { mutedHashtags.contains(Self.normalizedHashtag(tag)) }

    func isThreadMuted(_ rootId: String) -> Bool { mutedThreads.contains(rootId) }

    func hides(_ note: Note) -> Bool {
        if !mutedThreads.isEmpty, mutedThreads.contains(note.rootId ?? note.id) || mutedThreads.contains(note.id) { return true }
        guard !mutedHashtags.isEmpty else { return false }
        return note.hashtags.contains { mutedHashtags.contains($0.lowercased()) }
    }

    func hidesNotification(target: String?, root: String?) -> Bool {
        guard !mutedThreads.isEmpty else { return false }
        return [target, root].compactMap { $0 }.contains(where: mutedThreads.contains)
    }

    static func normalizedHashtag(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    }

    func containsMutedWord(_ content: String) -> Bool {
        guard !mutedWords.isEmpty else { return false }
        let lower = content.lowercased()
        return mutedWords.contains { lower.contains($0) }
    }

    func reset() {
        generation += 1
        queue = nil
        remote = RemoteMuteList()
        pending = PendingMutes()
        mutedPubkeys = []
        mutedWords = []
        mutedHashtags = []
        mutedThreads = []
        isLoaded = false
        hasSyncedRemote = false
        syncToRust()
    }

    func load() async {
        guard let me = Session.shared.pubkey else { return }
        let generation = self.generation
        pending = PendingMutes.stored(for: me)
        await readCachedList(me, generation: generation)
        _ = await SyncService.shared.fetchEvents(Self.filter(me))
        guard generation == self.generation else { return }
        await readCachedList(me, generation: generation)
        guard generation == self.generation else { return }
        hasSyncedRemote = true
        if !pending.isEmpty { enqueue { await self.publishPending() } }
    }

    func mute(_ pubkey: String) async throws {
        guard !pubkey.isEmpty, pubkey != Session.shared.pubkey else { return }
        await perform(.add(.pubkey, pubkey))
    }

    func unmute(_ pubkey: String) async throws {
        await perform(.remove(.pubkey, pubkey))
    }

    func addWord(_ word: String) async throws {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        await perform(.add(.word, normalized))
    }

    func removeWord(_ word: String) async throws {
        await perform(.remove(.word, word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()))
    }

    func muteHashtag(_ tag: String) async {
        let normalized = Self.normalizedHashtag(tag)
        guard !normalized.isEmpty else { return }
        await perform(.add(.hashtag, normalized))
    }

    func unmuteHashtag(_ tag: String) async {
        await perform(.remove(.hashtag, Self.normalizedHashtag(tag)))
    }

    func muteThread(_ rootId: String) async {
        guard rootId.count == 64 else { return }
        await perform(.add(.thread, rootId))
    }

    func unmuteThread(_ rootId: String) async {
        await perform(.remove(.thread, rootId))
    }

    private func current(_ entry: MuteEntry) -> [String] {
        switch entry {
        case .pubkey: mutedPubkeys
        case .word: mutedWords
        case .hashtag: mutedHashtags
        case .thread: mutedThreads
        }
    }

    private func perform(_ change: Change) async {
        guard let me = Session.shared.pubkey else { return }
        switch change {
        case .add(let entry, let value):
            guard !current(entry).contains(value) else { return }
            pending.removed[entry.rawValue, default: []].removeAll { $0 == value }
            pending.added[entry.rawValue, default: []].append(value)
        case .remove(let entry, let value):
            guard current(entry).contains(value) else { return }
            pending.added[entry.rawValue, default: []].removeAll { $0 == value }
            pending.removed[entry.rawValue, default: []].append(value)
        }
        pending.store(for: me)
        recompute()
        await enqueue { await self.publishPending() }.value
    }

    @discardableResult
    private func enqueue(_ work: @escaping () async -> Void) -> Task<Void, Never> {
        let previous = queue
        let generation = self.generation
        let task = Task {
            await previous?.value
            guard generation == self.generation else { return }
            await work()
        }
        queue = task
        return task
    }

    private func publishPending() async {
        guard !pending.isEmpty, let me = Session.shared.pubkey, let key = Session.shared.privateKey else { return }
        let generation = self.generation
        guard let base = await latestList(me, key: key), generation == self.generation, base.isReadable else { return }
        let changes = pending
        let keep: ([String]) -> Bool = { tag in
            guard tag.count > 1, let entry = MuteEntry(rawValue: tag[0]) else { return true }
            return !(changes.removed[entry.rawValue] ?? []).contains(entry.normalized(tag[1]))
        }
        let publicTags = base.publicTags.filter(keep)
        var privateTags = base.privateTags.filter(keep)
        let known = RemoteMuteList(publicTags: publicTags, privateTags: privateTags)
        for entry in MuteEntry.allCases {
            let existing = Set(known.values(entry))
            privateTags += (changes.added[entry.rawValue] ?? []).filter { !existing.contains($0) }.map { [entry.rawValue, $0] }
        }
        do {
            let content = privateTags.isEmpty ? "" : try nip44Encrypt(content: JSON.string(privateTags), senderSkHex: key, receiverPkHex: me)
            let event = try createSignedEvent(kind: 10000, content: content, tags: publicTags, privateKeyHex: key)
            try await SyncService.shared.publish(event)
            guard generation == self.generation else { return }
            remote = RemoteMuteList(publicTags: publicTags, privateTags: privateTags)
            pending.subtract(changes)
            pending.store(for: me)
            recompute()
        } catch {}
    }

    private func latestList(_ me: String, key: String) async -> RemoteMuteList? {
        let cached = await cachedEvents(me)
        let fetched = await SyncService.shared.fetchReplaceable(kind: 10000, author: me)
        if fetched.isEmpty, !cached.isEmpty { return nil }
        if let newest = Self.newest(cached + fetched, author: me) { return Self.parse(newest, pubkey: me, privateKey: key) }
        guard Session.shared.isNewAccount || AccountStore.wasCreatedHere(me) else { return nil }
        if ((try? await getConnectedRelayCount()) ?? 0) == 0 { return nil }
        return RemoteMuteList()
    }

    private func readCachedList(_ me: String, generation: Int) async {
        let events = await cachedEvents(me)
        guard generation == self.generation else { return }
        if let newest = Self.newest(events, author: me) {
            remote = Self.parse(newest, pubkey: me, privateKey: Session.shared.privateKey)
        } else {
            remote = RemoteMuteList()
        }
        recompute()
    }

    private func cachedEvents(_ me: String) async -> [JSONObject] {
        JSON.array(try? await dbQueryEvents(filterJson: JSON.string(Self.filter(me)), limit: 1))
    }

    private static func filter(_ me: String) -> JSONObject { ["kinds": [10000], "authors": [me], "limit": 1] }

    private static func newest(_ events: [JSONObject], author: String) -> JSONObject? {
        events
            .filter { $0.int("kind") == 10000 && $0.str("pubkey")?.lowercased() == author.lowercased() }
            .max { ($0.int("created_at"), $0.str("id") ?? "") < ($1.int("created_at"), $1.str("id") ?? "") }
    }

    private static func parse(_ event: JSONObject, pubkey: String, privateKey: String?) -> RemoteMuteList {
        var list = RemoteMuteList(publicTags: event.tags())
        guard let content = event["content"] as? String, !content.isEmpty else { return list }
        guard let privateKey, let plain = decrypt(content, privateKey: privateKey, pubkey: pubkey),
              let tags = JSON.any(plain) as? [[Any]] else {
            list.isReadable = false
            return list
        }
        list.privateTags = tags.map { $0.compactMap { $0 as? String } }
        return list
    }

    private static func decrypt(_ content: String, privateKey: String, pubkey: String) -> String? {
        if content.contains("?iv=") {
            return try? nip04Decrypt(payload: content, receiverSkHex: privateKey, senderPkHex: pubkey)
        }
        return try? nip44Decrypt(payload: content, receiverSkHex: privateKey, senderPkHex: pubkey)
    }

    private func merged(_ entry: MuteEntry) -> [String] {
        let removed = Set(pending.removed[entry.rawValue] ?? [])
        return Self.unique(remote.values(entry) + (pending.added[entry.rawValue] ?? [])).filter { !removed.contains($0) }
    }

    private func recompute() {
        let pubkeys = merged(.pubkey)
        let words = merged(.word)
        let hashtags = merged(.hashtag)
        let threads = merged(.thread)
        let changed = pubkeys != mutedPubkeys || words != mutedWords || hashtags != mutedHashtags || threads != mutedThreads
        mutedPubkeys = pubkeys
        mutedWords = words
        mutedHashtags = hashtags
        mutedThreads = threads
        isLoaded = true
        Session.shared.mutedPubkeys = pubkeys
        Session.shared.mutedWords = words
        syncToRust()
        if changed {
            DataBus.shared.feedChanged()
            DataBus.shared.notificationsChanged()
            DMService.shared.mutesChanged()
        }
    }

    private func syncToRust() {
        setActiveMuteList(mutedPubkeys: mutedPubkeys, mutedWords: mutedWords)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

enum MuteEntry: String, CaseIterable {
    case pubkey = "p", word = "word", hashtag = "t", thread = "e"

    func normalized(_ value: String) -> String {
        switch self {
        case .pubkey, .thread: value
        case .word, .hashtag: value.lowercased()
        }
    }
}

private struct RemoteMuteList {
    var publicTags: [[String]] = []
    var privateTags: [[String]] = []
    var isReadable = true

    func values(_ entry: MuteEntry) -> [String] {
        (publicTags + privateTags).filter { $0.count > 1 && $0[0] == entry.rawValue && !$0[1].isEmpty }.map { entry.normalized($0[1]) }
    }
}

private struct PendingMutes: Codable {
    var added: [String: [String]] = [:]
    var removed: [String: [String]] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case added, removed, addedPubkeys, removedPubkeys, addedWords, removedWords
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        added = try c.decodeIfPresent([String: [String]].self, forKey: .added) ?? [:]
        removed = try c.decodeIfPresent([String: [String]].self, forKey: .removed) ?? [:]
        let legacy: [(CodingKeys, MuteEntry, Bool)] = [(.addedPubkeys, .pubkey, true), (.removedPubkeys, .pubkey, false), (.addedWords, .word, true), (.removedWords, .word, false)]
        for (key, entry, isAdded) in legacy {
            guard let values = try c.decodeIfPresent([String].self, forKey: key), !values.isEmpty else { continue }
            if isAdded { added[entry.rawValue, default: []] += values } else { removed[entry.rawValue, default: []] += values }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(added, forKey: .added)
        try c.encode(removed, forKey: .removed)
    }

    var isEmpty: Bool { added.values.allSatisfy(\.isEmpty) && removed.values.allSatisfy(\.isEmpty) }

    mutating func subtract(_ published: PendingMutes) {
        for (key, values) in published.added { added[key]?.removeAll(where: values.contains) }
        for (key, values) in published.removed { removed[key]?.removeAll(where: values.contains) }
    }

    static func stored(for pubkey: String) -> PendingMutes {
        guard let data = UserDefaults.standard.data(forKey: key(pubkey)) else { return PendingMutes() }
        return (try? JSONDecoder().decode(PendingMutes.self, from: data)) ?? PendingMutes()
    }

    func store(for pubkey: String) {
        if isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.key(pubkey))
        } else if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key(pubkey))
        }
    }

    private static func key(_ pubkey: String) -> String { "mute_pending_\(pubkey)" }
}
