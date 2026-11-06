import Foundation

@MainActor
final class MediaUploadService {
    static let shared = MediaUploadService()

    func upload(data: Data, mimeType: String) async throws -> String { "" }
}
