import SwiftUI

struct DMGroupAvatar: View {
    let group: MarmotGroup?
    var size: CGFloat = 52

    private var others: [String] {
        let me = Session.shared.pubkey
        return Array((group?.members ?? []).filter { $0 != me }.prefix(2))
    }

    var body: some View {
        ZStack {
            if others.count >= 2 {
                ProfileAvatar(pubkey: others[1], size: size * 0.66)
                    .offset(x: size * 0.17, y: -size * 0.17)
                ProfileAvatar(pubkey: others[0], size: size * 0.66)
                    .overlay(Circle().stroke(AppColors.background, lineWidth: 2))
                    .offset(x: -size * 0.17, y: size * 0.17)
            } else {
                Circle().fill(AppColors.tile)
                Image(systemName: "person.3.fill")
                    .font(.system(size: size * 0.34))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension MarmotGroup {
    var displayName: String { name.isEmpty ? L("dmGroupUntitled") : name }
}

struct DMMemberPicker: View {
    @Binding var selected: Set<String>
    var excluded: Set<String> = []
    @State private var model = DMUserPickerViewModel()
    @State private var cache = ProfileCache.shared

    var body: some View {
        Group {
            if !selected.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(selected).sorted(), id: \.self) { pubkey in
                                Button { selected.remove(pubkey) } label: {
                                    HStack(spacing: 6) {
                                        ProfileAvatar(pubkey: pubkey, size: 24)
                                        Text(cache.profile(pubkey)?.bestName ?? Profile.shortNpub(pubkey)).font(.subheadline).lineLimit(1)
                                        Image(systemName: "xmark").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                                    }
                                    .padding(.leading, 4)
                                    .padding(.trailing, 10)
                                    .padding(.vertical, 4)
                                    .background(AppColors.tile, in: .capsule)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("dm-group-selected")
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            Section {
                TextField(L("searchByNameOrNpub"), text: $model.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("dm-group-search")
                if let pubkey = model.directPubkey, !excluded.contains(pubkey) {
                    row(pubkey)
                }
                ForEach(model.results.filter { !excluded.contains($0.pubkey) && $0.pubkey != Session.shared.pubkey }) { profile in
                    row(profile.pubkey)
                }
                if model.results.isEmpty, model.directPubkey == nil {
                    if model.isSearching || model.isLoadingFollowing {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if !model.trimmedQuery.isEmpty {
                        Text(L("noUsersFound")).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(model.trimmedQuery.isEmpty ? L("following") : L("users"))
            }
        }
        .task { await model.loadFollowing() }
        .task(id: model.query) { await model.search() }
    }

    private func row(_ pubkey: String) -> some View {
        let isSelected = selected.contains(pubkey)
        return Button {
            if isSelected { selected.remove(pubkey) } else { selected.insert(pubkey) }
        } label: {
            HStack(spacing: 12) {
                ProfileAvatar(pubkey: pubkey, size: 38)
                Text(cache.profile(pubkey)?.bestName ?? Profile.shortNpub(pubkey))
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppColors.textPrimary : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("dm-group-member-\(pubkey)")
    }
}

struct DMNewGroupView: View {
    let onCreated: (String) -> Void
    @State private var name = ""
    @State private var selected: Set<String> = []
    @State private var isCreating = false
    @FocusState private var nameFocused: Bool

    private var canCreate: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selected.isEmpty && !isCreating }

    var body: some View {
        List {
            Section {
                TextField(L("dmGroupName"), text: $name)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .accessibilityIdentifier("dm-group-name")
            } footer: {
                Text(L("dmGroupFooter")).wrapsInFooter()
            }
            DMMemberPicker(selected: $selected)
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(L("dmNewGroup"))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isCreating)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    create()
                } label: {
                    if isCreating { ProgressView() } else { Text(L("dmGroupCreate")).fontWeight(.semibold) }
                }
                .prominentButtonStyle()
                .disabled(!canCreate)
                .accessibilityIdentifier("dm-group-create")
            }
        }
        .onAppear { nameFocused = true }
    }

    private func create() {
        guard ReadOnlyGate.check(), canCreate else { return }
        isCreating = true
        Task {
            do {
                let key = try await DMService.shared.createGroup(name: name, members: Array(selected))
                onCreated(key)
            } catch {
                ToastCenter.shared.error(error)
            }
            isCreating = false
        }
    }
}

struct DMGroupInfoSheet: View {
    let key: String
    let onLeft: () -> Void
    @State private var service = DMService.shared
    @State private var cache = ProfileCache.shared
    @State private var name = ""
    @State private var adding: Set<String> = []
    @State private var showsAdd = false
    @State private var confirmLeave = false
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss

    private var group: MarmotGroup? { service.group(for: key) }
    private var me: String? { Session.shared.pubkey }
    private var isAdmin: Bool { service.isAdmin(of: key) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        DMGroupAvatar(group: group, size: 56)
                        if isAdmin {
                            TextField(L("dmGroupName"), text: $name)
                                .font(.title3.weight(.semibold))
                                .submitLabel(.done)
                                .onSubmit(rename)
                                .accessibilityIdentifier("dm-group-info-name")
                        } else {
                            Text(group?.displayName ?? "").font(.title3.weight(.semibold))
                        }
                    }
                } footer: {
                    Text(L("dmGroupMembersCount", ["count": group?.members.count ?? 0])).wrapsInFooter()
                }
                Section {
                    ForEach(group?.members.sorted { lhs, rhs in lhs == me ? true : rhs == me ? false : lhs < rhs } ?? [], id: \.self) { member in
                        memberRow(member)
                    }
                    if isAdmin {
                        Button(L("dmGroupAddPeople"), systemImage: "person.badge.plus") {
                            adding = []
                            showsAdd = true
                        }
                        .accessibilityIdentifier("dm-group-add")
                    }
                } header: {
                    Text(L("dmGroupMembers"))
                }
                Section {
                    Button(L("dmGroupLeave"), systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmLeave = true }
                        .accessibilityIdentifier("dm-group-leave")
                } footer: {
                    Text(L("dmGroupEncryption")).wrapsInFooter()
                }
            }
            .disabled(busy)
            .overlay { if busy { ProgressView().controlSize(.large) } }
            .navigationTitle(L("dmGroupInfo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("done"), systemImage: "checkmark") {
                        rename()
                        dismiss()
                    }
                    .accessibilityIdentifier("dm-group-info-done")
                }
            }
            .confirmationDialog(L("dmGroupLeaveConfirm"), isPresented: $confirmLeave, titleVisibility: .visible) {
                Button(L("dmGroupLeave"), role: .destructive) { leave() }
                    .accessibilityIdentifier("dm-group-leave-confirm")
                Button(L("cancel"), role: .cancel) {}
            } message: {
                Text(L("dmGroupLeaveMessage"))
            }
            .sheet(isPresented: $showsAdd) {
                NavigationStack {
                    List { DMMemberPicker(selected: $adding, excluded: Set(group?.members ?? [])) }
                        .listStyle(.insetGrouped)
                        .navigationTitle(L("dmGroupAddPeople"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(L("cancel"), systemImage: "xmark") { showsAdd = false }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L("settingsAdd")) {
                                    showsAdd = false
                                    add(adding)
                                }
                                .prominentButtonStyle()
                                .disabled(adding.isEmpty)
                                .accessibilityIdentifier("dm-group-add-confirm")
                            }
                        }
                }
                .presentationDetents([.large])
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { name = group?.name ?? "" }
        .accessibilityIdentifier("dm-group-info")
    }

    private func memberRow(_ member: String) -> some View {
        HStack(spacing: 12) {
            ProfileAvatar(pubkey: member, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(member == me ? L("dmGroupYou") : cache.profile(member)?.bestName ?? Profile.shortNpub(member))
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if group?.isAdmin(member) == true {
                    Text(L("dmGroupAdmin")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .swipeActions {
            if isAdmin, member != me {
                Button(L("dmGroupRemove"), systemImage: "person.badge.minus", role: .destructive) { remove(member) }
            }
        }
        .contextMenu {
            if member != me {
                Button(L("dmViewProfile"), systemImage: "person.crop.circle") {
                    dismiss()
                    Router.shared.push(.profile(member))
                }
            }
            if isAdmin, member != me {
                Button(L("dmGroupRemove"), systemImage: "person.badge.minus", role: .destructive) { remove(member) }
            }
        }
        .accessibilityIdentifier("dm-group-member-row")
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        Task {
            do { try await work() } catch { ToastCenter.shared.error(error) }
            busy = false
        }
    }

    private func rename() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAdmin, !trimmed.isEmpty, trimmed != group?.name else { return }
        run { try await service.renameGroup(key, to: trimmed) }
    }

    private func add(_ members: Set<String>) {
        guard !members.isEmpty else { return }
        run { try await service.addMembers(Array(members), to: key) }
    }

    private func remove(_ member: String) {
        run { try await service.removeMember(member, from: key) }
    }

    private func leave() {
        run {
            try await service.leaveGroup(key)
            dismiss()
            onLeft()
        }
    }
}
