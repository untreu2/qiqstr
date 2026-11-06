import Foundation
import QiqstrCore

struct InteractionCounts: Equatable, Sendable {
    var reactions = 0
    var reposts = 0
    var replies = 0
    var zapAmount = 0
    var hasReacted = false
    var hasReposted = false
    var hasZapped = false

    init(reactions: Int = 0, reposts: Int = 0, replies: Int = 0, zapAmount: Int = 0, hasReacted: Bool = false, hasReposted: Bool = false, hasZapped: Bool = false) {
        self.reactions = reactions
        self.reposts = reposts
        self.replies = replies
        self.zapAmount = zapAmount
        self.hasReacted = hasReacted
        self.hasReposted = hasReposted
        self.hasZapped = hasZapped
    }

    init(note: Note) {
        self.init(reactions: note.reactionCount, reposts: note.repostCount, replies: note.replyCount, zapAmount: note.zapCount, hasReacted: note.hasReacted, hasReposted: note.hasReposted, hasZapped: note.hasZapped)
    }

    init(json j: JSONObject) {
        self.init(reactions: j.int("reactions"), reposts: j.int("reposts"), replies: j.int("replies"), zapAmount: j.int("zaps"), hasReacted: j.bool("hasReacted"), hasReposted: j.bool("hasReposted"), hasZapped: j.bool("hasZapped"))
    }
}

enum NoteInteractionKind: String, Sendable {
    case reaction, repost, zap
}

struct NoteInteractionDetail: Identifiable, Hashable, Sendable {
    var id: String { "\(kind.rawValue)-\(pubkey)-\(createdAt)-\(content.hashValue)" }
    var kind: NoteInteractionKind
    var pubkey: String
    var content: String
    var zapAmount: Int
    var createdAt: Int

    init?(json j: JSONObject) {
        guard let kind = NoteInteractionKind(rawValue: j.str("type") ?? ""), let pubkey = j.str("pubkey") else { return nil }
        self.kind = kind
        self.pubkey = pubkey
        content = (j["content"] as? String) ?? ""
        zapAmount = j.int("zapAmount")
        createdAt = j.int("createdAt")
    }
}

enum NoteReportReason: String, CaseIterable, Identifiable, Sendable {
    case spam, nudity, profanity, illegal, impersonation, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spam: L("reportReasonSpam")
        case .nudity: L("reportReasonNudity")
        case .profanity: L("reportReasonProfanity")
        case .illegal: L("reportReasonIllegal")
        case .impersonation: L("reportReasonImpersonation")
        case .other: L("reportReasonOther")
        }
    }
}

@MainActor
final class InteractionService {
    static let shared = InteractionService()

    private var sync: SyncService { SyncService.shared }

    private func signingKey() throws -> String {
        guard let key = Session.shared.privateKey, Session.shared.pubkey != nil else { throw CoreError(L("authenticationRequired")) }
        return key
    }

    private func primaryRelay() async -> String {
        (try? await getRelayList())?.first ?? RelayConfig.mainRelays.first ?? ""
    }

    func react(to note: Note, content: String = "+") async throws {
        let key = try signingKey()
        let relay = await primaryRelay()
        let event = try createReactionEvent(targetEventId: note.id, targetAuthor: note.pubkey, content: content, privateKeyHex: key, relayUrl: relay, targetKind: 1)
        try await sync.publish(event)
    }

    func unreact(_ note: Note) async throws {
        let key = try signingKey()
        guard let me = Session.shared.pubkey else { return }
        let filter = JSON.string(["kinds": [7], "authors": [me], "#e": [note.id]])
        let ids = JSON.array(try await dbQueryEvents(filterJson: filter, limit: 20)).compactMap { $0.str("id") }
        guard !ids.isEmpty else { throw CoreError(L("eventNotFound")) }
        try await publishDeletion(ids, key: key)
    }

    func repost(_ note: Note) async throws {
        let key = try signingKey()
        let relay = await primaryRelay()
        let original = (try? await dbGetEvent(eventId: note.id)) ?? nil
        let event = try createRepostEvent(noteId: note.id, noteAuthor: note.pubkey, content: original ?? "", privateKeyHex: key, relayUrl: relay)
        try await sync.publish(event)
    }

    func undoRepost(_ note: Note) async throws {
        let key = try signingKey()
        guard let me = Session.shared.pubkey else { return }
        guard let repostId = try await dbFindUserRepostEventId(userPubkeyHex: me, noteId: note.id) else { throw CoreError(L("eventNotFound")) }
        try await publishDeletion([repostId], key: key)
    }

    func delete(_ note: Note) async throws {
        let key = try signingKey()
        try await publishDeletion([note.id], key: key)
    }

