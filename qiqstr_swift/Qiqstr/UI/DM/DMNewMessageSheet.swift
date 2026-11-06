import Observation
import SwiftUI

@MainActor
@Observable
final class DMUserPickerViewModel {
    var query = ""
    private(set) var followingProfiles: [Profile] = []
    private(set) var searchResults: [Profile] = []
    private(set) var isSearching = false
    private(set) var isLoadingFollowing = true
    private let service = DMService.shared
    private let cache = ProfileCache.shared

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var directPubkey: String? {
        guard let hex = Nip19.pubkeyHex(from: trimmedQuery) else { return nil }
        return hex
    }

    var recentPeers: [String] {
        Array(service.conversations.prefix(8).map(\.peer))
    }

    var results: [Profile] {
        guard !trimmedQuery.isEmpty else { return followingProfiles.map(resolved) }
        guard directPubkey == nil else { return [] }
        let needle = trimmedQuery.lowercased()
        let localMatches = followingProfiles.map(resolved).filter { profile in
            profile.name.lowercased().contains(needle) || profile.displayName.lowercased().contains(needle) || profile.nip05.lowercased().contains(needle)
        }
        var seen = Set(localMatches.map(\.pubkey))
        var merged = localMatches
        for profile in searchResults where !seen.contains(profile.pubkey) {
            seen.insert(profile.pubkey)
            merged.append(profile)
        }
        return merged.sorted { lhs, rhs in
            let l = service.isFollowing(lhs.pubkey), r = service.isFollowing(rhs.pubkey)
            if l != r { return l }
            return lhs.bestName.localizedCaseInsensitiveCompare(rhs.bestName) == .orderedAscending
        }
    }

    func isFollowing(_ pubkey: String) -> Bool { service.isFollowing(pubkey) }

    private func resolved(_ profile: Profile) -> Profile { cache.profile(profile.pubkey) ?? profile }

    func loadFollowing() async {
        let pubkeys = await service.followingPubkeys()
        await cache.load(pubkeys)
        followingProfiles = pubkeys.map { cache.profile($0) ?? Profile(pubkey: $0) }
            .sorted { $0.bestName.localizedCaseInsensitiveCompare($1.bestName) == .orderedAscending }
        isLoadingFollowing = false
    }

    func search() async {
        let current = trimmedQuery
        guard !current.isEmpty, directPubkey == nil else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled, current == trimmedQuery else { return }
        let found = await service.searchProfiles(current)
        guard current == trimmedQuery else { return }
        searchResults = found
        isSearching = false
    }

    func paste(_ strings: [String]) {
        if let value = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines) { query = value }
    }
}

struct DMNewMessageSheet: View {
    let onSelect: (String) -> Void
    @State private var model = DMUserPickerViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let pubkey = model.directPubkey {
                    Section {
                        Button { onSelect(pubkey) } label: {
                            DMUserRow(pubkey: pubkey, subtitle: Profile.shortNpub(pubkey), isFollowing: model.isFollowing(pubkey))
                        }
                        .accessibilityIdentifier("dm-picker-direct")
                    } header: {
                        Text(L("dmStartChat"))
                    }
                }
                if model.trimmedQuery.isEmpty, !model.recentPeers.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(model.recentPeers, id: \.self) { peer in
                                    DMRecentChip(pubkey: peer) { onSelect(peer) }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } header: {
                        Text(L("dmRecent")).padding(.horizontal, 4)
                    }
                }
                if !model.results.isEmpty {
                    Section {
                        ForEach(model.results) { profile in
                            Button { onSelect(profile.pubkey) } label: {
                                DMUserRow(pubkey: profile.pubkey, subtitle: profile.nip05.nilIfEmpty ?? Profile.shortNpub(profile.pubkey), isFollowing: model.isFollowing(profile.pubkey))
                            }
                            .accessibilityIdentifier("dm-picker-user-\(profile.pubkey)")
                        }
                    } header: {
                        Text(model.trimmedQuery.isEmpty ? L("following") : L("users"))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.immediately)
            .overlay { overlay }
            .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: L("searchByNameOrNpub"))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .task { await model.loadFollowing() }
            .task(id: model.query) { await model.search() }
            .navigationTitle(L("newMessage"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L("cancel"))
                        .accessibilityIdentifier("dm-picker-cancel")
                }
                ToolbarItem(placement: .primaryAction) {
                    PasteButton(payloadType: String.self) { strings in
                        Task { @MainActor in model.paste(strings) }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
                    .accessibilityIdentifier("dm-picker-paste")
                }
            }
        }
        .accessibilityIdentifier("dm-picker")
    }

    @ViewBuilder
    private var overlay: some View {
        if model.directPubkey == nil, model.results.isEmpty {
            if model.trimmedQuery.isEmpty {
                if model.isLoadingFollowing {
                    ProgressView()
                } else if model.recentPeers.isEmpty {
                    EmptyStateView(systemImage: "person.2", title: L("startConversationBy"), message: L("searchByNameOrNpub"))
                }
            } else if model.isSearching {
                ProgressView(L("searchingForUsers"))
            } else {
                EmptyStateView(systemImage: "magnifyingglass", title: L("noUsersFound"), message: L("dmPasteNpubHint"))
            }
        }
    }
}

private struct DMUserRow: View {
    let pubkey: String
    let subtitle: String
    let isFollowing: Bool
    @State private var cache = ProfileCache.shared

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatar(pubkey: pubkey, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(cache.profile(pubkey)?.bestName ?? Profile.shortNpub(pubkey))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isFollowing {
                Text(L("following"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.tile, in: Capsule())
            }
        }
        .contentShape(Rectangle())
    }
}

private struct DMRecentChip: View {
    let pubkey: String
    let action: () -> Void
    @State private var cache = ProfileCache.shared

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ProfileAvatar(pubkey: pubkey, size: 56)
                Text(cache.profile(pubkey)?.bestName ?? Profile.shortNpub(pubkey))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: 64)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("dm-picker-recent-\(pubkey)")
    }
}
