import Foundation

struct Nip05Identity: Sendable {
    var pubkey: String
    var relays: [String]
}

enum Nip05Resolver {
    static func looksLikeAddress(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace), let at = trimmed.lastIndex(of: "@") else { return false }
        let domain = trimmed[trimmed.index(after: at)...]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    static func resolve(_ address: String) async throws -> Nip05Identity {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = trimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else { throw AuthError.nip05NotFound(address) }
        let name = parts[0].isEmpty ? "_" : parts[0]
        var components = URLComponents()
        components.scheme = "https"
        components.host = parts[1]
        components.path = "/.well-known/nostr.json"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components.url else { throw AuthError.nip05NotFound(address) }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let names = root["names"] as? [String: Any],
              let pubkey = (names[name] ?? names.first { $0.key.lowercased() == name }?.value) as? String,
              pubkey.count == 64, pubkey.allSatisfy(\.isHexDigit)
        else { throw AuthError.nip05NotFound(address) }
        let relays = ((root["relays"] as? [String: Any])?[pubkey] as? [String]) ?? []
        return Nip05Identity(pubkey: pubkey.lowercased(), relays: relays)
    }
}
