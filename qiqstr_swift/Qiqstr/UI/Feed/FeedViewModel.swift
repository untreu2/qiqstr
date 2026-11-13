import Foundation
import Observation

enum FeedSource: Hashable {
    case explore
    case discover(DiscoverFeed)
    case following
    case list(FeedFollowSet)
    case topic(String)
    case topics

    var id: String {
        switch self {
        case .explore: "explore"
        case .discover(let feed): "dvm_\(feed.id)"
        case .following: "following"
        case .list(let set): set.id
        case .topic(let tag): "topic_\(tag)"
        case .topics: "topics"
        }
    }

    var title: String {
        switch self {
        case .explore: L("feedExplore")
        case .discover(let feed): feed.name
        case .following: L("all")
        case .list(let set): set.title
        case .topic(let tag): "#\(tag)"
        case .topics: L("feedTopics")
        }
    }

    var isExplore: Bool { self == .explore }

    var isCurated: Bool {
        switch self {
        case .explore, .discover: true
        default: false
        }
    }

    var isTopicFeed: Bool {
        switch self {
        case .topic, .topics: true
        default: false
        }
    }
}

@MainActor
@Observable
final class FeedViewModel {
    static let pageSize = 50

    private(set) var notes: [Note] = []
    private(set) var pendingCount = 0
    private(set) var hasLoaded = false
    private(set) var isSyncing = true
    private(set) var isLoadingMore = false
    private(set) var canLoadMore = true
    private(set) var lists: [FeedFollowSet] = []
    private(set) var source: FeedSource = .explore
    private(set) var scrollToTopToken = 0
    var sort: FeedSortMode {
        didSet {
            guard sort != oldValue else { return }
            UserDefaults.standard.set(sort.rawValue, forKey: "feed_sort_mode")
            resetForContextChange()
        }
    }
    var includeTopics: Bool {
        didSet {
            guard includeTopics != oldValue else { return }
            UserDefaults.standard.set(includeTopics, forKey: "feed_include_topics")
            guard source == .following else { return }
            resetForContextChange()
            if includeTopics { syncTopicsInBackground() }
        }
    }

    @ObservationIgnored private var fetched: [Note] = []
    @ObservationIgnored private var limit = FeedViewModel.pageSize
    @ObservationIgnored private var latestDisplayed = 0
    @ObservationIgnored private var acceptNext = true
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var prefetched: Set<String> = []
    @ObservationIgnored private var exhaustedRelays = false
    @ObservationIgnored private var graceTask: Task<Void, Never>?

    private var store: NoteInteractionStore { NoteInteractionStore.shared }

    init() {
        sort = FeedSortMode(rawValue: UserDefaults.standard.string(forKey: "feed_sort_mode") ?? "") ?? .latest
        includeTopics = UserDefaults.standard.bool(forKey: "feed_include_topics")
    }

    private var authors: [String]? {
        if case .list(let set) = source { return set.pubkeys }
        return nil
    }

    var followedTopics: [String] { HashtagFollowService.shared.tags }

    private var activeTopics: [String] {
        switch source {
        case .topic(let tag): [tag]
        case .topics: followedTopics
        case .following: includeTopics ? followedTopics : []
        case .list, .explore, .discover: []
        }
    }

    private func query(limit: Int) async -> [Note] {
        if source.isExplore { return await exploreNotes(force: false) }
        if case .discover(let feed) = source { return await discoverNotes(feed, force: false) }
        let topics = activeTopics
        if source.isTopicFeed { return await Self.topicNotes(topics, limit: limit, includeReplies: true) }
        let home = await NoteRepository.feed(authors: authors, limit: limit, sort: sort)
        guard !topics.isEmpty else { return home }
        let extra = await Self.topicNotes(topics, limit: limit, includeReplies: false)
        return Self.interleave(home, extra, limit: limit, sort: sort)
    }

