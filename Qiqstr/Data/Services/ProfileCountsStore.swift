import Foundation

struct ProfileCounts: Codable, Equatable, Sendable {
    var following: Int?
    var followers: Int?
}

@MainActor
final class ProfileCountsStore {
    static let shared = ProfileCountsStore()

    private static let storageKey = "profile_counts_cache_v1"
    private static let capacity = 400

    private var entries: [String: ProfileCounts]
    private var order: [String]
    private var saveTask: Task<Void, Never>?

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            entries = stored.entries
            order = stored.order.filter { stored.entries[$0] != nil }
        } else {
            entries = [:]
            order = []
        }
    }

    func counts(for pubkey: String) -> ProfileCounts? { entries[pubkey] }

    func update(_ pubkey: String, following: Int? = nil, followers: Int? = nil) {
        var current = entries[pubkey] ?? ProfileCounts()
        if let following { current.following = following }
        if let followers { current.followers = followers }
        guard current != entries[pubkey] else { return }
        entries[pubkey] = current
        order.removeAll { $0 == pubkey }
        order.append(pubkey)
        if order.count > Self.capacity {
            for key in order.prefix(order.count - Self.capacity) { entries.removeValue(forKey: key) }
            order.removeFirst(order.count - Self.capacity)
        }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            let stored = Stored(entries: self.entries, order: self.order)
            if let data = try? JSONEncoder().encode(stored) {
                UserDefaults.standard.set(data, forKey: Self.storageKey)
            }
        }
    }

    private struct Stored: Codable {
        var entries: [String: ProfileCounts]
        var order: [String]
    }
}
