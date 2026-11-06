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

    func isMuted(_ pubkey: String) -> Bool { mutedPubkeys.contains(pubkey) }

    func containsMutedWord(_ content: String) -> Bool {
        guard !mutedWords.isEmpty else { return false }
        let lower = content.lowercased()
        return mutedWords.contains { lower.contains($0) }
    }

    func reset() {
        generation += 1
        queue = nil
        mutedPubkeys = []
        mutedWords = []
        isLoaded = false
        hasSyncedRemote = false
        syncToRust()
    }

    func load() async {
        guard let me = Session.shared.pubkey, let key = Session.shared.privateKey else { return }
        let generation = self.generation
        await loadFromDatabase(pubkey: me, privateKey: key, generation: generation)
        _ = await SyncService.shared.fetchEvents(["kinds": [10000], "authors": [me], "limit": 1])
        guard generation == self.generation else { return }
        await loadFromDatabase(pubkey: me, privateKey: key, generation: generation)
        guard generation == self.generation else { return }
        hasSyncedRemote = true
    }

    func mute(_ pubkey: String) async throws {
        try await mutate { pubkeys, _ in
            guard !pubkeys.contains(pubkey) else { return false }
            pubkeys.append(pubkey)
            return true
        }
    }

    func unmute(_ pubkey: String) async throws {
        try await mutate { pubkeys, _ in
            guard pubkeys.contains(pubkey) else { return false }
            pubkeys.removeAll { $0 == pubkey }
            return true
        }
    }

    func addWord(_ word: String) async throws {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        try await mutate { _, words in
            guard !words.contains(normalized) else { return false }
            words.append(normalized)
            return true
        }
    }

    func removeWord(_ word: String) async throws {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try await mutate { _, words in
            guard words.contains(normalized) else { return false }
            words.removeAll { $0 == normalized }
            return true
        }
    }

    private func mutate(_ change: @escaping (inout [String], inout [String]) -> Bool) async throws {
        let previous = queue
        let generation = self.generation
        let operation = Task<Void, Error> {
            await previous?.value
            guard generation == self.generation else { throw CancellationError() }
            if !self.hasSyncedRemote { await self.load() }
            guard generation == self.generation else { throw CancellationError() }
            var pubkeys = self.mutedPubkeys
            var words = self.mutedWords
            guard change(&pubkeys, &words) else { return }
            let oldPubkeys = self.mutedPubkeys
            let oldWords = self.mutedWords
            self.apply(pubkeys: pubkeys, words: words)
            do {
                try await self.publish(pubkeys: pubkeys, words: words)
            } catch {
                if generation == self.generation { self.apply(pubkeys: oldPubkeys, words: oldWords) }
                throw error
            }
        }
        queue = Task { _ = try? await operation.value }
        try await operation.value
    }

    private func publish(pubkeys: [String], words: [String]) async throws {
        guard let me = Session.shared.pubkey, let key = Session.shared.privateKey else { throw CoreError("Not authenticated") }
        let privateTags = pubkeys.map { ["p", $0] } + words.map { ["word", $0] }
        let encrypted = try nip44Encrypt(content: JSON.string(privateTags), senderSkHex: key, receiverPkHex: me)
        let event = try createSignedEvent(kind: 10000, content: encrypted, tags: [], privateKeyHex: key)
        try await SyncService.shared.publish(event)
    }

    private func loadFromDatabase(pubkey: String, privateKey: String, generation: Int) async {
        let content: String?
        do {
            content = try await dbGetMuteListContent(pubkeyHex: pubkey)
        } catch {
            if generation == self.generation { isLoaded = true }
            return
        }
        guard generation == self.generation else { return }
        guard let content else {
            apply(pubkeys: [], words: [])
            return
        }
        var tags: [[String]]?
        if !content.isEmpty, let decrypted = try? nip44Decrypt(payload: content, receiverSkHex: privateKey, senderPkHex: pubkey) {
            tags = (JSON.any(decrypted) as? [[Any]])?.map { $0.compactMap { $0 as? String } }
        }
        if tags == nil {
            let filter = JSON.string(["kinds": [10000], "authors": [pubkey]])
            let events = JSON.array(try? await dbQueryEvents(filterJson: filter, limit: 1))
            guard generation == self.generation else { return }
            tags = events.first?.tags() ?? []
        }
        let list = tags ?? []
        let pubkeys = list.filter { $0.count > 1 && $0[0] == "p" }.map { $0[1] }
        let words = list.filter { $0.count > 1 && $0[0] == "word" }.map { $0[1].lowercased() }
        apply(pubkeys: unique(pubkeys), words: unique(words))
    }

    private func apply(pubkeys: [String], words: [String]) {
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
        }
    }

    private func syncToRust() {
        setActiveMuteList(mutedPubkeys: mutedPubkeys, mutedWords: mutedWords)
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