    private func exploreNotes(force: Bool) async -> [Note] {
        if exploreHidden == nil { exploreHidden = ExploreSeenStore.shared.snapshot() }
        let hidden = exploreHidden ?? [:]
        let pool = await TrendingService.shared.explorePool(force: force)
        var ids = pool.filter { hidden[$0] == nil }
        if ids.count < Self.exploreMinimumFresh {
            ids += pool.filter { hidden[$0] != nil }.sorted { (hidden[$0] ?? 0) < (hidden[$1] ?? 0) }
        }
        let byId = Dictionary(await NoteRepository.notes(ids).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byId[$0] }
    }

    @ObservationIgnored private var discoverCache: [String: [Note]] = [:]
    @ObservationIgnored private var exploreHidden: [String: Double]?
    private static let exploreMinimumFresh = 15

    private func discoverNotes(_ feed: DiscoverFeed, force: Bool) async -> [Note] {
        if !force, let cached = discoverCache[feed.id] { return cached }
        guard let notes = await ExploreService.shared.feedNotes(feed) else { return discoverCache[feed.id] ?? [] }
        discoverCache[feed.id] = notes
        return notes
    }

    private static func topicNotes(_ tags: [String], limit: Int, includeReplies: Bool) async -> [Note] {
        var merged: [Note] = []
        var seen: Set<String> = []
        for tag in tags {
            for note in await NoteRepository.hashtag(tag, limit: limit) where includeReplies || !note.isReply {
                if seen.insert(note.listId).inserted { merged.append(note) }
            }
        }
        merged.sort { $0.displayTimestamp > $1.displayTimestamp }
        return Array(merged.prefix(limit))
    }

    private static func interleave(_ home: [Note], _ extra: [Note], limit: Int, sort: FeedSortMode) -> [Note] {
        var listIds = Set(home.map(\.listId))
        var originals = Set(home.map(\.id))
        var merged = home
        for note in extra where !originals.contains(note.id) && listIds.insert(note.listId).inserted {
            originals.insert(note.id)
            merged.append(note)
        }
        switch sort {
        case .latest:
            merged.sort { $0.displayTimestamp > $1.displayTimestamp }
        case .mostInteracted:
            merged.sort { lhs, rhs in
                let l = lhs.reactionCount + lhs.repostCount + lhs.replyCount + lhs.zapCount
                let r = rhs.reactionCount + rhs.repostCount + rhs.replyCount + rhs.zapCount
                return l == r ? lhs.displayTimestamp > rhs.displayTimestamp : l > r
            }
        }
        return Array(merged.prefix(limit))
    }

    private func syncTopics(_ tags: [String], force: Bool = false) async {
        await withTaskGroup(of: Void.self) { group in
            for tag in tags {
                group.addTask { await SyncService.shared.syncHashtag(tag, force: force) }
            }
        }
    }

    private func syncTopicsInBackground() {
        let tags = activeTopics
        guard !tags.isEmpty else { return }
        let generation = self.generation
        Task { [weak self] in
            await self?.syncTopics(tags)
            guard let self, generation == self.generation, self.source.isTopicFeed, self.notes.isEmpty else { return }
            self.isSyncing = false
        }
    }

    private func fetchOlder(until: Int) async -> Int {
        var received = 0
        if !source.isTopicFeed {
            var pubkeys = authors ?? []
            if pubkeys.isEmpty, let me = Session.shared.pubkey { pubkeys = Array(Set(await NoteRepository.following() + [me])) }
            received += await NoteRepository.fetchOlder(authors: pubkeys, until: until)
        }
        for tag in activeTopics {
            received += await NoteRepository.fetchOlderHashtag(tag, until: until)
        }
        return received
    }

    func topicsChanged() {
        let tags = followedTopics
        switch source {
        case .topic(let tag):
            if !tags.contains(tag) { select(.following) }
        case .topics:
            if tags.isEmpty { select(.following) } else { refreshTopicsQuietly() }
        case .following:
            if includeTopics { refreshTopicsQuietly() }
        case .list, .explore, .discover:
            break
        }
    }

