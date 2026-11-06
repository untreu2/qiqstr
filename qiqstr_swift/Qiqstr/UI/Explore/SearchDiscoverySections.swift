import SwiftUI

struct SearchDiscoverySections: View {
    let model: SearchViewModel

    var body: some View {
        if !model.recents.isEmpty { recentSection }
        if !model.trendingHashtags.isEmpty { hashtagSection }
        LiveNowSection()
        if !model.suggestions.isEmpty { peopleSection }
        trendingSection
    }

    private var recentSection: some View {
        Section {
            ForEach(model.recents.prefix(8), id: \.self) { term in
                Button { model.useRecent(term) } label: {
                    Label(term, systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .swipeActions {
                    Button(L("searchRemoveRecent"), systemImage: "trash", role: .destructive) { model.removeRecent(term) }
                }
                .listRowBackground(Color.clear)
            }
        } header: {
            HStack {
                Text(L("searchRecent")).font(.headline).foregroundStyle(.primary)
                Spacer()
                Button(L("searchClearRecent")) { model.clearRecents() }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("search-clear-recents")
            }
            .textCase(nil)
        }
        .accessibilityIdentifier("search-recents")
    }

    private var hashtagSection: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.trendingHashtags, id: \.self) { tag in
                        NavigationLink(value: Route.hashtag(tag)) {
                            Text(verbatim: "#\(tag)").font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .accessibilityIdentifier("search-trending-tag-\(tag)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } header: {
            SearchSectionHeader(title: L("searchTrendingHashtags"))
        }
    }

    private var peopleSection: some View {
        Section {
            ForEach(model.suggestions.prefix(5)) { profile in
                UserRowView(pubkey: profile.pubkey)
                    .listRowBackground(Color.clear)
            }
        } header: {
            SearchSectionHeader(title: L("searchSuggestedPeople")) { Router.shared.push(.userSearch) }
        }
        .accessibilityIdentifier("search-suggested-people")
    }

    @ViewBuilder
    private var trendingSection: some View {
        Section {
            if model.trendingNotes.isEmpty {
                if model.isLoadingTrending {
                    ForEach(0..<4, id: \.self) { index in
                        SearchNoteSkeletonRow(lines: index % 2 == 0 ? 3 : 2).searchNoteRow()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L("searchLoadingTrending"))
                } else if model.trendingFailed {
                    HStack {
                        SearchInlineMessage(text: L("searchTrendingUnavailable"))
                        Spacer()
                        Button(L("retry")) { Task { await model.loadTrending(force: true) } }
                            .font(.footnote)
                            .buttonStyle(.borderless)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(model.trendingNotes, id: \.listId) { note in
                    NoteRowView(note: note).searchNoteRow()
                }
            }
        } header: {
            SearchSectionHeader(title: L("searchTrendingNotes"))
        }
        .accessibilityIdentifier("search-trending-notes")
    }
}
