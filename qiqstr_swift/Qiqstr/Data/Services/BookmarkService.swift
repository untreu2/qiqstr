import Foundation
import Observation
import QiqstrCore

@MainActor
@Observable
final class BookmarkService {
    static let shared = BookmarkService()
    private(set) var bookmarkedIds: [String] = []
    private(set) var isLoaded = false
    private(set) var isSyncing = false

    private var generation = 0
    private var publishChain: Task<Void, Never>?

    private static let dTag = "bookmark"

    func isBookmarked(_ noteId: String) -> Bool { bookmarkedIds.contains(noteId) }

    func reset() {
        generation += 1
        bookmarkedIds = []
        isLoaded = false
        isSyncing = false
        publishChain = nil
    }

    func load() async {
        let current = generation
        await loadFromDatabase(generation: current)
        await sync(generation: current)
    }

    func refresh() async {
        await sync(generation: generation)
    }

    func toggle(_ noteId: String) async throws {
        if isBookmarked(noteId) { try await remove(noteId) } else { try await add(noteId) }
    }

    func add(_ noteId: String) async throws {
        guard !noteId.isEmpty else { return }
        if !isLoaded { await loadFromDatabase(generation: generation) }
        guard !isBookmarked(noteId) else { return }
        let current = generation
        bookmarkedIds.append(noteId)
        DataBus.shared.listsChanged()
        do {
            try await enqueuePublish(noteId, adding: true)
        } catch {
            guard current == generation else { throw error }
            bookmarkedIds.removeAll { $0 == noteId }
            DataBus.shared.listsChanged()
            throw error
        }
    }

    func remove(_ noteId: String) async throws {
        if !isLoaded { await loadFromDatabase(generation: generation) }
        guard let index = bookmarkedIds.firstIndex(of: noteId) else { return }
        let current = generation
        bookmarkedIds.remove(at: index)
        DataBus.shared.listsChanged()
        do {
            try await enqueuePublish(noteId, adding: false)
        } catch {
            guard current == generation else { throw error }
            if !bookmarkedIds.contains(noteId) { bookmarkedIds.insert(noteId, at: min(index, bookmarkedIds.count)) }
            DataBus.shared.listsChanged()
            throw error
        }
    }

    func notes() async -> [Note] {
        let ids = bookmarkedIds
        guard !ids.isEmpty else { return [] }
        let session = Session.shared
        var notes = await hydrated(ids, session: session)
        let found = Set(notes.map(\.id))
        let missing = ids.filter { !found.contains($0) }
        if !missing.isEmpty {
            if let raw = try? await fetchEventsByIds(eventIds: missing, timeoutSecs: 6) {
                let events = JSON.array(raw)
                if !events.isEmpty {
                    _ = try? await dbSaveEvents(eventsJson: JSON.string(events))
                    SyncService.shared.backgroundFollowUps(events)
                }
            }
            notes += await hydrated(missing, session: session).filter { !found.contains($0.id) }
        }
        return notes.sorted { $0.createdAt > $1.createdAt }
    }

    private func hydrated(_ ids: [String], session: Session) async -> [Note] {
        let raw = try? await dbGetHydratedNotesByIds(eventIds: ids, mutedPubkeys: session.mutedPubkeys, mutedWords: session.mutedWords, currentUserPubkeyHex: session.pubkey)
        return await Note.parsed(raw)
    }

    private func sync(generation current: Int) async {
        guard let me = Session.shared.pubkey else { return }
        isSyncing = true
        defer { if current == generation { isSyncing = false } }
        let events = await SyncService.shared.fetchEvents(["kinds": [30001], "authors": [me], "#d": [Self.dTag], "limit": 1], timeout: 8)
        if !events.isEmpty { _ = try? await dbSaveEvents(eventsJson: JSON.string(events)) }
        guard current == generation, publishChain == nil else { return }
        await loadFromDatabase(generation: current)
    }

    private func loadFromDatabase(generation current: Int) async {
        guard let me = Session.shared.pubkey, let sk = Session.shared.privateKey else { return }
        let filter = JSON.string(["kinds": [30001], "authors": [me], "#d": [Self.dTag]])
        let events = JSON.array(try? await dbQueryEvents(filterJson: filter, limit: 5))
        guard current == generation else { return }
        guard let event = events.max(by: { $0.int("created_at") < $1.int("created_at") }) else {
            isLoaded = true
            return
        }
        var ids = eventIds(event.tags())
        if let content = event["content"] as? String, !content.isEmpty,
           let decrypted = Self.decrypt(content, key: sk, me: me),
           let privateTags = JSON.any(decrypted) as? [[Any]] {
            ids += eventIds(privateTags.map { $0.compactMap { $0 as? String } })
        }
        var seen = Set<String>()
        bookmarkedIds = ids.filter { seen.insert($0).inserted }
        isLoaded = true
        DataBus.shared.listsChanged()
    }

    private static func decrypt(_ content: String, key: String, me: String) -> String? {
        if content.contains("?iv=") { return try? nip04Decrypt(payload: content, receiverSkHex: key, senderPkHex: me) }
        return try? nip44Decrypt(payload: content, receiverSkHex: key, senderPkHex: me)
    }

    private func eventIds(_ tags: [[String]]) -> [String] {
        tags.filter { $0.count > 1 && $0[0] == "e" && !$0[1].isEmpty }.map { $0[1] }
    }

    private func enqueuePublish(_ noteId: String, adding: Bool) async throws {
        let previous = publishChain
        let task = Task<Result<Void, Error>, Never> {
            await previous?.value
            do { return .success(try await self.publish(noteId, adding: adding)) } catch { return .failure(error) }
        }
        let chain = Task { _ = await task.value }
        publishChain = chain
        let result = await task.value
        if publishChain == chain { publishChain = nil }
        try result.get()
    }

    private func publish(_ noteId: String, adding: Bool) async throws {
        let sk = try Session.shared.requireSigner()
        guard let me = Session.shared.pubkey else { throw CoreError("Not signed in") }
        let base = try await SyncService.shared.latestEditableEvent(kind: 30001, author: me, dTag: Self.dTag)
        var publicTags = (base?.tags() ?? []).filter { !($0.first == "d") }
        var privateTags: [[String]] = []
        if let content = base?["content"] as? String, !content.isEmpty {
            guard let decrypted = Self.decrypt(content, key: sk, me: me),
                  let tags = JSON.any(decrypted) as? [[Any]] else { throw CoreError(L("bookmarksUnreadable")) }
            privateTags = tags.map { $0.compactMap { $0 as? String } }
        }
        let isE: ([String]) -> Bool = { $0.count > 1 && $0[0] == "e" && $0[1] == noteId }
        if adding {
            if !publicTags.contains(where: isE), !privateTags.contains(where: isE) { privateTags.append(["e", noteId]) }
        } else {
            publicTags.removeAll(where: isE)
            privateTags.removeAll(where: isE)
        }
        if !publicTags.contains(where: { $0.first == "alt" }) { publicTags.append(["alt", "List of bookmarks"]) }
        let encrypted = try nip44Encrypt(content: JSON.string(privateTags), senderSkHex: sk, receiverPkHex: me)
        let json = try createSignedEvent(kind: 30001, content: encrypted, tags: [["d", Self.dTag]] + publicTags, privateKeyHex: sk)
        try await SyncService.shared.publish(json)
        var seen = Set<String>()
        bookmarkedIds = (eventIds(publicTags) + eventIds(privateTags)).filter { seen.insert($0).inserted }
        DataBus.shared.listsChanged()
    }
}
