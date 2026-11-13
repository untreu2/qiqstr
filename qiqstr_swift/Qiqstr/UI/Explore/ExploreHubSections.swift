import SwiftUI

struct ExploreHubSections: View {
    let section: ExploreSection
    let model: SearchViewModel
    let onSelect: (ExploreSection) -> Void
    let onOpenMedia: (Int) -> Void
    @State private var explore = ExploreService.shared
    @State private var packs = FollowPackService.shared

    var body: some View {
        switch section {
        case .forYou: forYou
        case .feeds: DiscoverFeedSections()
        case .people: people
        case .zaps: zaps
        case .topics: topics
        case .media: EmptyView()
        }
    }

    private var rankedPacks: [FollowPack] { packs.ranked(for: []) }

    private var topicTags: [String] {
        let tags = explore.topics.prefix(16).map(\.tag)
        return tags.isEmpty ? model.trendingHashtags : Array(tags)
    }

    @ViewBuilder
    private var forYou: some View {
        LiveNowSection()
        if !topicTags.isEmpty {
            Section {
                TopicChips(tags: topicTags)
            } header: {
                SearchSectionHeader(title: L("exploreTrendingTopics")) { onSelect(.topics) }
            }
        }
        if !explore.feeds.isEmpty {
            Section {
                ExploreCarousel {
                    ForEach(explore.feeds.prefix(10)) { DiscoverFeedCard(feed: $0) }
                }
            } header: {
                SearchSectionHeader(title: L("explorePopularFeeds")) { onSelect(.feeds) }
            }
            .accessibilityIdentifier("explore-popular-feeds")
        }
        if !explore.visibleMedia.isEmpty {
            Section {
                ExploreMediaStrip(entries: Array(explore.visibleMedia.prefix(12)), onOpen: onOpenMedia)
            } header: {
                SearchSectionHeader(title: L("exploreTrendingMedia")) { onSelect(.media) }
            }
            .accessibilityIdentifier("explore-media-strip")
        }
        if !explore.visiblePeople.isEmpty {
            Section {
                ExploreCarousel {
                    ForEach(explore.visiblePeople.prefix(12)) { RisingPersonCard(person: $0) }
                }
            } header: {
                SearchSectionHeader(title: L("exploreRisingPeople")) { onSelect(.people) }
            }
            .accessibilityIdentifier("explore-rising-people")
        }
        if !explore.visibleZaps.isEmpty {
            Section {
                ForEach(explore.visibleZaps.prefix(3)) { zap in
                    TopZapRow(zap: zap, note: zap.noteId.flatMap { explore.zapNotes[$0] })
                }
            } header: {
                SearchSectionHeader(title: L("exploreTopZaps")) { onSelect(.zaps) }
            }
            .accessibilityIdentifier("explore-top-zaps")
        }
        if !rankedPacks.isEmpty {
            Section {
                ExploreCarousel {
                    ForEach(rankedPacks.prefix(10)) { FollowPackTile(pack: $0) }
                }
            } header: {
                SearchSectionHeader(title: L("exploreFollowPacks")) { onSelect(.people) }
            }
            .accessibilityIdentifier("explore-follow-packs")
        }
        Section {
            NavigationLink(value: Route.reads) {
                Label { exploreLinkText(L("reads"), L("exploreReadsSubtitle")) } icon: { IconTile(systemImage: "doc.text", size: 40) }
            }
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("explore-link-reads")
            NavigationLink(value: Route.liveStreams) {
                Label { exploreLinkText(L("liveTitle"), L("exploreLiveSubtitle")) } icon: { IconTile(systemImage: "dot.radiowaves.left.and.right", size: 40) }
            }
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("explore-link-live")
            NavigationLink(value: Route.userSearch) {
                Label { exploreLinkText(L("exploreFindPeople"), L("exploreFindPeopleSubtitle")) } icon: { IconTile(systemImage: "person.crop.circle.badge.magnifyingglass", size: 40) }
            }
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("explore-link-people")
        } header: {
            SearchSectionHeader(title: L("exploreMore"))
        }
        SearchDiscoverySections(model: model, showsHashtags: false, showsRecents: false, showsLive: false, showsPeople: explore.visiblePeople.isEmpty)
    }

