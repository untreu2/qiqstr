import Foundation

@MainActor
enum RecentSearchStore {
    private static let limit = 12

    private static var key: String { "search_recents_\(Session.shared.pubkey ?? "guest")" }

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    @discardableResult
    static func add(_ term: String) -> [String] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 120 else { return load() }
        var items = load().filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        items.insert(trimmed, at: 0)
        items = Array(items.prefix(limit))
        UserDefaults.standard.set(items, forKey: key)
        return items
    }

    @discardableResult
    static func remove(_ term: String) -> [String] {
        let items = load().filter { $0 != term }
        UserDefaults.standard.set(items, forKey: key)
        return items
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
