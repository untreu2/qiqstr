import SwiftUI

@MainActor
@Observable
final class FollowListViewModel {
    let pubkey: String
    let mode: FollowListMode
    private(set) var pubkeys: [String] = []
    private(set) var isLoading = true
    private(set) var hasLoaded = false
    var query = ""

    init(pubkey: String, mode: FollowListMode) {
        self.pubkey = pubkey
        self.mode = mode
    }

    func filtered(_ cache: ProfileCache) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return pubkeys }
        if let hex = Nip19.pubkeyHex(from: q) { return pubkeys.filter { $0 == hex } }
        return pubkeys.filter { pk in
            guard let p = cache.profile(pk) else { return pk.hasPrefix(q) }
            return p.name.lowercased().contains(q)
                || p.displayName.lowercased().contains(q)
                || p.nip05.lowercased().contains(q)
                || p.lud16.lowercased().contains(q)
        }
    }

    func loadLocal() async {
        guard mode == .following else { return }
        let local = await ProfileDataSource.following(pubkey)
        if !local.isEmpty || !hasLoaded { apply(local, final: false) }
    }

    func refresh() async {
        switch mode {
        case .following:
            await SyncService.shared.syncFollowingList(pubkey, force: true)
            apply(await ProfileDataSource.following(pubkey), final: true)
        case .followers:
            let found = await ProfileDataSource.followers(pubkey)
            apply(found.isEmpty && !pubkeys.isEmpty ? pubkeys : found, final: true)
        }
        await preloadProfiles()
    }

    private func apply(_ list: [String], final: Bool) {
        var seen = Set<String>()
        pubkeys = list.filter { !$0.isEmpty && seen.insert($0).inserted }
        if final || !pubkeys.isEmpty {
            isLoading = false
            hasLoaded = true
        }
    }

    private func preloadProfiles() async {
        for chunk in stride(from: 0, to: pubkeys.count, by: 400).map({ Array(pubkeys[$0..<min($0 + 400, pubkeys.count)]) }) {
            await ProfileCache.shared.load(chunk)
        }
    }
}

struct FollowListView: View {
    let pubkey: String
    let mode: FollowListMode
    @State private var model: FollowListViewModel
    @State private var cache = ProfileCache.shared
    @State private var bus = DataBus.shared

    init(pubkey: String, mode: FollowListMode) {
        self.pubkey = pubkey
        self.mode = mode
        _model = State(initialValue: FollowListViewModel(pubkey: pubkey, mode: mode))
    }

    private var title: String { mode == .following ? L("following") : L("followers").localizedCapitalized }

    var body: some View {
        let items = model.filtered(cache)
        List {
            if !model.pubkeys.isEmpty {
                Section {
                    ForEach(items, id: \.self) { pk in
                        UserRowView(pubkey: pk, showFollowButton: true)
                            .listRowBackground(AppColors.background)
                    }
                } header: {
                    Text("\(Sats.compact(model.pubkeys.count)) \(mode == .following ? L("followingCount") : L("followers"))")
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .accessibilityIdentifier("follow-list")
        .overlay { overlay(items: items) }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(cache.profile(pubkey)?.bestName ?? "")
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: L("searchByNameOrNpub"))
        .refreshable { await model.refresh() }
        .task {
            if cache.profile(pubkey) == nil { await cache.load([pubkey]) }
            await model.loadLocal()
            await model.refresh()
        }
        .task(id: bus.feedVersion) {
            guard model.hasLoaded else { return }
            await model.loadLocal()
        }
    }

    @ViewBuilder
    private func overlay(items: [String]) -> some View {
        if model.isLoading && model.pubkeys.isEmpty {
            LoadingView()
        } else if model.pubkeys.isEmpty {
            EmptyStateView(systemImage: "person.2", title: mode == .following ? L("noFollowingUsers") : L("profileNoFollowers"), actionTitle: L("retry")) {
                Task { await model.refresh() }
            }
        } else if items.isEmpty {
            ContentUnavailableView.search(text: model.query)
        }
    }
}
