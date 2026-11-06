import Foundation
import Observation

enum SearchScope: String, CaseIterable, Identifiable {
    case top, people, notes, hashtags, articles
    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: L("searchScopeTop")
        case .people: L("searchScopePeople")
        case .notes: L("searchScopeNotes")
        case .hashtags: L("searchScopeHashtags")
        case .articles: L("searchScopeArticles")
        }
    }
}

struct HashtagMatch: Identifiable, Hashable {
    let tag: String
    var count: Int
    var id: String { tag }
}

@MainActor
@Observable
final class SearchViewModel {
    var query = "" { didSet { if query != oldValue { schedule() } } }
    var scope: SearchScope = .top

    private(set) var people: [Profile] = []
    private(set) var notes: [Note] = []
    private(set) var articles: [Article] = []
    private(set) var resolvedHex: String?
    private(set) var pending: Set<SearchKind> = []
    private(set) var isSearchingLocal = false
    private(set) var remoteFailed = false
    private(set) var hasSearched = false
    private(set) var opened = 0

    private(set) var recents: [String] = []
    private(set) var suggestions: [Profile] = []
    private(set) var trendingNotes: [Note] = []
    private(set) var trendingHashtags: [String] = []
    private(set) var isLoadingTrending = false
    private(set) var trendingFailed = false

    static let peopleLimit = 40
    static let notesLimit = 60
    static let articlesLimit = 30
    private static let remoteLimit = 25

    private var task: Task<Void, Never>?
    private var generation = 0
    private var failures: [SearchKind: Int] = [:]
    private var started = false

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isSearching: Bool { isSearchingLocal || !pending.isEmpty }
    var queryHashtag: String? { SearchService.hashtag(from: trimmedQuery) }

