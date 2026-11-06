import SwiftUI

enum FollowListMode: String, Hashable { case following, followers }

enum SettingsRoute: Hashable { case keys, relays, muted, display, database, eventManager, payments, language }

enum Route: Hashable {
    case profile(String)
    case thread(String)
    case quotes(String)
    case noteStatistics(String)
    case followList(String, FollowListMode)
    case hashtag(String)
    case explore
    case article(String)
    case articleAddress(String)
    case editProfile
    case settings
    case settingsPage(SettingsRoute)
    case bookmarks
    case followSets
    case followSet(String)
    case dmChat(String)
    case walletReceive
    case userSearch
    case suggestedFollows
    case liveStreams
    case liveStream(String)
}

struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .profile(let pubkey): ProfileView(pubkey: pubkey)
        case .thread(let id): ThreadView(noteId: id)
        case .quotes(let id): QuotesView(noteId: id)
        case .noteStatistics(let id): NoteStatisticsView(noteId: id)
        case .followList(let pubkey, let mode): FollowListView(pubkey: pubkey, mode: mode)
        case .hashtag(let tag): HashtagFeedView(tag: tag)
        case .explore: ExploreView()
        case .article(let id): ArticleDetailView(articleId: id)
        case .articleAddress(let naddr): ArticleDetailView(naddr: naddr)
        case .editProfile: EditProfileView()
        case .settings: SettingsView()
        case .settingsPage(let page): SettingsPageView(page: page)
        case .bookmarks: BookmarksView()
        case .followSets: FollowSetsView()
        case .followSet(let id): FollowSetDetailView(setId: id)
        case .dmChat(let pubkey): DMChatView(pubkey: pubkey)
        case .walletReceive: ReceiveView()
        case .userSearch: UserSearchView()
        case .suggestedFollows: SuggestedFollowsView(onFinish: nil)
        case .liveStreams: LiveListView()
        case .liveStream(let coordinate): LiveStreamView(coordinate: coordinate)
        }
    }
}

extension View {
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { RouteDestination(route: $0) }
    }
}

@MainActor
@Observable
final class Router {
    static let shared = Router()
    var selectedTab: AppTab = .feed
    var paths: [AppTab: NavigationPath] = [.feed: NavigationPath(), .dm: NavigationPath(), .wallet: NavigationPath(), .notifications: NavigationPath(), .search: NavigationPath()]
    var isComposing = false
    var composeContext: ComposeContext?
    var showSidebar = false
    var sheet: AppSheet?
    @ObservationIgnored private var pendingLink: NostrLink?

    func push(_ route: Route) {
        paths[selectedTab, default: NavigationPath()].append(route)
    }

    func popToRoot(_ tab: AppTab) { paths[tab] = NavigationPath() }

    func binding(_ tab: AppTab) -> Binding<NavigationPath> {
        Binding(get: { self.paths[tab] ?? NavigationPath() }, set: { self.paths[tab] = $0 })
    }

    func compose(_ context: ComposeContext = .newNote) {
        guard ReadOnlyGate.check() else { return }
        composeContext = context
        isComposing = true
    }

    func reset() {
        for key in paths.keys { paths[key] = NavigationPath() }
        selectedTab = .feed
        isComposing = false
        showSidebar = false
        sheet = nil
    }

    func open(url: URL) {
        if let link = NostrLink(url: url) ?? NostrLink(entity: url.absoluteString) {
            open(link)
        } else if let scheme = url.scheme?.lowercased(), scheme != "nostr", scheme != "qiqstr" {
            UIApplication.shared.open(url)
        }
    }

    func open(_ link: NostrLink) {
        guard Session.shared.phase == .ready else {
            pendingLink = link
            return
        }
        NostrLinkResolver.open(link, router: self)
    }

    func openPendingLink() {
        guard let link = pendingLink, Session.shared.phase == .ready else { return }
        pendingLink = nil
        NostrLinkResolver.open(link, router: self)
    }
}

enum AppTab: Hashable { case feed, dm, wallet, notifications, search, compose }

enum AppSheet: Identifiable {
    case zap(Note)
    case zapProfile(String)
    case switchAccount
    case shareProfile(String)
    case url(URL)
    var requiresSigner: Bool {
        switch self {
        case .zap, .zapProfile: true
        default: false
        }
    }

    var id: String {
        switch self {
        case .zap(let n): "zap-\(n.id)"
        case .zapProfile(let p): "zapp-\(p)"
        case .switchAccount: "switch"
        case .shareProfile(let p): "share-\(p)"
        case .url(let u): u.absoluteString
        }
    }
}

enum ComposeContext: Identifiable, Hashable {
    case newNote
    case reply(Note)
    case quote(Note)
    var id: String {
        switch self {
        case .newNote: "new"
        case .reply(let n): "reply-\(n.id)"
        case .quote(let n): "quote-\(n.id)"
        }
    }
}
