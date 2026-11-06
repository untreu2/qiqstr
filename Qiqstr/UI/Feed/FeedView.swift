import SwiftUI
import QiqstrCore

struct FeedView: View {
    @State private var notes: [Note] = []
    @State private var bus = DataBus.shared
    var body: some View {
        List(notes) { Text("\($0.authorName ?? "?"): \($0.content)").lineLimit(2) }
            .accessibilityIdentifier("feed-list")
            .task(id: bus.feedVersion) {
                guard let me = Session.shared.pubkey else { return }
                notes = Note.list(try? await dbGetHydratedFeedNotes(userPubkeyHex: me, authorsHex: nil, limit: 50, mutedPubkeys: [], mutedWords: [], filterReplies: true, currentUserPubkeyHex: me))
            }
    }
}