    var hashtags: [HashtagMatch] {
        var counts: [String: Int] = [:]
        let needle = trimmedQuery.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !needle.isEmpty else { return [] }
        for note in notes {
            for tag in Set(note.hashtags.map { $0.lowercased() }) where tag.contains(needle) && SearchService.hashtag(from: tag) == tag {
                counts[tag, default: 0] += 1
            }
        }
        for article in articles {
            for tag in Set(article.hashtags.map { $0.lowercased() }) where tag.contains(needle) && SearchService.hashtag(from: tag) == tag {
                counts[tag, default: 0] += 1
            }
        }
        for tag in trendingHashtags where tag.contains(needle) && counts[tag] == nil { counts[tag] = 0 }
        var matches = counts.map { HashtagMatch(tag: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.tag.hasPrefix(needle) != rhs.tag.hasPrefix(needle) { return lhs.tag.hasPrefix(needle) }
                return lhs.count == rhs.count ? lhs.tag < rhs.tag : lhs.count > rhs.count
            }
        if let exact = queryHashtag {
            let current = matches.first { $0.tag == exact } ?? HashtagMatch(tag: exact, count: 0)
            matches.removeAll { $0.tag == exact }
            matches.insert(current, at: 0)
        }
        return Array(matches.prefix(30))
    }

    var showsEmptyResults: Bool {
        guard hasSearched, !isSearching, !trimmedQuery.isEmpty, resolvedHex == nil else { return false }
        switch scope {
        case .top: return people.isEmpty && notes.isEmpty && articles.isEmpty && hashtags.isEmpty
        case .people: return people.isEmpty
        case .notes: return notes.isEmpty
        case .hashtags: return hashtags.isEmpty
        case .articles: return articles.isEmpty
        }
    }

    func start() async {
        recents = RecentSearchStore.load()
        guard !started else { return }
        started = true
        async let suggested: Void = loadSuggestions()
        async let trending: Void = loadTrending(force: false)
        _ = await (suggested, trending)
    }

    func refresh() async {
        if trimmedQuery.isEmpty {
            suggestions = await UserSearchService.suggestions(limit: 25)
            await loadTrending(force: true)
        } else {
            schedule(debounce: false)
            await task?.value
        }
    }

    func submit() {
        let text = trimmedQuery
        guard !text.isEmpty else { return }
        if let url = SearchService.entityURL(from: text) {
            open(url)
            return
        }
        if let hex = resolvedHex {
            opened += 1
            Router.shared.push(.profile(hex))
            return
        }
        remember()
    }

    func remember(_ term: String? = nil) {
        recents = RecentSearchStore.add(term ?? trimmedQuery)
    }

    func useRecent(_ term: String) {
        query = term
        remember(term)
    }

    func removeRecent(_ term: String) {
        recents = RecentSearchStore.remove(term)
    }

    func clearRecents() {
        RecentSearchStore.clear()
        recents = []
    }

    func loadTrending(force: Bool) async {
        let service = TrendingService.shared
        if trendingNotes.isEmpty { isLoadingTrending = true }
        defer { isLoadingTrending = false }
        async let ids = service.trendingNoteIds(force: force)
        async let tags = service.trendingHashtags(force: force)
        let noteIds = await ids
        let loaded = await service.hydratedNotes(noteIds)
        if !loaded.isEmpty || force { trendingNotes = loaded }
        trendingFailed = trendingNotes.isEmpty
        if trendingHashtags.isEmpty { trendingHashtags = TrendingService.hashtags(from: trendingNotes) }
        Task { await ProfileCache.shared.load(Array(Set(loaded.map(\.pubkey)))) }
        let remoteTags = await tags
        if !remoteTags.isEmpty { trendingHashtags = remoteTags }
    }

    private func loadSuggestions() async {
        guard suggestions.isEmpty else { return }
        suggestions = await UserSearchService.suggestions(limit: 25)
    }

    private func open(_ url: URL) {
        opened += 1
        Router.shared.open(url: url)
    }

    private func schedule(debounce: Bool = true) {
        task?.cancel()
        generation += 1
        let current = generation
        let text = trimmedQuery
        failures = [:]
        remoteFailed = false
        guard !text.isEmpty else {
            reset()
            return
        }
        if let url = SearchService.entityURL(from: text) {
            reset()
            open(url)
            return
        }
        if let hex = SearchService.hexId(from: text) {
            reset()
            resolvedHex = hex
            hasSearched = true
            return
        }
        resolvedHex = nil
        isSearchingLocal = true
        pending = Set(SearchKind.allCases)
        task = Task { [weak self] in
            if debounce { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            await self?.run(text, generation: current)
        }
    }

    private func reset() {
        people = []
        notes = []
        articles = []
        resolvedHex = nil
        pending = []
        isSearchingLocal = false
        hasSearched = false
    }

    private func isCurrent(_ generation: Int) -> Bool { generation == self.generation && !Task.isCancelled }

    private func run(_ text: String, generation: Int) async {
        let context = SearchContext.current
        async let localPeople = SearchService.localProfiles(text, limit: Self.peopleLimit, context: context)
        async let localNotes = SearchService.localNotes(text, limit: Self.notesLimit, context: context)
        async let localArticles = SearchService.localArticles(text, limit: Self.articlesLimit, context: context)
        let (foundPeople, foundNotes, foundArticles) = await (localPeople, localNotes, localArticles)
        guard isCurrent(generation) else { return }
        people = foundPeople
        notes = foundNotes
        articles = foundArticles
        isSearchingLocal = false
        hasSearched = true
        Task { await ProfileCache.shared.load(Array(Set(foundNotes.map(\.pubkey) + foundArticles.map(\.pubkey)))) }

        await withTaskGroup(of: Void.self) { group in
            for kind in SearchKind.allCases {
                group.addTask { await self.runRemote(kind, text: text, context: context, generation: generation) }
            }
        }
    }

    private func runRemote(_ kind: SearchKind, text: String, context: SearchContext, generation: Int) async {
        for await batch in SearchService.remote(kind, query: text, limit: Self.remoteLimit) {
            guard isCurrent(generation) else { return }
            if batch.failed { failures[kind, default: 0] += 1 }
            guard !batch.events.isEmpty else { continue }
            await merge(kind, events: batch.events, context: context, generation: generation)
        }
        guard generation == self.generation else { return }
        pending.remove(kind)
        updateRemoteFailure()
    }

    private func merge(_ kind: SearchKind, events: [JSONObject], context: SearchContext, generation: Int) async {
        await SearchService.store(events)
        guard isCurrent(generation) else { return }
        switch kind {
        case .people:
            let found = SearchService.profiles(from: events, context: context)
            let cache = ProfileCache.shared
            for profile in found where cache.profile(profile.pubkey) == nil { cache.set(profile) }
            var seen = Set(people.map(\.pubkey))
            people = Array((people + found.filter { seen.insert($0.pubkey).inserted }).prefix(Self.peopleLimit))
        case .notes:
            let known = Set(notes.map(\.id))
            let ids = events.compactMap { $0.str("id") }.filter { !known.contains($0) }
            let hydrated = await SearchService.notes(ids: ids, context: context)
            guard isCurrent(generation) else { return }
            var seen = Set(notes.map(\.id))
            notes = Array((notes + hydrated.filter { seen.insert($0.id).inserted }).prefix(Self.notesLimit))
            SyncService.shared.fetchMissingProfiles(SearchService.pubkeys(in: events))
            Task { await ProfileCache.shared.load(Array(Set(hydrated.map(\.pubkey)))) }
        case .articles:
            let hydrated = await SearchService.articles(from: events)
            guard isCurrent(generation) else { return }
            var seen = Set(articles.map { "\($0.pubkey):\($0.dTag)" })
            articles = Array((articles + hydrated.filter { seen.insert("\($0.pubkey):\($0.dTag)").inserted }).prefix(Self.articlesLimit))
            SyncService.shared.fetchMissingProfiles(SearchService.pubkeys(in: events))
        }
    }

    private func updateRemoteFailure() {
        guard pending.isEmpty else { return }
        remoteFailed = SearchKind.allCases.allSatisfy { (failures[$0] ?? 0) >= $0.relays.count }
    }
}
