import Foundation

actor Nip05Verifier {
    static let shared = Nip05Verifier()

    private struct Entry {
        var verified: Bool
        var checkedAt: Date
    }

    private var cache: [String: Entry] = [:]
    private var inflight: [String: Task<Bool, Never>] = [:]
    private let ttl: TimeInterval = 60 * 30
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    nonisolated static func parts(_ nip05: String) -> (name: String, domain: String)? {
        let trimmed = nip05.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pieces = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        if pieces.count == 1, isDomain(String(pieces[0])) { return ("_", String(pieces[0])) }
        guard pieces.count == 2, !pieces[0].isEmpty, isDomain(String(pieces[1])) else { return nil }
        return (String(pieces[0]), String(pieces[1]))
    }

    nonisolated static func isValid(_ nip05: String) -> Bool {
        let trimmed = nip05.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || (trimmed.contains("@") && parts(trimmed) != nil)
    }

    nonisolated static func display(_ nip05: String) -> String {
        guard let parts = parts(nip05) else { return nip05 }
        return parts.name == "_" ? parts.domain : "\(parts.name)@\(parts.domain)"
    }

    nonisolated private static func isDomain(_ s: String) -> Bool {
        s.contains(".") && !s.hasPrefix(".") && !s.hasSuffix(".") && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == ":" }
    }

    func verify(nip05: String, pubkey: String) async -> Bool {
        guard let parts = Self.parts(nip05) else { return false }
        let key = "\(parts.name)@\(parts.domain)#\(pubkey.lowercased())"
        if let entry = cache[key], Date().timeIntervalSince(entry.checkedAt) < ttl { return entry.verified }
        if let task = inflight[key] { return await task.value }
        let task = Task { await self.lookup(name: parts.name, domain: parts.domain, pubkey: pubkey.lowercased()) }
        inflight[key] = task
        let verified = await task.value
        inflight[key] = nil
        cache[key] = Entry(verified: verified, checkedAt: Date())
        return verified
    }

    private func lookup(name: String, domain: String, pubkey: String) async -> Bool {
        var components = URLComponents()
        components.scheme = "https"
        components.host = domain
        components.path = "/.well-known/nostr.json"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components.url else { return false }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let names = json["names"] as? [String: Any] else { return false }
        let match = names.first { $0.key.lowercased() == name }?.value as? String
        return match?.lowercased() == pubkey
    }
}
