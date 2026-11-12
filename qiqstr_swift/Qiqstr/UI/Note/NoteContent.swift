import Foundation
import SwiftUI

enum NoteContentSegment: Hashable, Sendable {
    case text(String)
    case link(String)
    case hashtag(String)
    case mention(String)
}

struct NoteMediaItem: Hashable, Sendable, Identifiable {
    var id: String { url }
    var url: String
    var isVideo: Bool
    var aspectRatio: CGFloat?
    var blurhash: String?
    var alt: String?
    var poster: String?
}

struct NoteImeta: Hashable, Sendable {
    var url: String
    var mimeType: String?
    var size: CGSize?
    var blurhash: String?
    var alt: String?
    var poster: String?

    var aspectRatio: CGFloat? { size.map { $0.width / $0.height } }

    init?(tag: [String]) {
        guard tag.first == "imeta" else { return nil }
        var fields: [String: String] = [:]
        for entry in tag.dropFirst() {
            guard let space = entry.firstIndex(of: " ") else { continue }
            let key = String(entry[..<space])
            if fields[key] == nil { fields[key] = String(entry[entry.index(after: space)...]).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        guard let url = fields["url"], !url.isEmpty else { return nil }
        self.url = url
        mimeType = fields["m"]?.lowercased()
        if let dim = fields["dim"] {
            let parts = dim.lowercased().split(separator: "x").compactMap { Double($0) }
            if parts.count == 2, parts[0] > 0, parts[1] > 0 { size = CGSize(width: parts[0], height: parts[1]) }
        }
        blurhash = fields["blurhash"]?.nilIfEmpty
        alt = fields["alt"]?.nilIfEmpty
        poster = fields["image"]?.nilIfEmpty ?? fields["thumb"]?.nilIfEmpty
    }

    static func map(_ tags: [[String]]) -> [String: NoteImeta] {
        var result: [String: NoteImeta] = [:]
        for tag in tags {
            if let meta = NoteImeta(tag: tag), result[meta.url] == nil { result[meta.url] = meta }
        }
        return result
    }
}

final class NoteContent {
    static let truncationLimit = 280

    let segments: [NoteContentSegment]
    let truncatedSegments: [NoteContentSegment]?
    let media: [NoteMediaItem]
    let linkUrls: [String]
    let quoteIds: [String]
    let articleIds: [String]
    let mentionPubkeys: [String]
    let isEmptyText: Bool
    let contentWarning: String?

    init(content: String, tags: [[String]]) {
        let parsed = NoteRepository.parse(content)
        let imeta = NoteImeta.map(tags)
        contentWarning = Note.contentWarning(content: content, tags: tags)
        var segments: [NoteContentSegment] = []
        var mentions: [String] = []
        for part in parsed.parts {
            switch part {
            case .text(let text): segments.append(contentsOf: Self.split(text))
            case .mention(let bech):
                segments.append(.mention(bech))
                if let hex = Nip19.pubkeyHex(from: bech), !mentions.contains(hex) { mentions.append(hex) }
            }
        }
        self.segments = segments
        truncatedSegments = Self.truncate(segments, limit: Self.truncationLimit)
        media = parsed.mediaUrls.map { url in
            let lower = (URL(string: url)?.path ?? url).lowercased()
            let meta = imeta[url]
            let isVideo = meta?.mimeType?.hasPrefix("video/") ?? (lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.hasSuffix(".m4v") || lower.hasSuffix(".webm"))
            return NoteMediaItem(url: url, isVideo: isVideo, aspectRatio: meta?.aspectRatio, blurhash: meta?.blurhash, alt: meta?.alt, poster: meta?.poster)
        }
        linkUrls = parsed.linkUrls
        var quotes: [String] = []
        for bech in parsed.quoteIds {
            if let hex = Nip19.decode(bech), !quotes.contains(hex) { quotes.append(hex) }
        }
        quoteIds = quotes
        var articles: [String] = []
        for naddr in parsed.articleIds where !articles.contains(naddr) { articles.append(naddr) }
        articleIds = articles
        mentionPubkeys = mentions
        isEmptyText = segments.allSatisfy { segment in
            if case .text(let t) = segment { return t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return false
        }
    }

    var images: [NoteMediaItem] { media.filter { !$0.isVideo } }
    var videos: [NoteMediaItem] { media.filter(\.isVideo) }
    var translatableText: String {
        segments.compactMap { segment -> String? in
            switch segment {
            case .text(let text): text
            case .hashtag(let tag): "#\(tag)"
            case .link, .mention: nil
            }
        }
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var previewLink: String? { linkUrls.count == 1 && media.isEmpty ? linkUrls.first : nil }

    private static let linkRegex = try? NSRegularExpression(pattern: "https?://[^\\s<>\"']+", options: [.caseInsensitive])
    private static let hashtagRegex = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_/#&])#[\\p{L}\\p{N}_]+")

    private static func split(_ text: String) -> [NoteContentSegment] {
        guard let linkRegex, let hashtagRegex else { return [.text(text)] }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var tokens: [(NSRange, NoteContentSegment)] = []
        for match in linkRegex.matches(in: text, range: full) {
            var url = ns.substring(with: match.range)
            while let last = url.last, ".,;:!?)]}".contains(last) { url.removeLast() }
            tokens.append((NSRange(location: match.range.location, length: (url as NSString).length), .link(url)))
        }
        for match in hashtagRegex.matches(in: text, range: full) where !tokens.contains(where: { NSIntersectionRange($0.0, match.range).length > 0 }) {
            tokens.append((match.range, .hashtag(String(ns.substring(with: match.range).dropFirst()))))
        }
        tokens.sort { $0.0.location < $1.0.location }
        var result: [NoteContentSegment] = []
        var cursor = 0
        for (range, segment) in tokens {
            if range.location > cursor { result.append(.text(ns.substring(with: NSRange(location: cursor, length: range.location - cursor)))) }
            result.append(segment)
            cursor = range.location + range.length
        }
        if cursor < ns.length { result.append(.text(ns.substring(from: cursor))) }
        return result
    }

    private static func truncate(_ segments: [NoteContentSegment], limit: Int) -> [NoteContentSegment]? {
        var length = 0
        var result: [NoteContentSegment] = []
        for segment in segments {
            let cost: Int
            switch segment {
            case .text(let t): cost = t.count
            case .link(let l): cost = min(l.count, 34)
            case .hashtag(let h): cost = h.count + 1
            case .mention: cost = 8
            }
            if length + cost <= limit {
                result.append(segment)
                length += cost
                continue
            }
            if case .text(let t) = segment, limit - length > 0 {
                var cut = String(t.prefix(limit - length))
                if let space = cut.lastIndex(where: { $0 == " " || $0 == "\n" }), cut.distance(from: space, to: cut.endIndex) < 24 {
                    cut = String(cut[..<space])
                }
                while cut.last?.isWhitespace == true { cut.removeLast() }
                result.append(.text(cut + "…"))
            } else {
                result.append(.text("…"))
            }
            return result
        }
        let newlineCount = segments.reduce(0) { count, segment in
            if case .text(let t) = segment { return count + t.filter { $0 == "\n" }.count }
            return count
        }
        if newlineCount > 12 {
            var lines = 0
            var cut: [NoteContentSegment] = []
            for segment in segments {
                if case .text(let t) = segment {
                    var kept = ""
                    for ch in t {
                        if ch == "\n" { lines += 1 }
                        if lines >= 12 { break }
                        kept.append(ch)
                    }
                    cut.append(.text(kept))
                    if lines >= 12 {
                        cut.append(.text("…"))
                        return cut
                    }
                } else {
                    cut.append(segment)
                }
            }
        }
        return nil
    }

    static func displayURL(_ url: String) -> String {
        var s = url.replacingOccurrences(of: "^https?://(www\\.)?", with: "", options: .regularExpression)
        if s.hasSuffix("/") { s.removeLast() }
        return s.count > 36 ? "\(s.prefix(34))…" : s
    }

    func attributed(_ segments: [NoteContentSegment], font: Font = .body, cache: ProfileCache) -> AttributedString {
        var result = AttributedString()
        for segment in segments {
            switch segment {
            case .text(let text):
                result += AttributedString(text)
            case .link(let url):
                var part = AttributedString(Self.displayURL(url))
                part.link = URL(string: url)
                part.foregroundColor = AppColors.link
                result += part
            case .hashtag(let tag):
                var part = AttributedString("#\(tag)")
                part.link = NoteLink.hashtag(tag)
                part.foregroundColor = AppColors.link
                result += part
            case .mention(let bech):
                let hex = Nip19.pubkeyHex(from: bech)
                let name = hex.flatMap { cache.profile($0)?.bestName } ?? hex.map(Profile.shortNpub) ?? bech
                var part = AttributedString("@\(name)")
                part.link = hex.map(NoteLink.profile)
                part.foregroundColor = AppColors.link
                part.font = font.weight(.medium)
                result += part
            }
        }
        return result
    }
}

enum NoteLink {
    static let scheme = "qiqstr-note"
    static func profile(_ pubkey: String) -> URL { URL(string: "\(scheme)://profile/\(pubkey)")! }
    static func hashtag(_ tag: String) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "hashtag"
        c.path = "/\(tag)"
        return c.url ?? URL(string: "\(scheme)://hashtag/")!
    }

    @MainActor
    static func handle(_ url: URL) -> OpenURLAction.Result {
        let router = Router.shared
        if url.scheme == scheme {
            let value = String(url.path.dropFirst())
            switch url.host {
            case "profile": router.push(.profile(value))
            case "hashtag": router.push(.hashtag(value))
            default: break
            }
            return .handled
        }
        if url.scheme == "nostr" {
            router.open(url: url)
            return .handled
        }
        if url.scheme == "http" || url.scheme == "https" {
            router.sheet = .url(url)
            return .handled
        }
        return .systemAction
    }
}

@MainActor
enum NoteContentCache {
    private static var store: [String: NoteContent] = [:]
    private static var order: [String] = []
    private static let capacity = 1500

    static func content(for note: Note) -> NoteContent {
        if let hit = store[note.id] { return hit }
        let content = NoteContent(content: note.content, tags: note.tags)
        insert(content, for: note.id)
        return content
    }

    static func cached(_ id: String) -> NoteContent? { store[id] }

    static func warm(_ notes: [Note]) async {
        var built = 0
        for note in notes where store[note.id] == nil {
            insert(NoteContent(content: note.content, tags: note.tags), for: note.id)
            built += 1
            if built % 12 == 0 { await Task.yield() }
        }
    }

    private static func insert(_ content: NoteContent, for id: String) {
        store[id] = content
        order.append(id)
        if order.count > capacity {
            let overflow = order.prefix(order.count - capacity)
            for key in overflow { store.removeValue(forKey: key) }
            order.removeFirst(overflow.count)
        }
    }
}
