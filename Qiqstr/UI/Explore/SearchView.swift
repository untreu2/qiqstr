import SwiftUI
import QiqstrCore

@MainActor
@Observable
final class NoteSearchModel {
    private(set) var notes: [Note] = []
    private(set) var isSearching = false
    private var task: Task<Void, Never>?

    func search(_ text: String) {
        task?.cancel()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, !query.hasPrefix("npub1"), !query.hasPrefix("nprofile1") else {
            notes = []
            isSearching = false
            return
        }
        isSearching = true
        task = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let raw = try? await dbSearchNotes(query: query, limit: 40)
            let ids = JSON.array(raw).compactMap { $0.str("id") }
            let hydrated = ids.isEmpty ? [] : Note.list(try? await dbGetHydratedNotesByIds(eventIds: ids, mutedPubkeys: Session.shared.mutedPubkeys, mutedWords: Session.shared.mutedWords, currentUserPubkeyHex: Session.shared.pubkey))
            guard !Task.isCancelled else { return }
            notes = hydrated.sorted { $0.createdAt > $1.createdAt }
            isSearching = false
        }
    }
}

struct SearchView: View {
    @State private var people = UserSearchModel()
    @State private var notes = NoteSearchModel()

    private var query: String { people.trimmedQuery }

    private var hashtag: String? {
        let tag = query.hasPrefix("#") ? String(query.dropFirst()) : query
        guard !tag.isEmpty, tag.count <= 40, tag.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        return tag.lowercased()
    }

    var body: some View {
        List {
            if query.isEmpty {
                suggested
            } else {
                results
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
        .overlay { emptyOverlay }
        .navigationTitle(L("search"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $people.query, prompt: L("searchByNameOrNpub"))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) {
            if let pubkey = people.resolvedPubkey { Router.shared.push(.profile(pubkey)) }
        }
        .onChange(of: people.query) { notes.search(people.query) }
        .task { await people.loadSuggestions() }
        .accessibilityIdentifier("search-list")
    }

    @ViewBuilder
    private var suggested: some View {
        if !people.suggestions.isEmpty {
            Section(L("suggestedFollows")) {
                ForEach(people.suggestions.prefix(15)) { profile in
                    UserRowView(pubkey: profile.pubkey)
                }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if let pubkey = people.resolvedPubkey {
            Section {
                UserRowView(pubkey: pubkey)
            }
        }
        if let hashtag {
            Section {
                NavigationLink(value: Route.hashtag(hashtag)) {
                    Label("#\(hashtag)", systemImage: "number")
                        .font(.body.weight(.medium))
                }
                .accessibilityIdentifier("search-hashtag")
            }
        }
        if !people.results.isEmpty {
            Section {
                ForEach(people.results.prefix(5)) { profile in
                    UserRowView(pubkey: profile.pubkey)
                }
            } header: {
                HStack {
                    Text(L("users"))
                    Spacer()
                    if people.results.count > 5 {
                        NavigationLink(L("exploreSeeAll"), value: Route.userSearch)
                            .font(.subheadline)
                    }
                }
            }
        }
        if !notes.notes.isEmpty {
            Section(L("notes")) {
                ForEach(notes.notes, id: \.listId) { note in
                    NoteRowView(note: note)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if !query.isEmpty, hashtag == nil, people.resolvedPubkey == nil, people.results.isEmpty, notes.notes.isEmpty, !people.isSearching, !notes.isSearching {
            ContentUnavailableView.search(text: query)
        }
    }
}
