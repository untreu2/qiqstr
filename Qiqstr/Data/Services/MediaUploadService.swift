import Foundation
import QiqstrCore

struct UploadedMedia: Hashable, Sendable {
    var url: String
    var sha256: String
    var mimeType: String
    var size: Int
}

@MainActor
final class MediaUploadService {
    static let shared = MediaUploadService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    func upload(data: Data, mimeType: String) async throws -> String {
        try await uploadMedia(data: data, mimeType: mimeType).url
    }

    func uploadMedia(data: Data, mimeType: String, server: String? = nil) async throws -> UploadedMedia {
        let server = server ?? RelayConfig.blossomServer
        let key = try Session.shared.requireSigner()
        let hash = await Task.detached { sha256Hash(data: data) }.value
        let expiration = Int64(TimeFormat.now + 600)
        let auth = try createBlossomAuthEvent(content: "Upload \(hash)", sha256Hash: hash, expiration: expiration, privateKeyHex: key)
        let token = Data(auth.utf8).base64EncodedString()
        let base = server.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard let url = URL(string: "\(base)/upload") else { throw CoreError(L("mediaUploadFailed")) }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Nostr \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        let (body, response) = try await session.upload(for: request, from: data)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let reason = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Reason") ?? String(decoding: body.prefix(200), as: UTF8.self)
            throw CoreError("\(L("mediaUploadFailed")) (\(status)) \(reason)".trimmingCharacters(in: .whitespaces))
        }
        let json = (try? JSONSerialization.jsonObject(with: body)) as? JSONObject ?? [:]
        let sha = json.str("sha256") ?? hash
        guard let remote = json.str("url") ?? (sha.isEmpty ? nil : "\(base)/\(sha)") else { throw CoreError(L("mediaUploadFailed")) }
        return UploadedMedia(url: remote, sha256: sha, mimeType: json.str("type") ?? mimeType, size: json.int("size") == 0 ? data.count : json.int("size"))
    }
}
