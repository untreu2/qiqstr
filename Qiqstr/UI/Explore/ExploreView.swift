import SwiftUI

struct ExploreView: View {
    @State private var model = ExploreViewModel()
    @State private var bus = DataBus.shared
    @State private var started = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if model.trimmedQuery.isEmpty {
                    header
                } else {
                    usersSection
                    if !model.visibleArticles.isEmpty {
                        SectionHeader(title: L("articles")).padding(.horizontal, 4).padding(.top, 6)
                    }
                }
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(AppColors.background)
        .accessibilityIdentifier("explore-list")
        .navigationTitle(L("reads"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: L("exploreSearchPrompt"))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .refreshable { await model.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.userSearch) { Image(systemName: "person.2") }
                    .accessibilityLabel(L("users"))
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(L("reads"), selection: $model.scope) {
                ForEach(ExploreScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("explore-scope-picker")
            Text(model.scope == .following ? L("readsSubtitle") : L("exploreGlobalSubtitle"))
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 4)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var usersSection: some View {
        let users = model.users
        if !users.results.isEmpty || users.isSearching {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    SectionHeader(title: L("users"))
                    if users.isSearching { ProgressView().controlSize(.mini) }
                    Spacer()
                    NavigationLink(value: Route.userSearch) {
                        Text(L("exploreSeeAll")).font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityIdentifier("explore-users-see-all")
                }
                .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(users.results) { profile in
                        NavigationLink(value: Route.profile(profile.pubkey)) {
                            ExploreUserRow(profile: profile)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { ExploreUserMenu(pubkey: profile.pubkey) }
                        if profile.id != users.results.last?.id {
                            Divider().padding(.leading, 70)
                        }
                    }
                }
                .background(AppColors.inputFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .accessibilityIdentifier("explore-users-section")
        }
    }

    @ViewBuilder
    private var content: some View {
        let articles = model.visibleArticles
        if model.isLoading, articles.isEmpty {
            VStack(spacing: 14) {
                ProgressView()
                Text(L("loadingArticles")).font(.system(size: 14)).foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        } else if articles.isEmpty {
            if model.trimmedQuery.isEmpty {
                EmptyStateView(
                    systemImage: "doc.richtext",
                    title: L("noArticlesYet"),
                    message: model.scope == .following ? L("longFormContentDescription") : nil,
                    actionTitle: L("retry")
                ) { Task { await model.refresh() } }
                .padding(.top, 40)
            } else if model.users.results.isEmpty, !model.users.isSearching {
                EmptyStateView(systemImage: "magnifyingglass", title: L("noResultsFound"), message: L("trySearchingDifferentTerm"))
                    .padding(.top, 40)
            }
        } else {
            ForEach(articles) { article in
                ArticleCardView(article: article)
                    .onAppear {
                        if article.id == articles.last?.id { Task { await model.loadMore() } }
                    }
            }
            if model.isLoadingMore {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
            }
        }
    }
}
