import SwiftUI

@MainActor
@Observable
final class DiscoverFeedViewModel {
    let feedId: String
    private(set) var feed: DiscoverFeed?
    private(set) var notes: [Note] = []
    private(set) var articles: [Article] = []
    private(set) var isLoading = true
    private(set) var failed = false

    private let explore = ExploreService.shared

    init(feedId: String) {
        self.feedId = feedId
        feed = ExploreService.shared.feed(id: feedId)
    }

    func load() async {
        if feed == nil {
            await explore.loadFeeds()
            feed = explore.feed(id: feedId)
        }
        guard let feed else {
            isLoading = false
            failed = true
            return
        }
        isLoading = notes.isEmpty && articles.isEmpty
        defer { isLoading = false }
        switch feed.content {
        case .notes:
            guard let result = await explore.feedNotes(feed) else { failed = notes.isEmpty; return }
            notes = result
            NoteInteractionStore.shared.seed(result)
            NoteInteractionStore.shared.requestCounts(result.prefix(40).map(\.id))
        case .reads:
            guard let result = await explore.feedArticles(feed) else { failed = articles.isEmpty; return }
            articles = result
        }
        failed = false
        let pubkeys = Array(Set(notes.map(\.pubkey) + articles.map(\.pubkey)))
        await ProfileCache.shared.load(pubkeys.filter { ProfileCache.shared.profile($0) == nil })
    }
}

struct DiscoverFeedView: View {
    @State private var model: DiscoverFeedViewModel
    @State private var explore = ExploreService.shared

    init(feedId: String) {
        _model = State(initialValue: DiscoverFeedViewModel(feedId: feedId))
    }

    var body: some View {
        content
            .background(AppColors.background)
            .navigationTitle(model.feed?.name ?? L("exploreFeeds"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .refreshable { await model.load() }
            .task { await model.load() }
            .accessibilityIdentifier("discover-feed-view")
    }

    @ViewBuilder
    private var content: some View {
        if let feed = model.feed, feed.content == .reads {
            List {
                header(feed)
                ForEach(model.articles) { article in
                    ArticleCardView(article: article)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay { stateOverlay(isEmpty: model.articles.isEmpty) }
        } else {
            NoteList(notes: model.notes) {
                if let feed = model.feed { header(feed) }
            }
            .overlay { stateOverlay(isEmpty: model.notes.isEmpty) }
        }
    }

    private func header(_ feed: DiscoverFeed) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                DiscoverFeedArtwork(feed: feed, size: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Text(feed.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    NavigationLink(value: Route.profile(feed.pubkey)) {
                        DiscoverFeedAuthor(pubkey: feed.pubkey)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            if !feed.about.isEmpty {
                Text(feed.about)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if feed.content == .notes {
                DiscoverFeedPinButton(feed: feed)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(AppColors.background)
    }

    @ViewBuilder
    private func stateOverlay(isEmpty: Bool) -> some View {
        if isEmpty {
            if model.isLoading {
                FeedSkeleton().padding(.top, 180).accessibilityLabel(L("loadingYourFeed"))
            } else if model.failed {
                EmptyStateView(systemImage: "wifi.slash", title: L("exploreUnavailable"), actionTitle: L("retry")) {
                    Task { await model.load() }
                }
            } else {
                EmptyStateView(systemImage: "tray", title: L("noNotesYet"))
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let feed = model.feed {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if feed.content == .notes {
                        let pinned = explore.isPinned(feed)
                        Button(L(pinned ? "exploreFeedRemoveFromHome" : "exploreFeedAddToHome"), systemImage: pinned ? "pin.slash" : "pin") {
                            explore.togglePin(feed)
                        }
                    }
                    Button(L("exploreFeedCreator"), systemImage: "person.crop.circle") { Router.shared.push(.profile(feed.pubkey)) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel(L("exploreMoreOptions"))
                .accessibilityIdentifier("discover-feed-menu")
            }
        }
    }
}

private struct DiscoverFeedAuthor: View {
    let pubkey: String
    @State private var cache = ProfileCache.shared

    var body: some View {
        HStack(spacing: 6) {
            ProfileAvatar(pubkey: pubkey, size: 18)
            Text(L("exploreByAuthor", ["name": cache.profile(pubkey)?.bestName ?? Profile.shortNpub(pubkey)]))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .task { await cache.load([pubkey]) }
    }
}

struct FollowPackView: View {
    let packId: String
    @State private var packs = FollowPackService.shared
    @State private var follows = FollowService.shared
    @State private var confirmFollowAll = false
    @State private var isFollowing = false

    private var pack: FollowPack? { packs.packs.first { $0.id == packId } }
    private var me: String? { Session.shared.pubkey }

    private var remaining: [String] {
        guard let pack else { return [] }
        return pack.members.filter { $0 != me && !follows.isFollowing($0) }
    }

    var body: some View {
        Group {
            if let pack {
                list(pack)
            } else if packs.isLoading {
                LoadingView()
            } else {
                EmptyStateView(systemImage: "person.3", title: L("exploreListNotFound"))
            }
        }
        .background(AppColors.background)
        .navigationTitle(pack?.title ?? L("exploreFollowPacks"))
        .navigationBarTitleDisplayMode(.inline)
        .task { packs.prefetch() }
        .confirmationDialog(L("explorePackFollowAllConfirm", ["count": remaining.count]), isPresented: $confirmFollowAll, titleVisibility: .visible) {
            Button(L("authFollowAll")) { Task { await followAll() } }
            Button(L("cancel"), role: .cancel) {}
        }
        .accessibilityIdentifier("follow-pack-view")
    }

    private func list(_ pack: FollowPack) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        FollowPackArtwork(url: pack.image.nilIfEmpty, isBuiltIn: pack.kind == 0)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pack.title).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                            if !pack.author.isEmpty {
                                NavigationLink(value: Route.profile(pack.author)) {
                                    DiscoverFeedAuthor(pubkey: pack.author)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    if let summary = pack.summary.nilIfEmpty {
                        Text(summary).font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        FollowPackAvatarStack(pubkeys: Array(pack.members.prefix(5)))
                        Text(L("memberCount", ["count": pack.members.count]))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button {
                            confirmFollowAll = true
                        } label: {
                            if isFollowing {
                                ProgressView()
                            } else {
                                Text(remaining.isEmpty ? L("following") : L("authFollowAll")).fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .foregroundStyle(AppColors.background)
                        .buttonBorderShape(.capsule)
                        .disabled(remaining.isEmpty || isFollowing)
                        .accessibilityIdentifier("pack-follow-all")
                    }
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(pack.members.filter { $0 != me }, id: \.self) { pubkey in
                    UserRowView(pubkey: pubkey).listRowBackground(Color.clear)
                }
            } header: {
                Text(L("exploreMembersOther", ["count": pack.members.count]))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .task { await ProfileCache.shared.load(Array(pack.members.prefix(60))) }
    }

    private func followAll() async {
        isFollowing = true
        defer { isFollowing = false }
        do {
            try await follows.follow(many: remaining)
            ToastCenter.shared.show(L("explorePackFollowed"), style: .success)
        } catch {
            ToastCenter.shared.error(error)
        }
    }
}
