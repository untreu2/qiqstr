import SwiftUI

enum FollowSetEditorMode: Identifiable, Hashable {
    case create
    case details(FollowSet)
    case members(FollowSet)

    var id: String {
        switch self {
        case .create: "create"
        case .details(let set): "details-\(set.id)"
        case .members(let set): "members-\(set.id)"
        }
    }
}

struct FollowSetEditorSheet: View {
    let mode: FollowSetEditorMode
    var onCreated: ((FollowSet) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var selected: [String] = []
    @State private var search = UserSearchModel()
    @State private var saving = false
    @State private var saved = 0
    @FocusState private var focusedField: Field?

    private enum Field { case title, description, search }

    private var showsDetails: Bool { if case .members = mode { false } else { true } }
    private var showsMembers: Bool { if case .details = mode { false } else { true } }

    private var navigationTitle: String {
        switch mode {
        case .create: L("createList")
        case .details: L("exploreEditList")
        case .members: L("exploreAddMembers")
        }
    }

    private var canSave: Bool {
        guard !saving else { return false }
        return showsDetails ? !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : true
    }

    var body: some View {
        NavigationStack {
            Form {
                if showsDetails {
                    Section {
                        TextField(L("listNameHint"), text: $title)
                            .focused($focusedField, equals: .title)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .description }
                            .accessibilityIdentifier("followset-name-field")
                        TextField(L("listDescriptionHint"), text: $description, axis: .vertical)
                            .lineLimit(1...4)
                            .focused($focusedField, equals: .description)
                            .accessibilityIdentifier("followset-description-field")
                    }
                }
                if showsMembers {
                    if !selected.isEmpty {
                        Section {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(selected, id: \.self) { pubkey in
                                        SelectedMemberChip(pubkey: pubkey) { toggle(pubkey) }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        } header: {
                            Text("\(L("exploreSelected")) · \(selected.count)")
                        }
                    }
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField(L("searchUsers"), text: $search.query)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .search)
                                .accessibilityIdentifier("followset-member-search")
                            if search.isSearching { ProgressView().controlSize(.small) }
                        }
                        ForEach(candidates) { profile in
                            Button { toggle(profile.pubkey) } label: {
                                HStack {
                                    ExploreUserRow(profile: profile, showsFollowButton: false, avatarSize: 38)
                                    Image(systemName: selected.contains(profile.pubkey) ? "checkmark.circle.fill" : "circle")
                                        .font(.title2)
                                        .foregroundStyle(selected.contains(profile.pubkey) ? .primary : .secondary)
                                        .contentTransition(.symbolEffect(.replace))
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("followset-candidate-\(profile.pubkey)")
                        }
                        if !search.trimmedQuery.isEmpty, search.hasSearched, !search.isSearching, search.results.isEmpty {
                            Text(L("noUsersFound")).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(search.trimmedQuery.isEmpty ? L("following") : L("users"))
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("cancel"), role: .cancel) { dismiss() }
                        .accessibilityIdentifier("followset-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { Task { await save() } } label: {
                        if saving { ProgressView() } else { Text(mode == .create ? L("create") : L("save")) }
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("followset-save")
                }
            }
            .sensoryFeedback(.success, trigger: saved)
            .interactiveDismissDisabled(saving)
        }
        .presentationDetents(showsMembers ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await setup() }
    }

    private var candidates: [Profile] {
        if search.trimmedQuery.isEmpty { return followingProfiles }
        return search.results
    }

    @State private var followingProfiles: [Profile] = []

    private func setup() async {
        switch mode {
        case .create:
            focusedField = .title
        case .details(let set):
            title = set.title
            description = set.description
            focusedField = .title
        case .members(let set):
            selected = set.pubkeys
        }
        guard showsMembers, let me = Session.shared.pubkey else { return }
        search.resultLimit = 30
        let follows = Array(await SyncService.shared.followingList(me).filter { $0 != me }.prefix(200))
        await ProfileCache.shared.load(follows)
        followingProfiles = follows.map { ProfileCache.shared.profile($0) ?? Profile(pubkey: $0) }
            .sorted { $0.bestName.localizedCaseInsensitiveCompare($1.bestName) == .orderedAscending }
    }

    private func toggle(_ pubkey: String) {
        if let index = selected.firstIndex(of: pubkey) { selected.remove(at: index) } else { selected.append(pubkey) }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let service = FollowSetService.shared
        do {
            switch mode {
            case .create:
                let created = try await service.create(title: title, description: description, pubkeys: selected)
                ToastCenter.shared.show(L("exploreListCreated"), style: .success)
                onCreated?(created)
            case .details(let set):
                try await service.update(set.id, title: title, description: description)
                ToastCenter.shared.show(L("exploreListUpdated"), style: .success)
            case .members(let set):
                try await service.setMembers(selected, for: set.id)
                ToastCenter.shared.show(L("exploreListUpdated"), style: .success)
            }
            saved += 1
            dismiss()
        } catch {
            ToastCenter.shared.error(error)
        }
    }
}

private struct SelectedMemberChip: View {
    let pubkey: String
    let onRemove: () -> Void
    @State private var cache = ProfileCache.shared

    var body: some View {
        Button(action: onRemove) {
            VStack(spacing: 6) {
                ProfileAvatar(pubkey: pubkey, size: 44)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(AppColors.background, AppColors.textPrimary)
                            .offset(x: 4, y: -4)
                    }
                Text(cache.profile(pubkey)?.bestName ?? Profile.shortNpub(pubkey))
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: 60)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(L("removeFromList")) \(cache.profile(pubkey)?.bestName ?? "")")
        .accessibilityIdentifier("followset-selected-\(pubkey)")
    }
}
