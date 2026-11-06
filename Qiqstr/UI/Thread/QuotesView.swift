import SwiftUI

@MainActor
@Observable
final class QuotesViewModel {
    let noteId: String
    private(set) var quotes: [Note] = []
    private(set) var isLoading = true

    init(noteId: String) { self.noteId = noteId }

    func load() async {
        await reloadLocal()
        await NoteRepository.fetchQuotesFromRelays(noteId)
        await reloadLocal()
        isLoading = false
    }

    func reloadLocal() async {
        let muted = Set(Session.shared.mutedPubkeys)
        let deleted = NoteInteractionStore.shared.deletedIds
        let result = await NoteRepository.quotes(noteId).filter { !muted.contains($0.pubkey) && !deleted.contains($0.id) }
        quotes = result
        if !result.isEmpty { isLoading = false }
        NoteInteractionStore.shared.seed(result)
        NoteInteractionStore.shared.requestCounts(result.map(\.id))
        await NoteContentCache.warm(result)
        await ProfileCache.shared.load(Array(Set(result.map(\.pubkey))).filter { ProfileCache.shared.profile($0) == nil })
    }
}

struct QuotesView: View {
    let noteId: String
    @State private var model: QuotesViewModel
    @State private var bus = DataBus.shared

    init(noteId: String) {
        self.noteId = noteId
        _model = State(initialValue: QuotesViewModel(noteId: noteId))
    }

    var body: some View {
        NoteList(notes: model.quotes)
            .accessibilityIdentifier("quotes-list")
            .refreshable { await model.load() }
            .overlay {
                if model.quotes.isEmpty {
                    if model.isLoading {
                        LoadingView()
                    } else {
                        EmptyStateView(systemImage: "quote.bubble", title: L("noQuotesFound"))
                            .accessibilityIdentifier("quotes-empty")
                    }
                }
            }
            .navigationTitle(L("quotes"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.load() }
            .task(id: bus.feedVersion) { if bus.feedVersion > 0 { await model.reloadLocal() } }
    }
}
