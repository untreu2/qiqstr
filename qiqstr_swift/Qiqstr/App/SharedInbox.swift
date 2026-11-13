import Foundation
import Observation

nonisolated struct PendingShare: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
    let imageURLs: [URL]
    let createdAt: Date
}

@MainActor
@Observable
final class SharedInbox {
    static let shared = SharedInbox()
    static let appGroup = "group.me.untreu.qiqstrswift"
    static let prefillTextKey = "compose_prefill_text"
    static let prefillImagesKey = "compose_prefill_images"

    private(set) var pending: PendingShare?
    @ObservationIgnored private var delivered: Set<String> = []

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    private nonisolated struct Manifest: Decodable {
        let id: String
        let text: String
        let images: [String]
        let created: Date
    }

    private var rootURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup)?
            .appending(path: "SharedInbox", directoryHint: .isDirectory)
    }

    func check() {
        purgeStale()
        guard let share = allShares().max(by: { $0.createdAt < $1.createdAt }), !delivered.contains(share.id) else { return }
        present(share)
    }

    func handle(_ url: URL) {
        let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "share" }?.value
        guard let id else {
            Router.shared.compose(.newNote)
            return
        }
        guard !delivered.contains(id) else { return }
        if let share = load(id: id) {
            present(share)
        } else {
            Router.shared.compose(.newNote)
        }
    }

    func consume() {
        if let pending, let dir = directory(for: pending.id) {
            try? FileManager.default.removeItem(at: dir)
        }
        Self.defaults?.removeObject(forKey: Self.prefillTextKey)
        Self.defaults?.removeObject(forKey: Self.prefillImagesKey)
        pending = nil
    }

    private func present(_ share: PendingShare) {
        delivered.insert(share.id)
        guard Session.shared.canSign else {
            if let dir = directory(for: share.id) { try? FileManager.default.removeItem(at: dir) }
            ReadOnlyGate.shared.present()
            return
        }
        pending = share
        Self.defaults?.set(share.text, forKey: Self.prefillTextKey)
        Self.defaults?.set(share.imageURLs.map(\.path), forKey: Self.prefillImagesKey)
        Router.shared.compose(.newNote)
    }

    private func directory(for id: String) -> URL? {
        guard !id.contains("/"), !id.contains("..") else { return nil }
        return rootURL?.appending(path: id, directoryHint: .isDirectory)
    }

    private func load(id: String) -> PendingShare? {
        guard let dir = directory(for: id),
              let data = try? Data(contentsOf: dir.appending(path: "manifest.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }
        let images = manifest.images
            .map { dir.appending(path: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        return PendingShare(id: manifest.id, text: manifest.text, imageURLs: images, createdAt: manifest.created)
    }

    private func allShares() -> [PendingShare] {
        guard let rootURL, let names = try? FileManager.default.contentsOfDirectory(atPath: rootURL.path) else { return [] }
        return names.compactMap(load(id:))
    }

    private func purgeStale() {
        guard let rootURL,
              let dirs = try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let now = Date()
        for dir in dirs {
            let created = (try? dir.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now
            let hasManifest = FileManager.default.fileExists(atPath: dir.appending(path: "manifest.json").path)
            let limit: TimeInterval = hasManifest ? 7 * 86_400 : 3_600
            if now.timeIntervalSince(created) > limit, dir.lastPathComponent != pending?.id {
                try? FileManager.default.removeItem(at: dir)
            }
        }
    }
}
