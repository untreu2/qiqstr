import SwiftUI

struct AddToListSheet: View {
    let pubkey: String
    let displayName: String
    @Environment(\.dismiss) private var dismiss
    @State private var service = FollowSetService.shared
    @State private var working: Set<String> = []
    @State private var newTitle = ""
    @State private var showCreate = false
    @State private var feedback = 0

    private var ownSets: [FollowSet] { service.sets }

    var body: some View {
        NavigationStack {
            List {
                if ownSets.isEmpty {
                    if service.isLoaded {
                        EmptyStateView(systemImage: "person.2", title: L("noLists"), message: L("noListsDescription"))
                            .listRowBackground(Color.clear)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(ownSets) { set in
                            row(set)
                        }
                    } footer: {
                        Text(L("profileAddToListFooter", ["name": displayName]))
                    }
                }
                Section {
                    Button { showCreate = true } label: {
                        Label(L("createList"), systemImage: "plus")
                    }
                    .accessibilityIdentifier("add-to-list-create")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L("addToList"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityIdentifier("add-to-list-close")
                }
            }
            .alert(L("createList"), isPresented: $showCreate) {
                TextField(L("listNameHint"), text: $newTitle)
                Button(L("cancel"), role: .cancel) { newTitle = "" }
                Button(L("profileCreateAndAdd")) { Task { await create() } }
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .task { if !service.isLoaded { await service.load() } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: feedback)
        .accessibilityIdentifier("add-to-list-sheet")
    }

    private func row(_ set: FollowSet) -> some View {
        let isMember = set.pubkeys.contains(pubkey)
        return Button { Task { await toggle(set, isMember: isMember) } } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(set.displayTitle).foregroundStyle(.primary)
                    Text(L("profileListMemberCount", ["count": set.pubkeys.count]))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if working.contains(set.id) {
                    ProgressView()
                } else if isMember {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColors.link)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(working.contains(set.id))
        .accessibilityAddTraits(isMember ? .isSelected : [])
        .accessibilityIdentifier("add-to-list-row")
    }

    private func toggle(_ set: FollowSet, isMember: Bool) async {
        working.insert(set.id)
        defer { working.remove(set.id) }
        do {
            if isMember {
                try await service.removeMember(pubkey, from: set.id)
                ToastCenter.shared.show(L("profileRemovedFromList", ["list": set.displayTitle]), style: .success)
            } else {
                try await service.addMember(pubkey, to: set.id)
                ToastCenter.shared.show(L("profileAddedToList", ["list": set.displayTitle]), style: .success)
            }
            feedback += 1
        } catch {
            ToastCenter.shared.error(error)
        }
    }

    private func create() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        newTitle = ""
        guard !title.isEmpty else { return }
        do {
            let created = try await service.create(title: title, pubkeys: [pubkey])
            feedback += 1
            ToastCenter.shared.show(L("profileAddedToList", ["list": created.displayTitle]), style: .success)
        } catch {
            ToastCenter.shared.error(error)
        }
    }
}