    private func publishDeletion(_ ids: [String], key: String) async throws {
        let event = try createDeletionEvent(eventIds: ids, reason: "", privateKeyHex: key)
        try await sync.publish(event)
        _ = try? await dbDeleteEventsByIds(eventIds: ids)
        DataBus.shared.feedChanged()
        DataBus.shared.interactionsChanged()
    }

    func publishNote(content: String, mediaUrls: [String], extraTags: [[String]] = []) async throws -> String {
        let key = try signingKey()
        let body = Self.composeContent(content, mediaUrls: mediaUrls)
        let tags = Self.merge(Self.contentTags(body, mediaUrls: mediaUrls), extraTags)
        let event = try createNoteEvent(content: body, tags: tags, privateKeyHex: key)
        return try await publishReturningId(event)
    }

    func publishReply(to note: Note, content: String, mediaUrls: [String], extraTags: [[String]] = []) async throws -> String {
        let key = try signingKey()
        let me = Session.shared.pubkey ?? ""
        let body = Self.composeContent(content, mediaUrls: mediaUrls)
        let rootId = note.rootId ?? note.parentId ?? note.id
        var tags: [[String]] = []
        if rootId == note.id {
            tags.append(["e", note.id, "", "root", note.pubkey])
        } else {
            let rootAuthor = Self.rootAuthor(of: note, rootId: rootId)
            tags.append(["e", rootId, "", "root"] + (rootAuthor.map { [$0] } ?? []))
            tags.append(["e", note.id, "", "reply", note.pubkey])
        }
        var pubkeys: [String] = [note.pubkey]
        for tag in note.tags where tag.count > 1 && tag[0] == "p" && tag[1].count == 64 { pubkeys.append(tag[1]) }
        var seen: Set<String> = []
        for pk in pubkeys where pk != me && seen.insert(pk).inserted { tags.append(["p", pk]) }
        if seen.isEmpty, !note.pubkey.isEmpty { tags.append(["p", note.pubkey]) }
        let extra = Self.contentTags(body, mediaUrls: mediaUrls).filter { $0.first != "p" || !seen.contains($0.count > 1 ? $0[1] : "") }
        tags = Self.merge(tags, extra + extraTags.filter { $0.first != "e" })
        let event = try createReplyEvent(content: body, tags: tags, privateKeyHex: key)
        return try await publishReturningId(event)
    }

    func publishQuote(of note: Note, content: String, mediaUrls: [String], extraTags: [[String]] = []) async throws -> String {
        let key = try signingKey()
        let reference = Nip19.nevent(note.id, author: note.pubkey) ?? Nip19.note(note.id) ?? note.id
        let text = Self.composeContent(content, mediaUrls: mediaUrls)
        let body = text.isEmpty ? "nostr:\(reference)" : "\(text)\nnostr:\(reference)"
        let relay = await primaryRelay()
        let additional = Self.merge(Self.contentTags(body, mediaUrls: mediaUrls), extraTags).filter { tag in
            guard let first = tag.first else { return false }
            if first == "q" { return false }
            if first == "p", tag.count > 1, tag[1] == note.pubkey { return false }
            return true
        }
        let event = try createQuoteEvent(content: body, quotedEventId: note.id, quotedEventPubkey: note.pubkey, relayUrl: relay, privateKeyHex: key, additionalTags: additional)
        return try await publishReturningId(event)
    }

    func report(pubkey: String, noteId: String?, reason: String) async throws {
        let key = try signingKey()
        var tags: [[String]] = [["p", pubkey, reason]]
        if let noteId, !noteId.isEmpty { tags.append(["e", noteId, reason]) }
        let event = try createSignedEvent(kind: 1984, content: "", tags: tags, privateKeyHex: key)
        try await sync.publish(event)
    }

    private func publishReturningId(_ eventJson: String) async throws -> String {
        let event = try await sync.publish(eventJson)
        return event.str("id") ?? ""
    }

    func localCounts(_ noteIds: [String]) async -> [String: InteractionCounts] {
        guard let me = Session.shared.pubkey, !noteIds.isEmpty else { return [:] }
        let raw = try? await dbGetBatchInteractionData(noteIds: noteIds, userPubkeyHex: me)
        return Self.decodeCounts(raw)
    }

    func relayCounts(_ noteIds: [String]) async -> [String: InteractionCounts] {
        guard !noteIds.isEmpty else { return [:] }
        let raw = try? await fetchCountsFromRelays(noteIds: noteIds, userPubkeyHex: Session.shared.pubkey)
        return Self.decodeCounts(raw)
    }

