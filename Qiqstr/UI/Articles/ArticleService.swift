import Foundation
import QiqstrCore

struct ArticleAddress: Hashable, Sendable {
    var pubkey: String
    var identifier: String
    var kind: Int = 30023

    init(pubkey: String, identifier: String, kind: Int = 30023) {
        self.pubkey = pubkey
        self.identifier = identifier
        self.kind = kind
    }

    init?(naddr: String) {
        guard let tlv = Nip19.decodeTLV(naddr.trimmingCharacters(in: .whitespacesAndNewlines)), tlv.str("type") == "naddr",
              let pubkey = tlv.str("pubkey") else { return nil }
        self.init(pubkey: pubkey, identifier: (tlv["identifier"] as? String) ?? "", kind: tlv.int("kind") == 0 ? 30023 : tlv.int("kind"))
    }

    var naddr: String? { Nip19.naddr(kind: UInt16(kind), pubkey: pubkey, identifier: identifier) }
}

extension Article {
    var address: ArticleAddress { ArticleAddress(pubkey: pubkey, identifier: dTag) }
    var naddr: String? { address.naddr }
    var shareURL: URL? { naddr.flatMap { URL(string: "https://njump.me/\($0)") } }
    var displayTitle: String { title.isEmpty ? L("untitledArticle") : title }
    var readingMinutes: Int { max(1, content.split(whereSeparator: \.isWhitespace).count / 220) }
}

@MainActor
enum ArticleService {
    static let pageSize = 50

    static func articles(authors: [String]?, limit: Int) async -> [Article] {
        let session = Session.shared
        let raw = try? await dbGetHydratedArticles(authorsHex: authors, limit: UInt32(limit), mutedPubkeys: session.mutedPubkeys, mutedWords: session.mutedWords)
        var seen = Set<String>()
        return JSON.array(raw).map(Article.init(json:)).filter { !$0.id.isEmpty && seen.insert("\($0.pubkey):\($0.dTag)").inserted }
    }

    static func sync(authors: [String]?, force: Bool) async {
        await SyncService.shared.syncArticles(authors: authors, force: force)
    }

    static func fetchOlder(authors: [String]?, until: Int) async -> Int {
        var filter: JSONObject = ["kinds": [30023], "until": max(0, until - 1), "limit": pageSize]
        if let authors { filter["authors"] = authors }
        let events = await SyncService.shared.fetchEvents(filter, timeout: 10)
        guard !events.isEmpty else { return 0 }
        _ = try? await dbSaveEvents(eventsJson: JSON.string(events))
        SyncService.shared.fetchMissingProfiles(Array(Set(events.compactMap { $0.str("pubkey") })))
        return events.count
    }

    static func article(id: String) async -> Article? {
        guard let raw = try? await dbGetHydratedArticle(eventId: id), let json = JSON.object(raw) else { return nil }
        let article = Article(json: json)
        return article.id.isEmpty ? nil : article
    }

    static func article(at address: ArticleAddress) async -> Article? {
        guard let raw = try? await dbGetHydratedArticleByNaddr(pubkeyHex: address.pubkey, dTag: address.identifier), let json = JSON.object(raw) else { return nil }
        let article = Article(json: json)
        return article.id.isEmpty ? nil : article
    }

    static func fetch(id: String) async -> Article? {
        if let raw = try? await fetchEventById(eventId: id, timeoutSecs: 8), JSON.object(raw) != nil {
            _ = try? await dbSaveEvents(eventsJson: "[\(raw)]")
        }
        return await article(id: id)
    }

    @discardableResult
    static func fetch(address: ArticleAddress) async -> Article? {
        let events = await SyncService.shared.fetchEvents(["kinds": [address.kind], "authors": [address.pubkey], "#d": [address.identifier], "limit": 1], timeout: 10)
        if !events.isEmpty {
            _ = try? await dbSaveEvents(eventsJson: JSON.string(events))
            DataBus.shared.feedChanged()
        }
        return await article(at: address)
    }

    static func note(id: String) async -> Note? {
        let session = Session.shared
        func local() async -> Note? {
            Note.list(try? await dbGetHydratedNotesByIds(eventIds: [id], mutedPubkeys: [], mutedWords: [], currentUserPubkeyHex: session.pubkey)).first
        }
        if let note = await local() { return note }
        if let raw = try? await fetchEventById(eventId: id, timeoutSecs: 8), let event = JSON.object(raw) {
            _ = try? await dbSaveEvents(eventsJson: "[\(raw)]")
            SyncService.shared.backgroundFollowUps([event])
        }
        return await local()
    }
}
