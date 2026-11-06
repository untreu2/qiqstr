import SwiftUI

struct FollowSetsView: View {
    @State private var service = FollowSetService.shared
    @State private var editor: FollowSetEditorMode?
    @State private var pendingDelete: FollowSet?
    @State private var feedback = 0
    @State private var query = ""

    var body: some View {
        List {
            let own = filtered(service.sets)
            let followed = filtered(service.followedSets)
            if !own.isEmpty {
                Section {
                    ForEach(own) { set in ownRow(set) }
                } header: {
                    Text(L("exploreMyLists"))
                } footer: {
                    if query.isEmpty { Text(L("listsSubtitle")) }
                }
            }
            if !followed.isEmpty {
                Section {
                    ForEach(followed) { set in followedRow(set) }
                } header: {
                    Text(L("listsFromFollows"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .accessibilityIdentifier("followsets-list")
        .overlay { overlay }
        .navigationTitle(L("listsTitle"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: L("exploreSearchLists"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editor = .create } label: { Label(L("createList"), systemImage: "plus") }
                    .accessibilityIdentifier("followsets-create")
            }
        }
        .refreshable { await service.refresh() }
        .sheet(item: $editor) { mode in
            FollowSetEditorSheet(mode: mode) { created in
                Router.shared.push(.followSet(created.id))
            }
        }
        .confirmationDialog(
            "\(L("deleteList"))?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { set in
            Button(L("deleteList"), role: .destructive) { delete(set) }
                .accessibilityIdentifier("followsets-confirm-delete")
            Button(L("cancel"), role: .cancel) {}
        } message: { set in
            Text(L("exploreDeleteListConfirm", ["title": set.displayTitle]))
        }
        .sensoryFeedback(.success, trigger: feedback)
        .task {
            if !service.isLoaded { await service.load() } else { await service.refresh() }
        }
    }

    private func filtered(_ sets: [FollowSet]) -> [FollowSet] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return sets }
        return sets.filter { $0.displayTitle.localizedCaseInsensitiveContains(q) || $0.description.localizedCaseInsensitiveContains(q) }
    }

    @ViewBuilder
    private var overlay: some View {
        if !query.isEmpty, filtered(service.sets).isEmpty, filtered(service.followedSets).isEmpty {
            EmptyStateView(systemImage: "magnifyingglass", title: L("noResultsFound"), message: L("trySearchingDifferentTerm"))
        } else if service.sets.isEmpty, service.followedSets.isEmpty {
            if !service.isLoaded || service.isSyncing {
                LoadingView()
            } else {
                EmptyStateView(systemImage: "list.bullet.rectangle", title: L("noLists"), message: L("noListsDescription"), actionTitle: L("createList")) {
                    editor = .create
                }
            }
        }
    }

    private func ownRow(_ set: FollowSet) -> some View {
        NavigationLink(value: Route.followSet(set.id)) {
            FollowSetRow(set: set, isFavorite: service.isFavorite(set.id))
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { pendingDelete = set } label: { Label(L("delete"), systemImage: "trash") }
                .accessibilityIdentifier("followset-swipe-delete-\(set.dTag)")
            Button { editor = .details(set) } label: { Label(L("exploreEditList"), systemImage: "pencil") }
                .tint(.gray)
        }
        .swipeActions(edge: .leading) { favoriteButton(set) }
        .contextMenu {
            favoriteButton(set)
            Button { editor = .details(set) } label: { Label(L("exploreEditList"), systemImage: "pencil") }
            Button { editor = .members(set) } label: { Label(L("exploreAddMembers"), systemImage: "person.badge.plus") }
            Divider()
            Button(role: .destructive) { pendingDelete = set } label: { Label(L("deleteList"), systemImage: "trash") }
        }
        .accessibilityIdentifier("followset-row-\(set.dTag)")
    }

    private func followedRow(_ set: FollowSet) -> some View {
        NavigationLink(value: Route.followSet(set.id)) {
            FollowSetRow(set: set, showsOwner: true, isFavorite: service.isFavorite(set.id))
        }
        .swipeActions(edge: .leading) { favoriteButton(set) }
        .contextMenu {
            favoriteButton(set)
            Button { Router.shared.push(.profile(set.pubkey)) } label: { Label(L("exploreViewAuthor"), systemImage: "person.crop.circle") }
        }
        .accessibilityIdentifier("followset-row-\(set.pubkey)-\(set.dTag)")
    }

    private func favoriteButton(_ set: FollowSet) -> some View {
        let favorite = service.isFavorite(set.id)
        return Button {
            service.toggleFavorite(set.id)
            feedback += 1
        } label: {
            Label(favorite ? L("removeFromFeed") : L("addToFeed"), systemImage: favorite ? "pin.slash" : "pin")
        }
        .tint(.gray)
    }

    private func delete(_ set: FollowSet) {
        Task {
            do {
                try await service.delete(set.id)
                feedback += 1
                ToastCenter.shared.show(L("exploreListDeleted"), style: .success)
            } catch {
                ToastCenter.shared.error(error)
            }
        }
    }
}