    func liveCounts(_ noteIds: [String]) -> AsyncThrowingStream<[String: InteractionCounts], Error> {
        let me = Session.shared.pubkey
        let source = EventStream.make { sink in try await streamInteractionCounts(noteIds: noteIds, userPubkeyHex: me, sink: sink) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await raw in source { continuation.yield(Self.decodeCounts(raw)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func verify(_ note: Note) async -> (event: Bool, profile: Bool) {
        let event = (try? await verifyNoteById(eventIdHex: note.id)) ?? false
        let profile = (try? await verifyProfileByPubkey(pubkeyHex: note.pubkey)) ?? false
        return (event, profile)
    }

    func detailedInteractions(_ noteId: String) async -> [NoteInteractionDetail] {
        JSON.array(try? await dbGetDetailedInteractions(noteId: noteId)).compactMap(NoteInteractionDetail.init(json:))
    }

    static func decodeCounts(_ raw: String?) -> [String: InteractionCounts] {
        guard let map = JSON.object(raw) else { return [:] }
        var result: [String: InteractionCounts] = [:]
        for (key, value) in map {
            if let obj = value as? JSONObject { result[key] = InteractionCounts(json: obj) }
        }
        return result
    }

    static func composeContent(_ content: String, mediaUrls: [String]) -> String {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let media = mediaUrls.filter { !text.contains($0) }
        guard !media.isEmpty else { return text }
        return text.isEmpty ? media.joined(separator: "\n") : "\(text)\n\n\(media.joined(separator: "\n"))"
    }

    private static func rootAuthor(of note: Note, rootId: String) -> String? {
        for tag in note.tags where tag.count > 4 && tag[0] == "e" && tag[1] == rootId && tag[3] == "root" && tag[4].count == 64 {
            return tag[4]
        }
        return nil
    }

    static func contentTags(_ content: String, mediaUrls: [String]) -> [[String]] {
        var tags: [[String]] = []
        for tag in hashtags(in: content) { tags.append(["t", tag]) }
        for pubkey in mentionedPubkeys(in: content) { tags.append(["p", pubkey]) }
        for (id, _) in quotedEvents(in: content) { tags.append(["q", id]) }
        for url in mediaUrls {
            var imeta = ["imeta", "url \(url)"]
            if let mime = mimeType(forURL: url) { imeta.append("m \(mime)") }
            tags.append(imeta)
        }
        return tags
    }

    static func hashtags(in content: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "(?:^|\\s)#([\\p{L}\\p{N}_]+)") else { return [] }
        let ns = content as NSString
        var seen: [String] = []
        for match in regex.matches(in: content, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range(at: 1)).lowercased()
            if !seen.contains(tag) { seen.append(tag) }
        }
        return seen
    }

    static func mentionedPubkeys(in content: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "nostr:((?:npub1|nprofile1)[0-9a-z]+)", options: [.caseInsensitive]) else { return [] }
        let ns = content as NSString
        var result: [String] = []
        for match in regex.matches(in: content, range: NSRange(location: 0, length: ns.length)) {
            let bech = ns.substring(with: match.range(at: 1))
            if let hex = Nip19.pubkeyHex(from: bech), !result.contains(hex) { result.append(hex) }
        }
        return result
    }

    static func quotedEvents(in content: String) -> [(String, String)] {
        guard let regex = try? NSRegularExpression(pattern: "nostr:((?:note1|nevent1)[0-9a-z]+)", options: [.caseInsensitive]) else { return [] }
        let ns = content as NSString
        var result: [(String, String)] = []
        for match in regex.matches(in: content, range: NSRange(location: 0, length: ns.length)) {
            let bech = ns.substring(with: match.range(at: 1))
            if let hex = Nip19.decode(bech), !result.contains(where: { $0.0 == hex }) { result.append((hex, bech)) }
        }
        return result
    }

    static func mimeType(forURL url: String) -> String? {
        let path = (URL(string: url)?.path ?? url).lowercased()
        if path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") { return "image/jpeg" }
        if path.hasSuffix(".png") { return "image/png" }
        if path.hasSuffix(".gif") { return "image/gif" }
        if path.hasSuffix(".webp") { return "image/webp" }
        if path.hasSuffix(".mp4") { return "video/mp4" }
        if path.hasSuffix(".mov") { return "video/quicktime" }
        return nil
    }

    private static func imetaKey(_ entry: String) -> Substring {
        entry.split(separator: " ", maxSplits: 1).first ?? Substring(entry)
    }

    static func merge(_ base: [[String]], _ extra: [[String]]) -> [[String]] {
        var result = base
        for tag in extra where !tag.isEmpty {
            if tag.first == "imeta", let url = tag.dropFirst().first, let index = result.firstIndex(where: { $0.first == "imeta" && $0.dropFirst().first == url }) {
                var merged = result[index]
                for entry in tag.dropFirst(2) where !merged.dropFirst().contains(where: { imetaKey($0) == imetaKey(entry) }) { merged.append(entry) }
                result[index] = merged
            } else if !result.contains(where: { Array($0.prefix(2)) == Array(tag.prefix(2)) }) {
                result.append(tag)
            }
        }
        return result
    }
}
