import Foundation
import SwiftUI

nonisolated struct EmojiEntry: Hashable, Sendable, Identifiable {
    var id: String { emoji }
    let emoji: String
    let name: String
}

nonisolated struct EmojiGroup: Identifiable, Sendable {
    let id: String
    let items: [EmojiEntry]

    var symbol: String {
        switch id {
        case "smileys": "face.smiling"
        case "people": "hand.wave"
        case "nature": "leaf"
        case "food": "fork.knife"
        case "travel": "car"
        case "activities": "soccerball"
        case "objects": "lightbulb"
        case "symbols": "heart"
        default: "flag"
        }
    }

    var title: String {
        switch id {
        case "smileys": L("emojiSmileys")
        case "people": L("emojiPeople")
        case "nature": L("emojiNature")
        case "food": L("emojiFood")
        case "travel": L("emojiTravel")
        case "activities": L("emojiActivities")
        case "objects": L("emojiObjects")
        case "symbols": L("emojiSymbols")
        default: L("emojiFlags")
        }
    }
}

nonisolated enum EmojiCatalog {
    static let groups: [EmojiGroup] = {
        guard let url = Bundle.main.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return raw.compactMap { group in
            guard let id = group["id"] as? String, let items = group["items"] as? [String] else { return nil }
            return EmojiGroup(id: id, items: items.compactMap { item in
                let parts = item.split(separator: "|", maxSplits: 1)
                return parts.count == 2 ? EmojiEntry(emoji: String(parts[0]), name: String(parts[1])) : nil
            })
        }
    }()

    static func search(_ query: String) -> [EmojiEntry] {
        let terms = query.lowercased().split(separator: " ")
        guard !terms.isEmpty else { return [] }
        return groups.flatMap(\.items).filter { entry in terms.allSatisfy { entry.name.contains($0) } }
    }
}

nonisolated struct CustomEmoji: Hashable, Sendable, Identifiable, Codable {
    var id: String { "\(shortcode)|\(url)" }
    var shortcode: String
    var url: String

    var token: String { ":\(shortcode):" }

    init(shortcode: String, url: String) {
        self.shortcode = shortcode
        self.url = url
    }

    init?(tag: [String]) {
        guard tag.count >= 3, tag[0] == "emoji", Self.isShortcode(tag[1]), tag[2].hasPrefix("https://") else { return nil }
        shortcode = tag[1]
        url = tag[2]
    }

    static func isShortcode(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 64 && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    static func map(_ tags: [[String]]) -> [String: String] {
        var result: [String: String] = [:]
        for tag in tags {
            if let emoji = CustomEmoji(tag: tag), result[emoji.shortcode] == nil { result[emoji.shortcode] = emoji.url }
        }
        return result
    }

    static func shortcode(in content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 2, trimmed.hasPrefix(":"), trimmed.hasSuffix(":") else { return nil }
        let code = String(trimmed.dropFirst().dropLast())
        return isShortcode(code) ? code : nil
    }
}

nonisolated enum EmojiChoice: Hashable, Sendable {
    case unicode(String)
    case custom(CustomEmoji)

    var content: String {
        switch self {
        case .unicode(let emoji): emoji
        case .custom(let emoji): emoji.token
        }
    }

    var stored: String {
        switch self {
        case .unicode(let emoji): emoji
        case .custom(let emoji): "\(emoji.shortcode)|\(emoji.url)"
        }
    }

    init(stored: String) {
        let parts = stored.split(separator: "|", maxSplits: 1).map(String.init)
        if parts.count == 2, parts[1].hasPrefix("https://"), CustomEmoji.isShortcode(parts[0]) {
            self = .custom(CustomEmoji(shortcode: parts[0], url: parts[1]))
        } else {
            self = .unicode(stored)
        }
    }
}

@MainActor
@Observable
final class RecentEmojiStore {
    static let shared = RecentEmojiStore()
    private static let key = "emoji_recent"
    private static let limit = 24

    private(set) var items: [EmojiChoice] = (UserDefaults.standard.stringArray(forKey: RecentEmojiStore.key) ?? []).map(EmojiChoice.init(stored:))

    func record(_ choice: EmojiChoice) {
        items.removeAll { $0 == choice }
        items.insert(choice, at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
        UserDefaults.standard.set(items.map(\.stored), forKey: Self.key)
    }
}

@MainActor
@Observable
final class InlineEmojiStore {
    static let shared = InlineEmojiStore()
    private(set) var version = 0
    @ObservationIgnored private var images: [String: UIImage] = [:]
    @ObservationIgnored private var loading: Set<String> = []

    func image(_ url: String, pointSize: CGFloat = 20) -> UIImage? {
        _ = version
        if let hit = images[url] { return hit }
        guard loading.insert(url).inserted, let remote = URL(string: url) else { return nil }
        Task {
            guard let loaded = await ImagePipeline.shared.image(for: remote, maxPixel: 72), let cg = loaded.cgImage else { return }
            images[url] = Self.sized(cg, pointSize: pointSize)
            version += 1
        }
        return nil
    }

    private static func sized(_ image: CGImage, pointSize: CGFloat) -> UIImage {
        let height = max(1, CGFloat(image.height))
        #if os(iOS)
        return UIImage(cgImage: image, scale: height / pointSize, orientation: .up)
        #else
        return NSImage(cgImage: image, size: NSSize(width: pointSize * CGFloat(image.width) / height, height: pointSize))
        #endif
    }
}
