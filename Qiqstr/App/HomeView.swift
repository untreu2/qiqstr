import SwiftUI

struct HomeView: View {
    @State private var router = Router.shared
    @State private var badge = NotificationBadge.shared

    var body: some View {
        TabView(selection: tabSelection) {
            Tab(value: AppTab.feed) {
                NavigationStack(path: router.binding(.feed)) { FeedView().withRoutes() }
            } label: {
                Image(systemName: "house").accessibilityLabel(L("home"))
            }
            .accessibilityIdentifier("tab-feed")
            Tab(value: AppTab.dm) {
                NavigationStack(path: router.binding(.dm)) { DMConversationsView().withRoutes() }
            } label: {
                Image(systemName: "message").accessibilityLabel(L("messages"))
            }
            .badge(badge.hasUnreadMessages ? Text("") : nil)
            Tab(value: AppTab.wallet) {
                NavigationStack(path: router.binding(.wallet)) { WalletView().withRoutes() }
            } label: {
                Image(systemName: "bolt").accessibilityLabel(L("wallet"))
            }
            Tab(value: AppTab.notifications) {
                NavigationStack(path: router.binding(.notifications)) { NotificationsView().withRoutes() }
            } label: {
                Image(systemName: "bell").accessibilityLabel(L("notifications"))
            }
            .badge(badge.hasUnreadNotifications ? Text("") : nil)
            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: router.binding(.search)) { SearchView().withRoutes() }
            } label: {
                Image(systemName: "magnifyingglass").accessibilityLabel(L("search"))
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $router.isComposing) {
            ComposeView(context: router.composeContext ?? .newNote)
        }
        .sheet(isPresented: $router.showSidebar) {
            SidebarView()
        }
        .sheet(item: $router.sheet) { sheet in
            AppSheetView(sheet: sheet)
        }
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { router.selectedTab },
            set: { tab in
                if tab == .compose {
                    router.compose()
                } else {
                    if tab == router.selectedTab { router.popToRoot(tab) }
                    router.selectedTab = tab
                    if tab == .notifications { badge.markRead() }
                }
            }
        )
    }
}

struct AppSheetView: View {
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        case .zap(let note): ZapSheet(target: .note(note))
        case .zapProfile(let pubkey): ZapSheet(target: .profile(pubkey))
        case .switchAccount: SwitchAccountSheet()
        case .shareProfile(let pubkey): ShareProfileSheet(pubkey: pubkey)
        case .url(let url): SafariView(url: url).ignoresSafeArea()
        }
    }
}
