import Foundation

enum NotificationKind: String, Sendable {
    case reaction, repost, reply, mention, zap, quote, unknown
}

struct NotificationItem: Identifiable, Hashable, Sendable {
    var id: String
    var kind: NotificationKind
    var fromPubkey: String
    var targetNoteId: String?
    var content: String
    var createdAt: Int
    var fromName: String?
    var fromImage: String?
    var zapAmount: Int

    init(json j: JSONObject) {
        id = j.str("id") ?? UUID().uuidString
        kind = NotificationKind(rawValue: j.str("type") ?? "") ?? .unknown
        fromPubkey = j.str("fromPubkey") ?? ""
        targetNoteId = j.str("targetNoteId")
        content = (j["content"] as? String) ?? ""
        createdAt = j.int("createdAt")
        fromName = j.str("fromName")
        fromImage = j.str("fromImage")
        zapAmount = min(max(0, j.int("zapAmount")), SatsAmount.maximum)
    }
}
