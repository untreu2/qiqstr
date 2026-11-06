import SwiftUI

struct SearchResultSections: View {
    @Bindable var model: SearchViewModel

    var body: some View {
        if let hex = model.resolvedHex {
            resolvedSection(hex)
        } else {
            switch model.scope {
            case .top: topSections
            case .people: peopleSection(limit: SearchViewModel.peopleLimit, header: false)
            case .notes: notesSection(limit: SearchViewModel.notesLimit, header: false)
            case .hashtags: hashtagSection(limit: 30, header: false)
            case .articles: articlesSection(limit: SearchViewModel.articlesLimit, header: false)
            }
            if model.remoteFailed { SearchInlineMessage(text: L("searchRelaysUnavailable")) }
        }
    }

    @ViewBuilder
    private var topSections: some View {
        peopleSection(limit: 3, header: true)
        hashtagSection(limit: 3, header: true)
        articlesSection(limit: 2, header: true)
        notesSection(limit: 20, header: true)
    }

    private func resolvedSection(_ hex: String) -> some View {
        Section {
            NavigationLink(value: Route.profile(hex)) {
                Label(L("exploreOpenProfile"), systemImage: "person.crop.circle")
            }
            .accessibilityIdentifier("search-open-profile")
            NavigationLink(value: Route.thread(hex)) {
                Label(L("searchOpenNote"), systemImage: "text.bubble")
            }
            .accessibilityIdentifier("search-open-note")
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func peopleSection(limit: Int, header: Bool) -> some View {
        let loading = model.pending.contains(.people) || model.isSearchingLocal
        if !model.people.isEmpty || loading {
            Section {
                if model.people.isEmpty {
                    ForEach(0..<(header ? 2 : 5), id: \.self) { _ in SearchPersonSkeletonRow() }
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(model.people.prefix(limit)) { profile in
                        UserRowView(pubkey: profile.pubkey)
                            .simultaneousGesture(TapGesture().onEnded { model.remember() })
                            .listRowBackground(Color.clear)
                    }
                }
            } header: {
                if header {
                    SearchSectionHeader(title: L("searchScopePeople"), isLoading: loading && !model.people.isEmpty, seeAll: seeAll(.people, count: model.people.count, limit: limit))
                } else if loading, !model.people.isEmpty {
                    searchingHeader
                }
            }
            .accessibilityIdentifier("search-people-section")
        }
    }

    @ViewBuilder
    private func hashtagSection(limit: Int, header: Bool) -> some View {
        let matches = model.hashtags
        if !matches.isEmpty {
            Section {
                ForEach(matches.prefix(limit)) { match in
                    NavigationLink(value: Route.hashtag(match.tag)) {
                        LabeledContent {
                            if match.count > 0 { Text(match.count, format: .number) }
                        } label: {
                            Label {
                                Text(verbatim: "#\(match.tag)").foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "number")
                            }
                        }
                    }
                    .simultaneousGesture(TapGesture().onEnded { model.remember() })
                    .accessibilityIdentifier(match.tag == model.queryHashtag ? "search-hashtag" : "search-hashtag-\(match.tag)")
                }
                .listRowBackground(Color.clear)
            } header: {
                if header {
                    SearchSectionHeader(title: L("searchScopeHashtags"), seeAll: seeAll(.hashtags, count: matches.count, limit: limit))
                }
            }
        }
    }

    @ViewBuilder
    private func articlesSection(limit: Int, header: Bool) -> some View {
        let loading = model.pending.contains(.articles) || model.isSearchingLocal
        if !model.articles.isEmpty || (loading && !header) {
            Section {
                if model.articles.isEmpty {
                    ForEach(0..<2, id: \.self) { _ in ArticleCardSkeleton().searchArticleRow() }
                } else {
                    ForEach(model.articles.prefix(limit)) { article in
                        ArticleCardView(article: article)
                            .simultaneousGesture(TapGesture().onEnded { model.remember() })
                            .searchArticleRow()
                    }
                }
            } header: {
                if header {
                    SearchSectionHeader(title: L("searchScopeArticles"), isLoading: loading, seeAll: seeAll(.articles, count: model.articles.count, limit: limit))
                } else if loading, !model.articles.isEmpty {
                    searchingHeader
                }
            }
            .accessibilityIdentifier("search-articles-section")
        }
    }

    @ViewBuilder
    private func notesSection(limit: Int, header: Bool) -> some View {
        let loading = model.pending.contains(.notes) || model.isSearchingLocal
        if !model.notes.isEmpty || loading {
            Section {
                if model.notes.isEmpty {
                    ForEach(0..<3, id: \.self) { index in
                        SearchNoteSkeletonRow(lines: index == 1 ? 3 : 2).searchNoteRow()
                    }
                } else {
                    ForEach(model.notes.prefix(limit), id: \.listId) { note in
                        NoteRowView(note: note)
                            .simultaneousGesture(TapGesture().onEnded { model.remember() })
                            .searchNoteRow()
                    }
                }
            } header: {
                if header {
                    SearchSectionHeader(title: L("searchScopeNotes"), isLoading: loading && !model.notes.isEmpty, seeAll: seeAll(.notes, count: model.notes.count, limit: limit))
                } else if loading, !model.notes.isEmpty {
                    searchingHeader
                }
            }
            .accessibilityIdentifier("search-notes-section")
        }
    }

    private var searchingHeader: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(L("searchSearchingRelays")).font(.footnote).foregroundStyle(.secondary)
        }
        .textCase(nil)
    }

    private func seeAll(_ scope: SearchScope, count: Int, limit: Int) -> (() -> Void)? {
        guard count > limit else { return nil }
        return { model.scope = scope }
    }
}
