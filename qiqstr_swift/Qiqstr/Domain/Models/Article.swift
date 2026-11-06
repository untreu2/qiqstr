import Foundation

struct Article: Identifiable, Hashable, Sendable {
    var id: String
    var pubkey: String
    var title: String
    var content: String
    var image: String?
    var summary: String?
    var dTag: String
    var publishedAt: Int
    var createdAt: Int
    var hashtags: [String]
    var authorName: String?
    var authorImage: String?

    init(json j: JSONObject) {
        id = j.str("id") ?? ""
        pubkey = j.str("pubkey") ?? ""
        title = j.str("title") ?? ""
        content = (j["content"] as? String) ?? ""
        image = j.str("image")
        summary = j.str("summary")
        dTag = j.str("dTag") ?? ""
        publishedAt = j.int("publishedAt")
        createdAt = j.int("created_at")
        hashtags = j.strings("hashtags")
        authorName = j.str("authorName")
        authorImage = j.str("authorImage")
    }
}
