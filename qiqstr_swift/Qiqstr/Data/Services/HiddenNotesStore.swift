import Foundation

enum HiddenNotesStore {
    private static let limit = 2000

    static func ids(for pubkey: String?) -> Set<String> {
        guard let pubkey else { return [] }
        return Set(UserDefaults.standard.stringArray(forKey: key(pubkey)) ?? [])
    }

    static func add(_ id: String, for pubkey: String?) {
        guard let pubkey, !id.isEmpty else { return }
        var list = UserDefaults.standard.stringArray(forKey: key(pubkey)) ?? []
        guard !list.contains(id) else { return }
        list.append(id)
        UserDefaults.standard.set(Array(list.suffix(limit)), forKey: key(pubkey))
    }

    static func clear(for pubkey: String) {
        UserDefaults.standard.removeObject(forKey: key(pubkey))
    }

    private static func key(_ pubkey: String) -> String { "hidden_notes_\(pubkey)" }
}
