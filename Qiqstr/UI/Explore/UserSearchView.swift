import SwiftUI

struct UserSearchView: View {
    @State private var model = UserSearchModel()
    @State private var opened = 0

    var body: some View {
        List {
            if model.trimmedQuery.isEmpty {
                suggestionsSection
            } else {
                resultsSection
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .scrollDismissesKeyboard(.immediately)
        .accessibilityIdentifier("user-search-list")
        .overlay { overlay }
        .navigationTitle(L("users"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: L("searchByNameOrNpub"))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) { openResolved() }
        .onChange(of: model.query) { old, new in
            if new.count - old.count > 20 { openResolved() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { paste() } label: { Image(systemName: "doc.on.clipboard") }
                    .accessibilityLabel(L("explorePaste"))
                    .accessibilityIdentifier("user-search-paste")
            }
        }
        .sensoryFeedback(.selection, trigger: opened)
        .task { await model.loadSuggestions() }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        Section {
            Text(L("exploreSearchHint"))
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        if !model.suggestions.isEmpty {
            Section {
                ForEach(model.suggestions) { profile in row(profile) }
            } header: {
                SectionHeader(title: L("exploreSuggested"))
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if let pubkey = model.resolvedPubkey {
            Section {
                NavigationLink(value: Route.profile(pubkey)) {
                    Label(L("exploreOpenProfile"), systemImage: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                }
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("user-search-open-resolved")
            }
        }
        Section {
            ForEach(model.results) { profile in row(profile) }
            if model.isSearching, !model.results.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L("searchingForUsers")).font(.system(size: 14)).foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
    }

    private func row(_ profile: Profile) -> some View {
        NavigationLink(value: Route.profile(profile.pubkey)) {
            ExploreUserRow(profile: profile)
        }
        .listRowBackground(Color.clear)
        .contextMenu { ExploreUserMenu(pubkey: profile.pubkey) }
    }

    @ViewBuilder
    private var overlay: some View {
        if !model.trimmedQuery.isEmpty, model.results.isEmpty {
            if model.isSearching {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text(L("searchingForUsers")).font(.system(size: 15)).foregroundStyle(AppColors.textSecondary)
                }
            } else if model.hasSearched {
                EmptyStateView(systemImage: "person.fill.questionmark", title: L("noUsersFound"), message: L("trySearchingDifferentTerm"), actionTitle: L("retry")) {
                    model.retry()
                }
            }
        }
    }

    private func openResolved() {
        if let pubkey = UserSearchService.pubkey(from: model.query) {
            opened += 1
            Router.shared.push(.profile(pubkey))
        }
    }

    private func paste() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        model.query = text
    }
}
