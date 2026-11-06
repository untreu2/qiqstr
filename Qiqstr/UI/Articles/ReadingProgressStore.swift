import Foundation
import Observation

struct ReadingProgressEntry: Codable, Hashable, Identifiable {
    var key: String
    var articleId: String
    var naddr: String?
    var title: String
    var image: String?
    var authorPubkey: String
    var authorName: String?
    var minutes: Int
    var progress: Double
    var updatedAt: Date

    var id: String { key }
    var minutesLeft: Int { max(1, Int((Double(minutes) * (1 - progress)).rounded(.up))) }
    var isInProgress: Bool { progress >= ReadingProgressStore.startThreshold && progress < ReadingProgressStore.finishThreshold }
}

@MainActor
@Observable
final class ReadingProgressStore {
    static let shared = ReadingProgressStore()
    static let startThreshold = 0.03
    static let finishThreshold = 0.97
    private static let maxEntries = 40

    private(set) var version = 0
    @ObservationIgnored private var account: String?
    @ObservationIgnored private var entries: [String: ReadingProgressEntry] = [:]
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var lastPersist = Date.distantPast

    func continueReading(limit: Int = 3) -> [ReadingProgressEntry] {
        _ = version
        return Array(current().values.filter(\.isInProgress).sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }

    func progress(for article: Article) -> Double? {
        current()[article.progressKey]?.progress
    }

    func record(_ article: Article, progress: Double) {
        guard Session.shared.pubkey != nil else { return }
        var all = current()
        let clamped = min(max(progress, 0), 1)
        if let existing = all[article.progressKey], abs(existing.progress - clamped) < 0.005 { return }
        all[article.progressKey] = ReadingProgressEntry(
            key: article.progressKey,
            articleId: article.id,
            naddr: article.naddr,
            title: article.displayTitle,
            image: article.image?.nilIfEmpty,
            authorPubkey: article.pubkey,
            authorName: article.authorName?.nilIfEmpty,
            minutes: article.readingMinutes,
            progress: clamped,
            updatedAt: Date()
        )
        entries = all
        dirty = true
        if Date().timeIntervalSince(lastPersist) > 4 { persist() }
    }

    func remove(_ entry: ReadingProgressEntry) {
        var all = current()
        all.removeValue(forKey: entry.key)
        entries = all
        dirty = true
        persist()
    }

    func persist() {
        guard dirty else { return }
        write()
        version += 1
    }

    private func write() {
        guard let account else { return }
        let trimmed = entries.values.sorted { $0.updatedAt > $1.updatedAt }.prefix(Self.maxEntries)
        entries = Dictionary(uniqueKeysWithValues: trimmed.map { ($0.key, $0) })
        if let data = try? JSONEncoder().encode(Array(trimmed)) {
            UserDefaults.standard.set(data, forKey: Self.storageKey(account))
        }
        dirty = false
        lastPersist = Date()
    }

    private func current() -> [String: ReadingProgressEntry] {
        let active = Session.shared.pubkey
        guard active != account else { return entries }
        if dirty { write() }
        account = active
        dirty = false
        guard let active, let data = UserDefaults.standard.data(forKey: Self.storageKey(active)),
              let list = try? JSONDecoder().decode([ReadingProgressEntry].self, from: data) else {
            entries = [:]
            return entries
        }
        entries = Dictionary(list.map { ($0.key, $0) }, uniquingKeysWith: { $0.updatedAt > $1.updatedAt ? $0 : $1 })
        return entries
    }

    private static func storageKey(_ account: String) -> String { "reading_progress_\(account)" }
}

extension Article {
    var progressKey: String { "\(pubkey):\(dTag.isEmpty ? id : dTag)" }
}
