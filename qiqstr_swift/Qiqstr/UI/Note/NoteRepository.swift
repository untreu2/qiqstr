import Foundation
import QiqstrCore

enum FeedSortMode: String, CaseIterable, Identifiable {
    case latest
    case mostInteracted = "most_interacted"
    var id: String { rawValue }
    var title: String { self == .latest ? L("feedSortLatest") : L("feedSortMostInteracted") }
    var systemImage: String { self == .latest ? "clock" : "flame" }
}

struct FeedFollowSet: Identifiable, Hashable {
    var id: String { "\(pubkey):\(dTag)" }
    var pubkey: String
    var dTag: String
    var title: String
    var pubkeys: [String]

    init?(json j: JSONObject) {
        guard let pubkey = j.str("pubkey"), let dTag = j.str("dTag") else { return nil }
        self.pubkey = pubkey
        self.dTag = dTag
        title = j.str("title") ?? dTag
        pubkeys = j.strings("pubkeys")
    }
}

struct NoteThreadData {
    var rootNote: Note
    var chain: [Note]
    var children: [String: [Note]]
    var totalReplies: Int

    init?(json j: JSONObject) {
        guard let root = j["rootNote"] as? JSONObject else { return nil }
        let rootNote = Note(json: root)
        guard !rootNote.id.isEmpty else { return nil }
        self.rootNote = rootNote
        let chain = ((j["chainNotes"] as? [JSONObject]) ?? []).map(Note.init(json:)).filter { !$0.id.isEmpty }
        self.chain = chain.isEmpty ? [rootNote] : chain
        var children: [String: [Note]] = [:]
        for (key, value) in (j["childrenMap"] as? JSONObject) ?? [:] {
            children[key] = ((value as? [JSONObject]) ?? []).map(Note.init(json:)).filter { !$0.id.isEmpty && !$0.isRepost }
        }
        self.children = children
        totalReplies = j.int("totalReplies")
    }

    var focused: Note { chain.last ?? rootNote }
    var allNotes: [Note] { chain + children.values.flatMap { $0 } }
}

enum NoteRepository {
    static var me: String? { Session.shared.pubkey }
    static var mutedPubkeys: [String] { Session.shared.mutedPubkeys }
    static var mutedWords: [String] { Session.shared.mutedWords }

    static func feed(authors: [String]?, limit: Int, sort: FeedSortMode) async -> [Note] {
        guard let me else { return [] }
        let raw = try? await dbGetHydratedFeedNotesSorted(userPubkeyHex: me, authorsHex: authors, limit: UInt32(limit), filterReplies: true, currentUserPubkeyHex: me, sortMode: sort.rawValue)
        return Note.list(raw)
    }

    static func hashtag(_ tag: String, limit: Int) async -> [Note] {
        let raw = try? await dbGetHydratedHashtagNotes(hashtag: tag.lowercased(), limit: UInt32(limit), mutedPubkeys: mutedPubkeys, mutedWords: mutedWords, currentUserPubkeyHex: me)
        return Note.list(raw)
    }

    static func note(_ id: String) async -> Note? {
        guard let raw = try? await dbGetHydratedNote(eventId: id, currentUserPubkeyHex: me), let obj = JSON.object(raw) else { return nil }
        let note = Note(json: obj)
        return note.id.isEmpty ? nil : note
    }

    static func notes(_ ids: [String]) async -> [Note] {
        guard !ids.isEmpty else { return [] }
        let raw = try? await dbGetHydratedNotesByIds(eventIds: ids, mutedPubkeys: mutedPubkeys, mutedWords: mutedWords, currentUserPubkeyHex: me)
        return Note.list(raw)
    }

    static func ensureNote(_ id: String) async -> Note? {
        if let note = await note(id) { return note }
        await SyncService.shared.syncNote(id)
        return await note(id)
    }

    static func threadLocal(_ noteId: String) async -> NoteThreadData? {
        guard let raw = try? await fetchFullThreadLocal(noteId: noteId, currentUserPubkeyHex: me, mutedPubkeys: mutedPubkeys, mutedWords: mutedWords) else { return nil }
        return JSON.object(raw).flatMap(NoteThreadData.init(json:))
    }

    static func threadNetwork(_ noteId: String) async throws -> NoteThreadData? {
        let raw = try await fetchFullThread(noteId: noteId, currentUserPubkeyHex: me, mutedPubkeys: mutedPubkeys, mutedWords: mutedWords)
        return JSON.object(raw).flatMap(NoteThreadData.init(json:))
    }

    static func quoteCount(_ noteId: String) async -> Int {
        Int((try? await dbCountEvents(filterJson: JSON.string(["kinds": [1], "#q": [noteId]]))) ?? 0)
    }

