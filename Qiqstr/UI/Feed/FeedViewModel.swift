import Foundation
import Observation

enum FeedSource: Hashable {
    case following
    case list(FeedFollowSet)

    var id: String {
        switch self {
        case .following: "following"
        case .list(let set): set.id
        }
    }

    var title: String {
        switch self {
        case .following: L("all")
        case .list(let set): set.title
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
    private(set) var source: FeedSource = .following
    private(set) var scrollToTopToken = 0
    var sort: FeedSortMode {
        didSet {
            guard sort != oldValue else { return }
            UserDefaults.standard.set(sort.rawValue, forKey: "feed_sort_mode")
            resetForContextChange()
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
    }

    private var authors: [String]? {
        if case .list(let set) = source { return set.pubkeys }
        return nil
    }

    func start() {
        guard graceTask == nil else { return }
        if Session.shared.isNewAccount { isSyncing = false }
        graceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.isSyncing = false
        }
    }

    func reload() async {
        let generation = self.generation
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled, generation == self.generation else { return }
        let result = await NoteRepository.feed(authors: authors, limit: limit, sort: sort)
        guard generation == self.generation else { return }
        apply(result)
    }

    private func apply(_ result: [Note]) {
        fetched = result
        let visible = filtered(result)
        let me = Session.shared.pubkey
        if notes.isEmpty || acceptNext {
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
        canLoadMore = !exhaustedRelays || result.count >= limit
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
        switch source {
        case .following: await SyncService.shared.syncFeed(force: true)
        case .list(let set): await SyncService.shared.syncListFeed(set.pubkeys, force: true)
        }
        acceptNext = true
        await reload()
        store.requestCounts(notes.prefix(40).map(\.id))
    }

    func loadMoreIfNeeded(_ note: Note) {
        guard canLoadMore, !isLoadingMore, let index = notes.firstIndex(where: { $0.listId == note.listId }), index >= notes.count - 6 else { return }
        Task { await loadMore() }
    }

    func loadMore() async {
        guard canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let generation = self.generation
        let previousCount = fetched.count
        limit += Self.pageSize
        var result = await NoteRepository.feed(authors: authors, limit: limit, sort: sort)
        guard generation == self.generation else { return }
        if result.count <= previousCount || result.count < limit {
            let oldest = (result.isEmpty ? notes : result).map(\.createdAt).filter { $0 > 0 }.min() ?? TimeFormat.now
            var pubkeys = authors ?? []
            if pubkeys.isEmpty, let me = Session.shared.pubkey { pubkeys = Array(Set(await NoteRepository.following() + [me])) }
            let received = await NoteRepository.fetchOlder(authors: pubkeys, until: oldest)
            guard generation == self.generation else { return }
            if received == 0 { exhaustedRelays = true }
            result = await NoteRepository.feed(authors: authors, limit: limit, sort: sort)
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
        if case .list(let set) = source {
            Task { await SyncService.shared.syncListFeed(set.pubkeys) }
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
