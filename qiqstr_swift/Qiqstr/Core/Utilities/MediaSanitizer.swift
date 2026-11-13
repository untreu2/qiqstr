import AVFoundation
import CoreTransferable
import UIKit
import UniformTypeIdentifiers

nonisolated enum MediaSanitizer {
    static func strippedVideo(_ data: Data, mime: String) async -> Data? {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent(mime == "video/mp4" ? "in.mp4" : "in.mov")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: input)
        } catch {
            return nil
        }
        return await strippedVideo(at: input, mime: mime)
    }

    static func strippedVideo(at input: URL, mime: String) async -> Data? {
        let isMP4 = mime == "video/mp4"
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let output = directory.appendingPathComponent(isMP4 ? "out.mp4" : "out.mov")
            guard let session = AVAssetExportSession(asset: AVURLAsset(url: input), presetName: AVAssetExportPresetPassthrough) else { return nil }
            session.metadata = []
            session.metadataItemFilter = .forSharing()
            try await session.export(to: output, as: isMP4 ? .mp4 : .mov)
            return try Data(contentsOf: output)
        } catch {
            return nil
        }
    }

    static func strippedImage(_ data: Data, mime: String) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        switch mime {
        case "image/png": return image.pngData()
        case "image/jpeg": return image.jpegData(compressionQuality: 0.9)
        default: return nil
        }
    }

    private static func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("media-\(UUID().uuidString)", isDirectory: true)
    }
}

nonisolated struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("picked-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let copy = directory.appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }

    var size: Int { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }

    func discard() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}

enum PlaybackAudio {
    static func prepare(muted: Bool) {
        let session = AVAudioSession.sharedInstance()
        if muted {
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        } else {
            try? session.setCategory(.playback, mode: .moviePlayback)
            try? session.setActive(true)
        }
    }

    static func release() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
