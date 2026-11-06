import SwiftUI
import QiqstrCore

@MainActor
@Observable
final class NotificationNoteStore {
    static let shared = NotificationNoteStore()
    private(set) var notes: [String: Note] = [:]
    private var missing: Set<String> = []
    private var inflight: Set<String> = []

    func note(_ id: String) -> Note? { notes[id] }
    func isMissing(_ id: String) -> Bool { missing.contains(id) }

    func load(_ id: String) async {
        guard notes[id] == nil, !inflight.contains(id) else { return }
        inflight.insert(id)
        defer { inflight.remove(id) }
        if let note = await fetchLocal(id) {
            store(note)
            return
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await SyncService.shared.syncNote(id) }
            group.addTask { try? await Task.sleep(for: .seconds(6)) }
            await group.next()
            group.cancelAll()
        }
        if let note = await fetchLocal(id) { store(note) } else { missing.insert(id) }
    }

    func reset() {
        notes.removeAll()
        missing.removeAll()
    }

    private func store(_ note: Note) {
        notes[note.id] = note
        missing.remove(note.id)
        if ProfileCache.shared.profile(note.pubkey) == nil {
            Task { await ProfileCache.shared.load([note.pubkey]) }
        }
    }

    private func fetchLocal(_ id: String) async -> Note? {
        guard let raw = try? await dbGetHydratedNote(eventId: id, currentUserPubkeyHex: Session.shared.pubkey),
              let obj = JSON.object(raw) else { return nil }
        let note = Note(json: obj)
        return note.id.isEmpty ? nil : note
    }
}

enum NotificationText {
    static func readable(_ content: String) -> String {
        var text = content
        let pattern = "nostr:(npub1|nprofile1|note1|nevent1|naddr1)[0-9a-z]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return content }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed()
        for match in matches {
            let token = ns.substring(with: match.range)
            let bech = String(token.dropFirst(6))
            var replacement = ""
            if bech.hasPrefix("npub1") || bech.hasPrefix("nprofile1") {
                if let hex = Nip19.pubkeyHex(from: bech) {
                    replacement = "@" + (ProfileCache.shared.profile(hex)?.bestName ?? Profile.shortNpub(hex))
                }
            }
            text = (text as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct NotificationNotePreview: View {
    let noteId: String
    @State private var store = NotificationNoteStore.shared
    @State private var cache = ProfileCache.shared

    var body: some View {
        if !store.isMissing(noteId) { card }
    }

    private var card: some View {
        Group {
            if let note = store.note(noteId) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ProfileAvatar(pubkey: note.pubkey, size: 18, fallbackURL: note.authorImage)
                        Text(cache.profile(note.pubkey)?.bestName ?? note.authorName ?? Profile.shortNpub(note.pubkey))
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                        Text(TimeFormat.relative(note.createdAt))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    let text = NotificationText.readable(note.content)
                    if !text.isEmpty {
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Circle().fill(AppColors.overlayLight).frame(width: 18, height: 18)
                    RoundedRectangle(cornerRadius: 4).fill(AppColors.overlayLight).frame(width: 140, height: 10)
                }
                .redacted(reason: .placeholder)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.overlayLight.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task(id: noteId) { await store.load(noteId) }
    }
}
