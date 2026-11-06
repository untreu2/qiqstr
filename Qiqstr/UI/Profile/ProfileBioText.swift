import SwiftUI

enum BioToken: Hashable {
    case text(String)
    case profile(String)
    case note(String)
    case article(String)
    case hashtag(String)
    case link(URL, String)
}

enum BioParser {
    private static let bech = "[02-9ac-hj-np-z]"
    private static let regex: NSRegularExpression = {
        let pattern = "(?:nostr:)?((?:npub1|note1)\(bech){58}|(?:nprofile1|nevent1|naddr1)\(bech){20,})|(https?://[^\\s<>\"]+)|(?<![\\p{L}\\p{N}_&/])#([\\p{L}\\p{N}_]{1,64})"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    static func tokens(_ text: String) -> [BioToken] {
        let ns = text as NSString
        var result: [BioToken] = []
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var range = match.range
            var token: BioToken?
            if match.range(at: 1).location != NSNotFound {
                token = entity(ns.substring(with: match.range(at: 1)))
            } else if match.range(at: 2).location != NSNotFound {
                var raw = ns.substring(with: match.range(at: 2))
                while let last = raw.last, ".,;:!?)]}'\"".contains(last) {
                    raw.removeLast()
                    range.length -= 1
                }
                if let url = URL(string: raw) { token = .link(url, raw) }
            } else if match.range(at: 3).location != NSNotFound {
                token = .hashtag(ns.substring(with: match.range(at: 3)))
            }
            guard let token else { continue }
            if range.location > cursor { result.append(.text(ns.substring(with: NSRange(location: cursor, length: range.location - cursor)))) }
            result.append(token)
            cursor = range.location + range.length
        }
        if cursor < ns.length { result.append(.text(ns.substring(from: cursor))) }
        return result
    }

    private static func entity(_ raw: String) -> BioToken? {
        let lower = raw.lowercased()
        if lower.hasPrefix("npub1") || lower.hasPrefix("nprofile1") {
            return Nip19.pubkeyHex(from: lower).map(BioToken.profile)
        }
        if lower.hasPrefix("note1") || lower.hasPrefix("nevent1") {
            return Nip19.decode(lower).map(BioToken.note)
        }
        if lower.hasPrefix("naddr1") { return .article(lower) }
        return nil
    }
}

enum ProfileLink {
    static let scheme = "qiqstr-internal"

    static func url(_ kind: String, _ value: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = kind
        components.path = "/" + value
        return components.url
    }

    static func handle(_ url: URL) -> OpenURLAction.Result {
        let router = Router.shared
        guard url.scheme == scheme else {
            if url.scheme == "http" || url.scheme == "https" {
                router.sheet = .url(url)
            } else if url.scheme == "nostr" {
                router.open(url: url)
            } else {
                return .systemAction
            }
            return .handled
        }
        let value = String(url.path.dropFirst())
        switch url.host {
        case "profile": router.push(.profile(value))
        case "note": router.push(.thread(value))
        case "article": router.push(.articleAddress(value))
        case "hashtag": router.push(.hashtag(value))
        default: return .discarded
        }
        return .handled
    }
}

struct ProfileBioText: View {
    let text: String
    var font: Font = .subheadline
    @State private var cache = ProfileCache.shared

    private var tokens: [BioToken] { BioParser.tokens(text) }

    var body: some View {
        Text(attributed)
            .font(font)
            .foregroundStyle(.primary)
            .tint(AppColors.textPrimary)
            .lineSpacing(2)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction(handler: ProfileLink.handle))
            .task(id: text) {
                let pubkeys = tokens.compactMap { token -> String? in
                    if case .profile(let pk) = token { return pk }
                    return nil
                }
                if !pubkeys.isEmpty { await cache.load(pubkeys) }
            }
    }

    private var attributed: AttributedString {
        var output = AttributedString()
        for token in tokens {
            switch token {
            case .text(let s):
                output += AttributedString(s)
            case .profile(let pk):
                let name = cache.profile(pk)?.bestName ?? Profile.shortNpub(pk)
                output += linked("@\(name)", ProfileLink.url("profile", pk), weight: .semibold)
            case .note(let id):
                output += linked(Nip19.note(id).map { "\($0.prefix(14))…" } ?? id, ProfileLink.url("note", id), weight: .medium)
            case .article(let naddr):
                output += linked("\(naddr.prefix(14))…", ProfileLink.url("article", naddr), weight: .medium)
            case .hashtag(let tag):
                output += linked("#\(tag)", ProfileLink.url("hashtag", tag), weight: .semibold)
            case .link(let url, let raw):
                output += linked(Self.prettyLink(raw), url, weight: .regular, underline: true)
            }
        }
        return output
    }

    private func linked(_ label: String, _ url: URL?, weight: Font.Weight, underline: Bool = false) -> AttributedString {
        var piece = AttributedString(label)
        piece.link = url
        piece.font = font.weight(weight)
        piece.foregroundColor = AppColors.textPrimary
        if underline { piece.underlineStyle = .single }
        return piece
    }

    static func prettyLink(_ raw: String) -> String {
        var s = raw
        for prefix in ["https://", "http://"] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        if s.hasSuffix("/") { s.removeLast() }
        return s.count > 42 ? "\(s.prefix(40))…" : s
    }
}
