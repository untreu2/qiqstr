import SwiftUI

struct ExploreView: View {
    @State private var model = ExploreViewModel()
    @State private var bus = DataBus.shared
    @State private var started = false

    var body: some View {
        List {
            if !model.trimmedQuery.isEmpty {
                usersSection
            }
            articlesSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .scrollDismissesKeyboard(.immediately)
        .accessibilityIdentifier("explore-list")
        .overlay { emptyState }
        .navigationTitle(L("reads"))
        .navigationSubtitle(model.scope == .following ? L("readsSubtitle") : L("exploreGlobalSubtitle"))
        .navigationBarTitleDisplayMode(.large)
        .toolbarTitleMenu {
            Picker(L("reads"), selection: $model.scope) {
                ForEach(ExploreScope.allCases) { scope in
                    Label(scope.title, systemImage: scope == .following ? "person.2" : "globe").tag(scope)
                }
            }
            .accessibilityIdentifier("explore-scope-picker")
        }
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: L("exploreSearchPrompt"))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .refreshable { await model.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.userSearch) { Label(L("users"), systemImage: "person.2") }
                    .accessibilityIdentifier("explore-user-search")
            }
        }
        .sensoryFeedback(.selection, trigger: model.scope)
        .task {
            guard !started else { return }
            started = true
            await model.start()
        }
        .task(id: bus.feedVersion) {
            guard started else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await model.reload()
        }
    }

    @ViewBuilder
    private var usersSection: some View {
        let users = model.users
        if !users.results.isEmpty || users.isSearching {
            Section {
                ForEach(users.results) { profile in
                    NavigationLink(value: Route.profile(profile.pubkey)) {
                        ExploreUserRow(profile: profile)
                    }
                    .listRowBackground(Color.clear)
                    .contextMenu { ExploreUserMenu(pubkey: profile.pubkey) }
                }
            } header: {
                HStack(spacing: 8) {
                    Text(L("users")).font(.headline).foregroundStyle(.primary)
                    if users.isSearching { ProgressView().controlSize(.small) }
                    Spacer()
                    Button(L("exploreSeeAll")) { Router.shared.push(.userSearch) }
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("explore-users-see-all")
                }
                .textCase(nil)
            }
            .accessibilityIdentifier("explore-users-section")
        }
    }

    @ViewBuilder
    private var articlesSection: some View {
        let articles = model.visibleArticles
        if model.isLoading, articles.isEmpty {
            ForEach(0..<3, id: \.self) { _ in
                ArticleCardSkeleton().articleRow()
            }
            .accessibilityLabel(L("loadingArticles"))
        } else if !articles.isEmpty {
            Section {
                ForEach(articles) { article in
                    ArticleCardView(article: article)
                        .articleRow()
                        .onAppear {
                            if article.id == articles.last?.id { Task { await model.loadMore() } }
                        }
                }
                if model.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            } header: {
                if !model.trimmedQuery.isEmpty {
                    Text(L("articles")).font(.headline).foregroundStyle(.primary).textCase(nil)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.isLoading, model.visibleArticles.isEmpty {
            if model.trimmedQuery.isEmpty {
                EmptyStateView(
                    systemImage: "doc.richtext",
                    title: L("noArticlesYet"),
                    message: model.scope == .following ? L("longFormContentDescription") : nil,
                    actionTitle: L("retry")
                ) { Task { await model.refresh() } }
            } else if model.users.results.isEmpty, !model.users.isSearching {
                EmptyStateView(systemImage: "magnifyingglass", title: L("noResultsFound"), message: L("trySearchingDifferentTerm"))
            }
        }
    }
}

private extension View {
    func articleRow() -> some View {
        listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
