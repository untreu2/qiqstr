import Foundation
import Observation

enum ExploreScope: String, CaseIterable, Identifiable {
    case following, global
    var id: String { rawValue }
    var title: String { self == .following ? L("following") : L("exploreGlobal") }
}

@MainActor
@Observable
final class ExploreViewModel {
    private(set) var articles: [Article] = []
    private(set) var isLoading = true
    private(set) var isLoadingMore = false
    private(set) var canLoadMore = false
    private(set) var hasFollows = true
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            users.query = query
        }
    }
    let users: UserSearchModel = {
        let model = UserSearchModel()
        model.resultLimit = 6
        return model
    }()

    var scope: ExploreScope {
        didSet {
            guard scope != oldValue else { return }
            UserDefaults.standard.set(scope.rawValue, forKey: Self.scopeKey)
            Task { await start() }
        }
    }

    private var limit = ArticleService.pageSize
    private var authors: [String]?
    private var generation = 0
    private var remoteExhausted = false
    private static let scopeKey = "explore_scope"

    init() {
        scope = ExploreScope(rawValue: UserDefaults.standard.string(forKey: Self.scopeKey) ?? "") ?? .following
    }

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    var visibleArticles: [Article] {
        let q = trimmedQuery
        guard !q.isEmpty else { return articles }
        let cache = ProfileCache.shared
        return articles.filter { article in
            article.title.lowercased().contains(q)
                || (article.summary ?? "").lowercased().contains(q)
                || (article.authorName ?? "").lowercased().contains(q)
                || (cache.profile(article.pubkey)?.bestName.lowercased().contains(q) ?? false)
                || article.hashtags.contains { $0.lowercased().contains(q) }
                || article.content.lowercased().contains(q)
        }
    }

    func start() async {
        generation += 1
        let current = generation
        limit = ArticleService.pageSize
        remoteExhausted = false
        articles = []
        isLoading = true
        await resolveAuthors()
        guard current == generation else { return }
        await reload()
        if !articles.isEmpty { isLoading = false }
        await ArticleService.sync(authors: authors, force: false)
        guard current == generation else { return }
        await reload()
        isLoading = false
    }

    func refresh() async {
        let current = generation
        await resolveAuthors()
        guard current == generation else { return }
        await ArticleService.sync(authors: authors, force: true)
        guard current == generation else { return }
        remoteExhausted = false
        await reload()
        isLoading = false
    }

    func reload() async {
        let current = generation
        if scope == .following, authors?.isEmpty ?? true {
            articles = []
            canLoadMore = false
            return
        }
        let loaded = await ArticleService.articles(authors: authors, limit: limit)
        guard current == generation else { return }
        articles = loaded
        canLoadMore = loaded.count >= limit || !remoteExhausted
        Task { await ProfileCache.shared.load(Array(Set(loaded.map(\.pubkey)))) }
    }

    func loadMore() async {
        guard !isLoadingMore, canLoadMore, trimmedQuery.isEmpty else { return }
        let current = generation
        isLoadingMore = true
        defer { if current == generation { isLoadingMore = false } }
        let previous = articles.count
        limit += ArticleService.pageSize
        await reload()
        guard current == generation else { return }
        if articles.count <= previous {
            let oldest = articles.map(\.createdAt).min() ?? TimeFormat.now
            let fetched = await ArticleService.fetchOlder(authors: authors, until: oldest)
            guard current == generation else { return }
            if fetched == 0 { remoteExhausted = true }
            await reload()
            if articles.count <= previous { canLoadMore = false }
        }
    }

    private func resolveAuthors() async {
        switch scope {
        case .global:
            authors = nil
            hasFollows = true
        case .following:
            guard let me = Session.shared.pubkey else { authors = []; return }
            let follows = await SyncService.shared.followingList(me)
            hasFollows = !follows.isEmpty
            authors = Array(Set(follows + [me]))
        }
    }
}