    static func quotes(_ noteId: String) async -> [Note] {
        async let tagged = dbQueryEvents(filterJson: JSON.string(["kinds": [1], "#q": [noteId]]), limit: 300)
        async let referenced = dbQueryEvents(filterJson: JSON.string(["kinds": [1], "#e": [noteId]]), limit: 500)
        let quoteEvents = JSON.array(try? await tagged)
        let mentionEvents = JSON.array(try? await referenced).filter { event in
            event.tags().contains { $0.count >= 4 && $0[0] == "e" && $0[1] == noteId && $0[3] == "mention" }
        }
        var ids: [String] = []
        for event in quoteEvents + mentionEvents {
            if let id = event.str("id"), !ids.contains(id) { ids.append(id) }
        }
        return await notes(ids).sorted { $0.createdAt > $1.createdAt }
    }

    static func fetchQuotesFromRelays(_ noteId: String) async {
        async let q = SyncService.shared.fetchEvents(["kinds": [1], "#q": [noteId], "limit": 200])
        async let e = SyncService.shared.fetchEvents(["kinds": [1], "#e": [noteId], "limit": 300])
        let events = await q + e
        if !events.isEmpty {
            _ = try? await dbSaveEvents(eventsJson: JSON.string(events))
            SyncService.shared.fetchMissingProfiles(Array(Set(events.compactMap { $0.str("pubkey") })))
        }
    }

    static func fetchOlder(authors: [String], until: Int) async -> Int {
        guard !authors.isEmpty, until > 0 else { return 0 }
        let events = await SyncService.shared.fetchEvents(["authors": authors, "kinds": [1, 6], "until": until - 1, "limit": 100], timeout: 10)
        if !events.isEmpty {
            _ = try? await dbSaveEvents(eventsJson: JSON.string(events))
            SyncService.shared.backgroundFollowUps(events)
        }
        return events.count
    }

    static func fetchOlderHashtag(_ tag: String, until: Int) async -> Int {
        guard until > 0 else { return 0 }
        let events = await SyncService.shared.fetchEvents(["kinds": [1], "#t": [tag.lowercased()], "until": until - 1, "limit": 100], timeout: 10)
        if !events.isEmpty {
            _ = try? await dbSaveEvents(eventsJson: JSON.string(events))
            SyncService.shared.backgroundFollowUps(events)
        }
        return events.count
    }

    static func following() async -> [String] {
        guard let me else { return [] }
        return await SyncService.shared.followingList(me)
    }

    static func followSets(authors: [String], limit: Int) async -> [FeedFollowSet] {
        guard !authors.isEmpty else { return [] }
        let raw = try? await dbGetFollowSets(authorsHex: authors, limit: UInt32(limit), hiddenDTags: ["mute", "Chat-Friends"])
        return JSON.array(raw).compactMap(FeedFollowSet.init(json:))
    }

    static func searchProfiles(_ query: String, limit: Int = 8) async -> [Profile] {
        let raw = try? await dbSearchProfiles(query: query, limit: UInt32(limit))
        return JSON.array(raw).map { Profile(json: $0) }.filter { !$0.pubkey.isEmpty }
    }

    static func article(naddr: String) async -> Article? {
        guard let tlv = Nip19.decodeTLV(naddr), let pubkey = tlv.str("pubkey") else { return nil }
        let identifier = (tlv["identifier"] as? String) ?? ""
        if let raw = try? await dbGetHydratedArticleByNaddr(pubkeyHex: pubkey, dTag: identifier), let obj = JSON.object(raw) {
            return Article(json: obj)
        }
        let events = await SyncService.shared.fetchEvents(["kinds": [30023], "authors": [pubkey], "#d": [identifier], "limit": 1], timeout: 6)
        guard !events.isEmpty else { return nil }
        _ = try? await dbSaveEvents(eventsJson: JSON.string(events))
        guard let raw = try? await dbGetHydratedArticleByNaddr(pubkeyHex: pubkey, dTag: identifier), let obj = JSON.object(raw) else { return nil }
        return Article(json: obj)
    }

    static func prefetchEmbedded(_ notes: [Note]) {
        let contents = notes.map(\.content).filter { $0.contains("nostr:") || $0.contains("note1") || $0.contains("naddr1") }
        guard !contents.isEmpty else { return }
        Task(priority: .utility) {
            let embedded = extractEmbeddedIdsBatchTyped(contents: contents)
            if !embedded.eventIds.isEmpty {
                let ids = embedded.eventIds
                let exists = (try? await dbEventsExistBatch(eventIds: ids)) ?? []
                let missing = zip(ids, exists).filter { !$0.1 }.map(\.0)
                if !missing.isEmpty {
                    _ = try? await fetchEventsByIds(eventIds: Array(missing.prefix(60)), timeoutSecs: 8)
                    DataBus.shared.feedChanged()
                }
            }
            if !embedded.addresses.isEmpty {
                let filter: JSONObject = ["kinds": [30023], "authors": embedded.addresses, "limit": 50]
                _ = try? await QiqstrCore.fetchEvents(filterJson: JSON.string(filter), timeoutSecs: 8)
            }
        }
    }

    static func parse(_ content: String) -> ParsedContent {
        ParsedContent(json: JSON.object(parseNoteContent(content: content)) ?? [:])
    }
}
