import SwiftUI

struct SearchView: View {
    @State private var model = SearchViewModel()

    var body: some View {
        List {
            if model.trimmedQuery.isEmpty {
                SearchDiscoverySections(model: model)
            } else {
                SearchResultSections(model: model)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .scrollDismissesKeyboard(.immediately)
        .overlay { emptyOverlay }
        .navigationTitle(L("search"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $model.query, prompt: L("searchPrompt"))
        .searchScopes($model.scope, activation: .onSearchPresentation) {
            ForEach(SearchScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) { model.submit() }
        .refreshable { await model.refresh() }
        .sensoryFeedback(.selection, trigger: model.scope)
        .sensoryFeedback(.impact(weight: .light), trigger: model.opened)
        .task { await model.start() }
        .accessibilityIdentifier("search-list")
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
