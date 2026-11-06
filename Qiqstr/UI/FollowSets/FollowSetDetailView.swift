import SwiftUI

struct FollowSetDetailView: View {
    let setId: String

    @Environment(\.dismiss) private var dismiss
    @State private var service = FollowSetService.shared
    @State private var cache = ProfileCache.shared
    @State private var editor: FollowSetEditorMode?
    @State private var confirmDelete = false
    @State private var feedback = 0
    @State private var removing: Set<String> = []
    @State private var query = ""
    @ScaledMetric(relativeTo: .headline) private var ownerAvatarSize: CGFloat = 28

    private var set: FollowSet? { service.set(withId: setId) }

    var body: some View {
        Group {
            if let set {
                content(set)
            } else if !service.isLoaded || service.isSyncing {
                LoadingView()
            } else {
                EmptyStateView(systemImage: "list.bullet.rectangle", title: L("exploreListNotFound"))
                    .frame(maxHeight: .infinity)
            }
        }
        .background(AppColors.background)
        .navigationTitle(set?.displayTitle ?? L("listsTitle"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbar }
        .sheet(item: $editor) { FollowSetEditorSheet(mode: $0) }
        .confirmationDialog("\(L("deleteList"))?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("deleteList"), role: .destructive) { deleteSet() }
                .accessibilityIdentifier("followset-confirm-delete")
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(L("exploreDeleteListConfirm", ["title": set?.displayTitle ?? ""]))
        }
        .sensoryFeedback(.success, trigger: feedback)
        .task(id: set?.pubkeys) {
            guard let set else { return }
            await cache.load(set.pubkeys + [set.pubkey])
        }
        .task {
            if !service.isLoaded { await service.load() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let set {
            let own = service.isOwn(set)
            let favorite = service.isFavorite(set.id)
            if own {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editor = .members(set) } label: { Label(L("exploreAddMembers"), systemImage: "person.badge.plus") }
                        .accessibilityIdentifier("followset-add-members")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        service.toggleFavorite(set.id)
                        feedback += 1
                    } label: {
                        Label(favorite ? L("removeFromFeed") : L("addToFeed"), systemImage: favorite ? "pin.slash" : "pin")
                    }
                    .accessibilityIdentifier("followset-toggle-feed")
                    if own {
                        Button { editor = .details(set) } label: { Label(L("exploreEditList"), systemImage: "pencil") }
                            .accessibilityIdentifier("followset-edit")
                        Divider()
                        Button(role: .destructive) { confirmDelete = true } label: { Label(L("deleteList"), systemImage: "trash") }
                            .accessibilityIdentifier("followset-delete")
                    } else {
                        Button { Router.shared.push(.profile(set.pubkey)) } label: { Label(L("exploreViewAuthor"), systemImage: "person.crop.circle") }
                    }
                } label: {
                    Label(L("exploreMoreOptions"), systemImage: "ellipsis")
                }
                .accessibilityIdentifier("followset-more")
            }
        }
    }

    private func content(_ set: FollowSet) -> some View {
        let own = service.isOwn(set)
        let members = filteredMembers(set)
        return List {
            Section {
                if !set.description.isEmpty {
                    Text(set.description)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
                if !own {
                    Button { Router.shared.push(.profile(set.pubkey)) } label: {
                        HStack(spacing: 12) {
                            ProfileAvatar(pubkey: set.pubkey, size: ownerAvatarSize)
                            Text(L("exploreByAuthor", ["name": cache.profile(set.pubkey)?.bestName ?? Profile.shortNpub(set.pubkey)]))
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("followset-owner")
                }
                if service.isFavorite(set.id) {
                    Label(L("exploreInFeed"), systemImage: "pin.fill")
                        .foregroundStyle(.secondary)
                }
            }
            if set.pubkeys.isEmpty {
                Section {
                    EmptyStateView(
                        systemImage: "person.2",
                        title: L("noMembersInList"),
                        message: own ? nil : L("noMembersInListDescription"),
                        actionTitle: own ? L("exploreAddMembers") : nil,
                        action: own ? { editor = .members(set) } : nil
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(members, id: \.self) { pubkey in
                        NavigationLink(value: Route.profile(pubkey)) {
                            ExploreUserRow(profile: cache.profile(pubkey) ?? Profile(pubkey: pubkey))
                        }
                        .opacity(removing.contains(pubkey) ? 0.4 : 1)
                        .contextMenu {
                            ExploreUserMenu(pubkey: pubkey)
                            if own {
                                Divider()
                                Button(role: .destructive) { remove(pubkey, from: set) } label: { Label(L("removeFromList"), systemImage: "minus.circle") }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if own {
                                Button(role: .destructive) { remove(pubkey, from: set) } label: { Label(L("removeFromList"), systemImage: "minus.circle") }
                                    .accessibilityIdentifier("followset-remove-\(pubkey)")
                            }
                        }
                    }
                } header: {
                    Text(FollowSet.memberCountText(set.pubkeys.count))
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("followset-members")
        .searchable(text: $query, prompt: L("exploreSearchMembers"))
        .overlay {
            if !query.isEmpty, members.isEmpty, !set.pubkeys.isEmpty {
                EmptyStateView(systemImage: "magnifyingglass", title: L("noResultsFound"), message: L("trySearchingDifferentTerm"))
            }
        }
        .refreshable { await service.refresh() }
    }

    private func filteredMembers(_ set: FollowSet) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return set.pubkeys }
        return set.pubkeys.filter { pubkey in
            guard let profile = cache.profile(pubkey) else { return pubkey.localizedCaseInsensitiveContains(q) }
            return profile.bestName.localizedCaseInsensitiveContains(q) || profile.nip05.localizedCaseInsensitiveContains(q)
        }
    }

    private func remove(_ pubkey: String, from set: FollowSet) {
        removing.insert(pubkey)
        Task {
            defer { removing.remove(pubkey) }
            do {
                try await service.removeMember(pubkey, from: set.id)
                feedback += 1
                ToastCenter.shared.show(L("exploreMemberRemoved"), style: .success)
            } catch {
                ToastCenter.shared.error(error)
            }
        }
    }

    private func deleteSet() {
        guard let set else { return }
        let service = service
        dismiss()
        Task {
            do {
                try await service.delete(set.id)
                ToastCenter.shared.show(L("exploreListDeleted"), style: .success)
            } catch {
                ToastCenter.shared.error(error)
            }
        }
    }
}
