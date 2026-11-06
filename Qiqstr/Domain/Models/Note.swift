import Foundation

struct Note: Identifiable, Hashable, Sendable {
    var id: String
    var pubkey: String
    var content: String
    var createdAt: Int
    var tags: [[String]]
    var isRepost: Bool
    var repostEventId: String?
    var repostedBy: String?
    var repostedByName: String?
    var repostCreatedAt: Int?
    var isReply: Bool
    var isQuote: Bool
    var quotedNoteId: String?
    var rootId: String?
    var parentId: String?
    var authorName: String?
    var authorImage: String?
    var authorNip05: String?
    var reactionCount: Int
    var repostCount: Int
    var replyCount: Int
    var zapCount: Int
    var hasReacted: Bool
    var hasReposted: Bool
    var hasZapped: Bool

    var displayTimestamp: Int { repostCreatedAt ?? createdAt }
    var listId: String { repostEventId ?? id }

    init(json j: JSONObject) {
        id = j.str("id") ?? ""
        pubkey = j.str("pubkey") ?? j.str("author") ?? ""
        content = (j["content"] as? String) ?? ""
        createdAt = j.int("created_at") != 0 ? j.int("created_at") : j.int("createdAt")
        tags = j.tags()
        isRepost = j.bool("isRepost")
        repostEventId = j.str("repostEventId")
        repostedBy = j.str("repostedBy")
        repostedByName = j.str("repostedByName")
        repostCreatedAt = j["repostCreatedAt"] is NSNumber ? j.int("repostCreatedAt") : nil
        isReply = j.bool("isReply")
        isQuote = j.bool("isQuote")
        quotedNoteId = j.str("quotedNoteId")
        rootId = j.str("rootId")
        parentId = j.str("parentId")
        authorName = j.str("authorName")
        authorImage = j.str("authorImage")
        authorNip05 = j.str("authorNip05")
        reactionCount = j.int("reactionCount")
        repostCount = j.int("repostCount")
        replyCount = j.int("replyCount")
        zapCount = j.int("zapCount")
        hasReacted = j.bool("hasReacted")
        hasReposted = j.bool("hasReposted")
        hasZapped = j.bool("hasZapped")
    }

    static func list(_ json: String?) -> [Note] {
        JSON.array(json).map(Note.init(json:)).filter { !$0.id.isEmpty }
    }

    var hashtags: [String] { tags.filter { $0.first == "t" && $0.count > 1 }.map { $0[1] } }

    var contentWarning: String? { Note.contentWarning(content: content, tags: tags) }

    static func contentWarning(content: String, tags: [[String]]) -> String? {
        for tag in tags where tag.first == "content-warning" {
            return tag.count > 1 ? tag[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        }
        let namespaced = tags.contains { $0.count > 1 && $0[0] == "L" && $0[1].lowercased() == "content-warning" }
        for tag in tags where tag.count > 1 && tag[0] == "l" {
            if tag[1].lowercased() == "content-warning" { return "" }
            if tag.count > 2, tag[2].lowercased() == "content-warning" { return tag[1] }
            if namespaced, tag.count == 2 { return tag[1] }
        }
        if namespaced { return "" }
        let tagged = tags.contains { $0.count > 1 && $0[0] == "t" && $0[1].lowercased() == "nsfw" }
        if tagged || content.range(of: "(^|\\s)#nsfw(?![\\p{L}\\p{N}_])", options: [.regularExpression, .caseInsensitive]) != nil { return "NSFW" }
        return nil
    }
}
