import Foundation
import Observation
import QiqstrCore

@MainActor
@Observable
final class MuteService {
    static let shared = MuteService()
    private(set) var mutedPubkeys: [String] = []
    private(set) var mutedWords: [String] = []
    private(set) var isLoaded = false
    private(set) var hasSyncedRemote = false
    private var generation = 0
    private var queue: Task<Void, Never>?
    @ObservationIgnored private var remote = RemoteMuteList()
    @ObservationIgnored private var pending = PendingMutes()

    private enum Change {
        case mute(String), unmute(String), addWord(String), removeWord(String)
    }

    func isMuted(_ pubkey: String) -> Bool { mutedPubkeys.contains(pubkey) }

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
        await perform(.mute(pubkey))
    }

    func unmute(_ pubkey: String) async throws {
        await perform(.unmute(pubkey))
    }

    func addWord(_ word: String) async throws {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        await perform(.addWord(normalized))
    }

    func removeWord(_ word: String) async throws {
        await perform(.removeWord(word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()))
    }

    private func perform(_ change: Change) async {
        guard let me = Session.shared.pubkey else { return }
        switch change {
        case .mute(let pubkey):
            guard !mutedPubkeys.contains(pubkey) else { return }
            pending.removedPubkeys.removeAll { $0 == pubkey }
            pending.addedPubkeys.append(pubkey)
        case .unmute(let pubkey):
            guard mutedPubkeys.contains(pubkey) else { return }
            pending.addedPubkeys.removeAll { $0 == pubkey }
            pending.removedPubkeys.append(pubkey)
        case .addWord(let word):
            guard !mutedWords.contains(word) else { return }
            pending.removedWords.removeAll { $0 == word }
            pending.addedWords.append(word)
        case .removeWord(let word):
            guard mutedWords.contains(word) else { return }
            pending.addedWords.removeAll { $0 == word }
            pending.removedWords.append(word)
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
        let removedPubkeys = Set(changes.removedPubkeys)
        let removedWords = Set(changes.removedWords)
        let keep: ([String]) -> Bool = { tag in
            guard tag.count > 1 else { return true }
            switch tag[0] {
            case "p": return !removedPubkeys.contains(tag[1])
            case "word": return !removedWords.contains(tag[1].lowercased())
            default: return true
            }
        }
        let publicTags = base.publicTags.filter(keep)
        var privateTags = base.privateTags.filter(keep)
        let known = RemoteMuteList(publicTags: publicTags, privateTags: privateTags)
        let knownPubkeys = Set(known.pubkeys)
        let knownWords = Set(known.words)
        privateTags += changes.addedPubkeys.filter { !knownPubkeys.contains($0) }.map { ["p", $0] }
        privateTags += changes.addedWords.filter { !knownWords.contains($0) }.map { ["word", $0] }
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

    private func recompute() {
        let removedPubkeys = Set(pending.removedPubkeys)
        let removedWords = Set(pending.removedWords)
        let pubkeys = Self.unique(remote.pubkeys + pending.addedPubkeys).filter { !removedPubkeys.contains($0) }
        let words = Self.unique(remote.words + pending.addedWords).filter { !removedWords.contains($0) }
        let changed = pubkeys != mutedPubkeys || words != mutedWords
        mutedPubkeys = pubkeys
        mutedWords = words
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

private struct RemoteMuteList {
    var publicTags: [[String]] = []
    var privateTags: [[String]] = []
    var isReadable = true

    var pubkeys: [String] { values("p") }
    var words: [String] { values("word").map { $0.lowercased() } }

    private func values(_ name: String) -> [String] {
        (publicTags + privateTags).filter { $0.count > 1 && $0[0] == name && !$0[1].isEmpty }.map { $0[1] }
    }
}

private struct PendingMutes: Codable {
    var addedPubkeys: [String] = []
    var removedPubkeys: [String] = []
    var addedWords: [String] = []
    var removedWords: [String] = []

    var isEmpty: Bool { addedPubkeys.isEmpty && removedPubkeys.isEmpty && addedWords.isEmpty && removedWords.isEmpty }

    mutating func subtract(_ published: PendingMutes) {
        addedPubkeys.removeAll(where: published.addedPubkeys.contains)
        removedPubkeys.removeAll(where: published.removedPubkeys.contains)
        addedWords.removeAll(where: published.addedWords.contains)
        removedWords.removeAll(where: published.removedWords.contains)
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