    private func exploreLinkText(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
            Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    @ViewBuilder
    private var people: some View {
        Section {
            if explore.visiblePeople.isEmpty {
                if explore.isLoading("people") {
                    ExploreLoadingRows(count: 5, person: true)
                } else {
                    retryRow(L("exploreUnavailable")) { await explore.loadPeople(force: true) }
                }
            } else {
                ForEach(explore.visiblePeople.prefix(15)) { RisingPersonRow(person: $0) }
            }
        } header: {
            SearchSectionHeader(title: L("exploreRisingPeople"))
        } footer: {
            if !explore.visiblePeople.isEmpty {
                Text(L("exploreRisingFooter")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("explore-people-list")
        Section {
            if rankedPacks.isEmpty {
                if packs.isLoading { ExploreLoadingRows(count: 3, person: true) }
            } else {
                ForEach(rankedPacks.prefix(30)) { FollowPackRow(pack: $0) }
            }
        } header: {
            SearchSectionHeader(title: L("exploreFollowPacks"))
        }
        .accessibilityIdentifier("explore-packs-list")
    }

    @ViewBuilder
    private var zaps: some View {
        Section {
            if explore.visibleZaps.isEmpty {
                if explore.isLoading("zaps") {
                    ExploreLoadingRows(count: 4)
                } else {
                    retryRow(L("exploreUnavailable")) { await explore.loadZaps(force: true) }
                }
            } else {
                ForEach(explore.visibleZaps) { zap in
                    TopZapRow(zap: zap, note: zap.noteId.flatMap { explore.zapNotes[$0] })
                }
            }
        } header: {
            SearchSectionHeader(title: L("exploreTopZapsToday"))
        }
        .accessibilityIdentifier("explore-zaps-list")
    }

    @ViewBuilder
    private var topics: some View {
        Section {
            if explore.topics.isEmpty {
                if explore.isLoading("topics") {
                    ExploreLoadingRows(count: 6, person: true)
                } else {
                    retryRow(L("exploreUnavailable")) { await explore.loadTopics(force: true) }
                }
            } else {
                ForEach(Array(explore.topics.enumerated()), id: \.element.id) { index, topic in
                    TopicRow(topic: topic, rank: index + 1)
                }
            }
        } header: {
            SearchSectionHeader(title: L("exploreTrendingTopics"))
        } footer: {
            if !explore.topics.isEmpty {
                Text(L("exploreTopicsFooter")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("explore-topics-list")
    }

    private func retryRow(_ text: String, action: @escaping () async -> Void) -> some View {
        HStack {
            SearchInlineMessage(text: text)
            Spacer()
            Button(L("retry")) { Task { await action() } }
                .font(.footnote)
                .buttonStyle(.borderless)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

struct DiscoverFeedSections: View {
    @State private var explore = ExploreService.shared

    private var notesFeeds: [DiscoverFeed] { explore.feeds.filter { $0.content == .notes && !explore.isPinned($0) } }
    private var readsFeeds: [DiscoverFeed] { explore.feeds.filter { $0.content == .reads } }

    var body: some View {
        if !explore.pinnedFeeds.isEmpty {
            Section {
                ForEach(explore.pinnedFeeds) { DiscoverFeedRow(feed: $0) }
            } header: {
                SearchSectionHeader(title: L("exploreFeedsOnHome"))
            } footer: {
                Text(L("exploreFeedsOnHomeFooter")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        if explore.feeds.isEmpty {
            Section {
                if explore.isLoading("feeds") {
                    ExploreLoadingRows(count: 5, person: true)
                } else {
                    HStack {
                        SearchInlineMessage(text: L("exploreUnavailable"))
                        Spacer()
                        Button(L("retry")) { Task { await explore.loadFeeds(force: true) } }
                            .font(.footnote)
                            .buttonStyle(.borderless)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        if !notesFeeds.isEmpty {
            Section {
                ForEach(notesFeeds) { DiscoverFeedRow(feed: $0) }
            } header: {
                SearchSectionHeader(title: L("exploreNoteFeeds"))
            } footer: {
                Text(L("exploreNoteFeedsFooter")).font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("explore-note-feeds")
        }
        if !readsFeeds.isEmpty {
            Section {
                ForEach(readsFeeds) { DiscoverFeedRow(feed: $0) }
            } header: {
                SearchSectionHeader(title: L("exploreReadFeeds"))
            }
            .accessibilityIdentifier("explore-read-feeds")
        }
    }
}

struct DiscoverFeedsView: View {
    @State private var explore = ExploreService.shared

    var body: some View {
        List { DiscoverFeedSections() }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .navigationTitle(L("exploreFeeds"))
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await explore.loadFeeds(force: true) }
            .task { await explore.loadFeeds() }
            .accessibilityIdentifier("discover-feeds")
    }
}

struct ExploreMediaGrid: View {
    let onOpen: (Int) -> Void
    @State private var explore = ExploreService.shared

    var body: some View {
        ScrollView {
            if explore.visibleMedia.isEmpty {
                if explore.isLoading("media") {
                    ProgressView().padding(.top, 80)
                } else {
                    EmptyStateView(systemImage: "photo.on.rectangle", title: L("exploreUnavailable"), actionTitle: L("retry")) {
                        Task { await explore.loadMedia(force: true) }
                    }
                    .padding(.top, 60)
                }
            } else {
                ProfileMediaGrid(entries: explore.visibleMedia, onOpen: onOpen)
                    .accessibilityIdentifier("explore-media-grid")
                if !explore.mediaExhausted {
                    ProgressView()
                        .padding(.vertical, 24)
                        .onAppear { Task { await explore.loadMoreMedia() } }
                }
            }
        }
    }
}
