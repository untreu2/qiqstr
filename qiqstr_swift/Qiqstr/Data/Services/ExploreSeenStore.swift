import Foundation

@MainActor
final class ExploreSeenStore {
    static let shared = ExploreSeenStore()
    private static let maxAge: TimeInterval = 7 * 86_400
    private static let capacity = 3000

    private var owner: String?
    private var seen: [String: Double] = [:]
    private var saveTask: Task<Void, Never>?

    func snapshot() -> [String: Double] {
        load()
        return seen
    }

    func mark(_ id: String) {
        load()
        guard !id.isEmpty, seen[id] == nil else { return }
        seen[id] = Date().timeIntervalSince1970
        scheduleSave()
    }

    private func key(_ pubkey: String) -> String { "explore_seen_\(pubkey)" }

    private func load() {
        let me = Session.shared.pubkey
        guard owner != me else { return }
        saveTask?.cancel()
        owner = me
        guard let me else { seen = [:]; return }
        let stored = (UserDefaults.standard.dictionary(forKey: key(me)) as? [String: Double]) ?? [:]
        seen = Self.pruned(stored)
    }

    private func scheduleSave() {
        guard let owner else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled, self.owner == owner else { return }
            self.seen = Self.pruned(self.seen)
            UserDefaults.standard.set(self.seen, forKey: self.key(owner))
        }
    }

    private static func pruned(_ entries: [String: Double]) -> [String: Double] {
        let cutoff = Date().timeIntervalSince1970 - maxAge
        var fresh = entries.filter { $0.value >= cutoff }
        if fresh.count > capacity {
            let keep = fresh.sorted { $0.value > $1.value }.prefix(capacity)
            fresh = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        return fresh
    }
}
