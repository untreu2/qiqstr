import Foundation
import Observation

nonisolated struct ScheduledPost: Codable, Identifiable, Hashable, Sendable {
    var draft: ComposeDraft
    var publishAt: Date
    var lastError: String?

    var id: String { draft.id }
}

@MainActor
@Observable
final class ScheduledPostService {
    static let shared = ScheduledPostService()

    private(set) var posts: [ScheduledPost] = []
    @ObservationIgnored private var owner: String?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var publishing = false
    @ObservationIgnored private var pendingEdit: ScheduledPost?

    static func hasPending(for pubkey: String?) -> Bool {
        guard let pubkey, let url = fileURL(pubkey) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    var nextDue: Date? { all().map(\.publishAt).min() }

    func all() -> [ScheduledPost] {
        ensureLoaded()
        return posts
    }

    func reset() {
        timer?.cancel()
        timer = nil
        owner = nil
        posts = []
        pendingEdit = nil
    }

    func start() {
        ensureLoaded()
        restartTimer()
        Task { await publishDue() }
    }

    func schedule(_ draft: ComposeDraft, at date: Date) {
        ensureLoaded()
        posts.removeAll { $0.id == draft.id }
        posts.append(ScheduledPost(draft: draft, publishAt: date))
        posts.sort { $0.publishAt < $1.publishAt }
        persist()
        restartTimer()
        BackgroundRefresh.schedule()
    }

    func cancel(_ id: String) {
        ensureLoaded()
        guard posts.contains(where: { $0.id == id }) else { return }
        posts.removeAll { $0.id == id }
        persist()
        restartTimer()
    }

    func contains(_ id: String) -> Bool {
        all().contains { $0.id == id }
    }

    func edit(_ post: ScheduledPost) {
        pendingEdit = post
    }

    func takePendingEdit() -> ScheduledPost? {
        defer { pendingEdit = nil }
        return pendingEdit
    }

    func publishDue() async {
        ensureLoaded()
        guard !publishing, Session.shared.phase == .ready, Session.shared.canSign, Session.shared.pubkey == owner else { return }
        publishing = true
        defer { publishing = false }
        let due = posts.filter { $0.publishAt <= Date() }
        guard !due.isEmpty, await SyncService.shared.hasConnectedRelays() else { return }
        for post in due {
            do {
                try await ComposePublisher.publish(post.draft)
                posts.removeAll { $0.id == post.id }
                ToastCenter.shared.show(L("feedScheduledPosted"), style: .success)
            } catch {
                if let index = posts.firstIndex(where: { $0.id == post.id }) { posts[index].lastError = coreMessage(error) }
            }
            persist()
        }
        restartTimer()
    }

    private func restartTimer() {
        timer?.cancel()
        guard let next = posts.map(\.publishAt).min() else { return }
        let delay = max(1, next.timeIntervalSinceNow)
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.publishDue()
            guard !Task.isCancelled, let self, self.posts.contains(where: { $0.publishAt <= Date() }) else { return }
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            self.restartTimer()
        }
    }

    private func ensureLoaded() {
        let pubkey = Session.shared.pubkey
        guard pubkey != owner else { return }
        owner = pubkey
        posts = pubkey.flatMap(Self.read) ?? []
    }

    private func persist() {
        guard let owner, let url = Self.fileURL(owner) else { return }
        if posts.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(posts) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func read(_ owner: String) -> [ScheduledPost]? {
        guard let url = fileURL(owner), let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode([ScheduledPost].self, from: data))?.sorted { $0.publishAt < $1.publishAt }
    }

    private static func fileURL(_ owner: String) -> URL? {
        guard owner.count == 64, owner.allSatisfy(\.isHexDigit) else { return nil }
        return AppDirectories.support.appendingPathComponent("Scheduled", isDirectory: true).appendingPathComponent("\(owner).json")
    }
}