    private func refreshTopicsQuietly() {
        let tags = activeTopics
        Task { [weak self] in
            await self?.reload()
            await self?.syncTopics(tags)
        }
    }

    func start() {
        guard graceTask == nil else { return }
        if Session.shared.isNewAccount { isSyncing = false }
        graceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.isSyncing = false
        }
        syncTopicsInBackground()
    }

    func reload() async {
        let generation = self.generation
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled, generation == self.generation else { return }
        let result = await query(limit: limit)
        guard generation == self.generation else { return }
        apply(result)
    }

    private func apply(_ result: [Note]) {
        fetched = result
        let visible = filtered(result)
        let me = Session.shared.pubkey
        if notes.isEmpty || acceptNext || source.isCurated {
            acceptNext = false
            show(visible)
        } else {
            let displayedIds = Set(notes.map(\.listId))
            var others = 0
            var ownNew = false
            for note in visible where note.displayTimestamp > latestDisplayed && !displayedIds.contains(note.listId) {
                if (note.isRepost ? note.repostedBy : note.pubkey) == me { ownNew = true } else { others += 1 }
            }
            if others > 0 {
                notes = visible.filter { note in
                    note.displayTimestamp <= latestDisplayed || displayedIds.contains(note.listId) || (note.isRepost ? note.repostedBy : note.pubkey) == me
                }
                pendingCount = others
            } else {
                if ownNew { latestDisplayed = max(latestDisplayed, visible.map(\.displayTimestamp).max() ?? 0) }
                notes = visible
                pendingCount = 0
            }
        }
        if !result.isEmpty { isSyncing = false }
        hasLoaded = true
        canLoadMore = !source.isCurated && (!exhaustedRelays || result.count >= limit)
        afterLoad(visible)
    }

    private func show(_ visible: [Note]) {
        notes = visible
        latestDisplayed = visible.map(\.displayTimestamp).max() ?? 0
        pendingCount = 0
    }

    private func afterLoad(_ visible: [Note]) {
        store.seed(visible)
        let fresh = visible.filter { !prefetched.contains($0.listId) }
        guard !fresh.isEmpty else { return }
        prefetched.formUnion(fresh.map(\.listId))
        store.requestCounts(fresh.map(\.id))
        NoteRepository.prefetchEmbedded(fresh)
        var pubkeys = Set(fresh.map(\.pubkey))
        for note in fresh { if let r = note.repostedBy { pubkeys.insert(r) } }
        Task {
            await NoteContentCache.warm(fresh)
            await ProfileCache.shared.load(Array(pubkeys).filter { ProfileCache.shared.profile($0) == nil })
        }
    }

    func filtered(_ list: [Note]) -> [Note] {
        let mutedPubkeys = Set(Session.shared.mutedPubkeys)
        let words = Session.shared.mutedWords.map { $0.lowercased() }.filter { !$0.isEmpty }
        let deleted = store.deletedIds
        var seen: Set<String> = []
        return list.filter { note in
            guard !deleted.contains(note.id), seen.insert(note.listId).inserted else { return false }
            if mutedPubkeys.contains(note.pubkey) { return false }
            if let r = note.repostedBy, mutedPubkeys.contains(r) { return false }
            if !words.isEmpty {
                let content = note.content.lowercased()
                if words.contains(where: { content.contains($0) }) { return false }
            }
            return true
        }
    }

    func refilter() {
        notes = filtered(notes)
    }

    func acceptPending() {
        let visible = filtered(fetched)
        show(visible)
        afterLoad(visible)
        scrollToTopToken &+= 1
    }

    func refresh() async {
        acceptNext = true
        exhaustedRelays = false
        switch source {
        case .explore:
            exploreHidden = ExploreSeenStore.shared.snapshot()
            _ = await TrendingService.shared.explorePool(force: true)
        case .discover(let feed): _ = await discoverNotes(feed, force: true)
        case .following:
            async let feed: Void = SyncService.shared.syncFeed(force: true)
            async let topics: Void = syncTopics(activeTopics, force: true)
            _ = await (feed, topics)
        case .list(let set): await SyncService.shared.syncListFeed(set.pubkeys, force: true)
        case .topic, .topics: await syncTopics(activeTopics, force: true)
        }
        acceptNext = true
        await reload()
        store.requestCounts(notes.prefix(40).map(\.id))
    }

    func loadMoreIfNeeded(_ note: Note) {
        ExploreSeenStore.shared.mark(note.id)
        guard canLoadMore, !isLoadingMore, let index = notes.firstIndex(where: { $0.listId == note.listId }), index >= notes.count - 6 else { return }
        Task { await loadMore() }
    }

    func loadMore() async {
        guard canLoadMore, !isLoadingMore, !source.isCurated else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let generation = self.generation
        let previousCount = fetched.count
        limit += Self.pageSize
        var result = await query(limit: limit)
        guard generation == self.generation else { return }
        if result.count <= previousCount || result.count < limit {
            let oldest = (result.isEmpty ? notes : result).map(\.displayTimestamp).filter { $0 > 0 }.min() ?? TimeFormat.now
            let received = await fetchOlder(until: oldest)
            guard generation == self.generation else { return }
            if received == 0, await SyncService.shared.hasConnectedRelays() { exhaustedRelays = true }
            result = await query(limit: limit)
            guard generation == self.generation else { return }
        }
        mergeOlder(result)
    }

    private func mergeOlder(_ result: [Note]) {
        fetched = result
        let visible = filtered(result)
        let displayedIds = Set(notes.map(\.listId))
        let additions = visible.filter { !displayedIds.contains($0.listId) && $0.displayTimestamp <= latestDisplayed }
        if sort == .mostInteracted {
            notes = visible
        } else {
            notes.append(contentsOf: additions)
        }
        canLoadMore = !(additions.isEmpty && exhaustedRelays)
        afterLoad(additions)
    }

    func select(_ source: FeedSource) {
        guard source != self.source else { return }
        self.source = source
        resetForContextChange()
        switch source {
        case .explore, .discover: break
        case .list(let set): Task { await SyncService.shared.syncListFeed(set.pubkeys) }
        case .topic, .topics: syncTopicsInBackground()
        case .following: if includeTopics { syncTopicsInBackground() }
        }
    }

    private func resetForContextChange() {
        generation += 1
        notes = []
        fetched = []
        pendingCount = 0
        limit = Self.pageSize
        latestDisplayed = 0
        acceptNext = true
        exhaustedRelays = false
        canLoadMore = true
        hasLoaded = false
        isSyncing = true
        graceTask?.cancel()
        graceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            self?.isSyncing = false
        }
        Task { await reload() }
    }

    func pinnedFeedsChanged(_ pinned: [DiscoverFeed]) {
        guard case .discover(let feed) = source, !pinned.contains(where: { $0.id == feed.id }) else { return }
        select(.explore)
    }

    func loadLists() async {
        guard let me = Session.shared.pubkey else { return }
        let own = await NoteRepository.followSets(authors: [me], limit: 100)
        let favorites = UserDefaults.standard.stringArray(forKey: "favorite_follow_set_ids") ?? []
        var result = own.filter { !$0.pubkeys.isEmpty }
        if !favorites.isEmpty {
            let follows = await NoteRepository.following()
            let others = await NoteRepository.followSets(authors: follows, limit: 500)
            for id in favorites {
                if let set = (own + others).first(where: { $0.id == id || $0.dTag == id }), !result.contains(where: { $0.id == set.id }), !set.pubkeys.isEmpty {
                    result.append(set)
                }
            }
        }
        lists = result
        if case .list(let active) = source {
            if let updated = result.first(where: { $0.id == active.id }) {
                if updated != active { source = .list(updated) }
            } else {
                select(.following)
            }
        }
    }
}
