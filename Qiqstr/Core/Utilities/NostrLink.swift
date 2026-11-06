import Foundation

enum NostrLink: Equatable {
    case profile(entity: String)
    case event(entity: String)
    case address(entity: String)

    static let webHosts: Set<String> = [
        "njump.me", "primal.net", "damus.io", "snort.social", "iris.to", "nostr.com", "nostr.band",
        "coracle.social", "nostrudel.ninja", "yakihonne.com", "habla.news", "highlighter.com", "zap.stream", "nostter.app",
    ]

    private static let prefixes = ["npub1", "nprofile1", "note1", "nevent1", "naddr1"]
    private static let charset = Set("023456789acdefghjklmnpqrstuvwxyz")

    var entity: String {
        switch self {
        case .profile(let e), .event(let e), .address(let e): e
        }
    }

    init?(url: URL) {
        if url.scheme?.lowercased() == "nostr" {
            self.init(entity: String(url.absoluteString.dropFirst("nostr:".count)))
            return
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host()?.lowercased() else { return nil }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard Self.webHosts.contains(bare) else { return nil }
        for component in url.pathComponents.reversed() {
            if let link = NostrLink(entity: component) {
                self = link
                return
            }
        }
        return nil
    }

    init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let link = NostrLink(entity: trimmed) {
            self = link
        } else if let url = URL(string: trimmed), let link = NostrLink(url: url) {
            self = link
        } else {
            return nil
        }
    }

    init?(entity raw: String) {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("nostr:") { value = String(value.dropFirst(6)) }
        if value.hasPrefix("//") { value = String(value.dropFirst(2)) }
        guard let prefix = Self.prefixes.first(where: value.hasPrefix) else { return nil }
        let body = value.dropFirst(prefix.count)
        guard body.count >= 20, body.allSatisfy(Self.charset.contains) else { return nil }
        switch prefix {
        case "npub1", "nprofile1": self = .profile(entity: value)
        case "naddr1": self = .address(entity: value)
        default: self = .event(entity: value)
        }
    }
}
