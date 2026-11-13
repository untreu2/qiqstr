import SwiftUI

struct SearchView: View {
    @State private var model = SearchViewModel()
    @State private var explore = ExploreService.shared
    @State private var section: ExploreSection = .forYou
    @State private var mediaSelection: ProfileMediaSelection?

    var body: some View {
        content
            .background(AppColors.background)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(L("feedExplore"))
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: L("searchPrompt"))
            .searchScopes($model.scope, activation: .onSearchPresentation) {
                ForEach(SearchScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .searchSuggestions { recentSuggestions }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit(of: .search) { model.submit() }
            .sensoryFeedback(.selection, trigger: model.scope)
            .sensoryFeedback(.impact(weight: .light), trigger: model.opened)
            .task { await model.start() }
            .task { await LiveNowSectionModel.load() }
            .task {
                FollowPackService.shared.prefetch()
                await explore.loadAll()
            }
            .fullScreenCover(item: $mediaSelection) { selection in
                ProfileMediaPager(entries: explore.visibleMedia, startIndex: selection.index)
            }
            .accessibilityIdentifier("search-list")
    }

    @ViewBuilder
    private var content: some View {
        if model.trimmedQuery.isEmpty {
            hub
                .safeAreaBar(edge: .top) { ExploreChipBar(selection: $section) }
        } else {
            List { SearchResultSections(model: model) }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay { emptyOverlay }
        }
    }

    @ViewBuilder
    private var hub: some View {
        if section == .media {
            ExploreMediaGrid { mediaSelection = ProfileMediaSelection(index: $0) }
                .refreshable { await explore.loadMedia(force: true) }
        } else {
            List {
                ExploreHubSections(section: section, model: model, onSelect: { section = $0 }) {
                    mediaSelection = ProfileMediaSelection(index: $0)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await refresh() }
            .id(section)
        }
    }

    @ViewBuilder
    private var recentSuggestions: some View {
        if model.trimmedQuery.isEmpty, !model.recents.isEmpty {
            Section(L("searchRecent")) {
                ForEach(model.recents.prefix(8), id: \.self) { term in
                    Label(term, systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.primary)
                        .searchCompletion(term)
                }
                Button(L("searchClearRecent"), role: .destructive) { model.clearRecents() }
                    .accessibilityIdentifier("search-clear-recents")
            }
        }
    }

    private func refresh() async {
        switch section {
        case .forYou:
            async let live: Void = LiveNowSectionModel.load(force: true)
            async let search: Void = model.refresh()
            async let all: Void = explore.loadAll(force: true)
            _ = await (live, search, all)
        case .feeds: await explore.loadFeeds(force: true)
        case .people:
            async let people: Void = explore.loadPeople(force: true)
            async let packs: Void = FollowPackService.shared.reload()
            _ = await (people, packs)
        case .zaps: await explore.loadZaps(force: true)
        case .topics: await explore.loadTopics(force: true)
        case .media: await explore.loadMedia(force: true)
        }
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if model.showsEmptyResults {
            ContentUnavailableView.search(text: model.trimmedQuery)
        }
    }
}

struct SearchSectionHeader: View {
    let title: String
    var isLoading = false
    var seeAll: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.headline).foregroundStyle(.primary)
            if isLoading { ProgressView().controlSize(.small) }
            Spacer()
            if let seeAll {
                Button(L("exploreSeeAll"), action: seeAll)
                    .font(.subheadline)
                    .buttonStyle(.borderless)
            }
        }
        .textCase(nil)
    }
}

struct SearchPersonSkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(.quaternary).frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Placeholder name").font(.body.weight(.semibold))
                Text(verbatim: "name@example.com").font(.subheadline)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

struct SearchNoteSkeletonRow: View {
    var lines = 2

    var body: some View {
        FeedSkeletonRow(lines: lines)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
    }
}

struct SearchInlineMessage: View {
    let text: String
    var systemImage = "wifi.slash"

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

extension View {
    func searchNoteRow() -> some View {
        listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
    }

    func searchArticleRow() -> some View {
        listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
