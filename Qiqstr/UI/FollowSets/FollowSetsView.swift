import SwiftUI

struct FollowSetsView: View {
    @State private var service = FollowSetService.shared
    @State private var editor: FollowSetEditorMode?
    @State private var pendingDelete: FollowSet?
    @State private var feedback = 0

    var body: some View {
        List {
            Section {
                Text(L("listsSubtitle"))
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            if !service.sets.isEmpty {
                Section {
                    ForEach(service.sets) { set in ownRow(set) }
                } header: {
                    SectionHeader(title: L("exploreMyLists"))
                }
            }
            if !service.followedSets.isEmpty {
                Section {
                    ForEach(service.followedSets) { set in followedRow(set) }
                } header: {
                    SectionHeader(title: L("listsFromFollows"))
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editor = .create } label: { Image(systemName: "plus") }
                    .accessibilityLabel(L("createList"))
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

    @ViewBuilder
    private var overlay: some View {
        if service.sets.isEmpty, service.followedSets.isEmpty {
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
        .listRowBackground(AppColors.inputFill)
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
        .listRowBackground(AppColors.inputFill)
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
        .tint(AppColors.textSecondary)
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
