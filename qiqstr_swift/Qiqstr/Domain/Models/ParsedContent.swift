import Foundation

enum ContentPart: Hashable, Sendable {
    case text(String)
    case mention(String)
}

struct ParsedContent: Hashable, Sendable {
    var parts: [ContentPart]
    var mediaUrls: [String]
    var linkUrls: [String]
    var quoteIds: [String]
    var articleIds: [String]

    init(json j: JSONObject) {
        parts = ((j["textParts"] as? [JSONObject]) ?? []).compactMap { p in
            switch p.str("type") {
            case "text": return .text((p["text"] as? String) ?? "")
            case "mention": return p.str("id").map { .mention($0) }
            default: return nil
            }
        }
        mediaUrls = j.strings("mediaUrls")
        linkUrls = j.strings("linkUrls")
        quoteIds = j.strings("quoteIds")
        articleIds = j.strings("articleIds")
    }
}
