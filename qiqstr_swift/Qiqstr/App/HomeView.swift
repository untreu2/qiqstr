import SwiftUI

struct HomeView: View {
    @State private var router = Router.shared
    @State private var badge = NotificationBadge.shared
    @State private var session = Session.shared
    @State private var clipboard = ClipboardLinkWatcher.shared
    @Environment(\.scenePhase) private var scenePhase

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
        .tabBarMinimizeBehavior(router.isTabBarMinimizable ? .onScrollDown : .never)
        .sheet(isPresented: $router.isComposing) {
            ComposeView(context: router.composeContext ?? .newNote)
        }
        .sheet(isPresented: $router.showSidebar) {
            SidebarView()
        }
        .sheet(item: sheetSelection) { sheet in
            AppSheetView(sheet: sheet)
        }
        .onChange(of: router.sheet?.id) {
            guard let sheet = router.sheet, sheet.requiresSigner, !session.canSign else { return }
            router.sheet = nil
            ReadOnlyGate.shared.present()
        }
        .overlay(alignment: .top) { ClipboardLinkBanner() }
        .readOnlyGate()
        .zapRetryToast()
        .task {
            router.openPendingLink()
            SharedInbox.shared.check()
            await clipboard.becameActive()
        }
        .onOpenURL(perform: openDeepLink)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                SharedInbox.shared.check()
                Task { await clipboard.becameActive() }
            case .background: clipboard.enteredBackground()
            default: break
            }
        }
    }

    private func openDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "qiqstr" else { return }
        switch url.host()?.lowercased() {
        case "compose":
            SharedInbox.shared.handle(url)
        case "search":
            router.selectedTab = .search
        case "messages":
            router.selectedTab = .dm
        case "notifications":
            router.selectedTab = .notifications
            badge.markRead()
            WidgetBridge.markRead()
        default:
            break
        }
    }

    private var sheetSelection: Binding<AppSheet?> {
        Binding(
            get: {
                guard let sheet = router.sheet, !sheet.requiresSigner || session.canSign else { return nil }
                return sheet
            },
            set: { router.sheet = $0 }
        )
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
                    if tab == .notifications {
                        badge.markRead()
                        WidgetBridge.markRead()
                    }
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
