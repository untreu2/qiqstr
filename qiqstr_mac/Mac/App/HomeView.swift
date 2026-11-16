import SwiftUI

struct HomeView: View {
    @State private var router = Router.shared
    @State private var badge = NotificationBadge.shared
    @State private var session = Session.shared
    @State private var cache = ProfileCache.shared
    @State private var feedModel = FeedViewModel()
    @State private var sidebarRefresh = 0

    private var me: String { session.pubkey ?? "" }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            NavigationStack(path: path(for: router.selectedTab)) {
                root(for: router.selectedTab)
                    .readableWidth()
                    .navigationDestination(for: Route.self) { RouteDestination(route: $0).readableWidth() }
            }
            .id(router.selectedTab)
            .frame(minWidth: 520)
            .background(AppColors.background)
        }
        .sheet(isPresented: $router.isComposing) {
            ComposeView(context: router.composeContext ?? .newNote)
                .frame(minWidth: 560, minHeight: 420)
        }
        .onChange(of: router.showSidebar) { _, shows in
            guard shows else { return }
            router.showSidebar = false
            router.selectedTab = .profile
        }
        .sheet(item: sheetSelection) { sheet in
            AppSheetView(sheet: sheet).frame(minWidth: 480, minHeight: 520)
        }
        .onChange(of: router.sheet?.id) {
            guard let sheet = router.sheet, sheet.requiresSigner, !session.canSign else { return }
            router.sheet = nil
            ReadOnlyGate.shared.present()
        }
        .onChange(of: router.selectedTab) { _, tab in
            if tab == .notifications {
                badge.markRead()
                WidgetBridge.markRead()
            }
        }
        .menuIndicator(.hidden)
        .readOnlyGate()
        .zapRetryToast()
        .task {
            NoteInteractionStore.shared.prepareForAccount()
            router.openPendingLink()
        }
    }

    private var sidebar: some View {
        List(selection: tabSelection) {
            Section {
                item(.feed, L("home"), "house")
                item(.dm, L("messages"), "message", unread: badge.hasUnreadMessages)
                item(.notifications, L("notifications"), "bell", unread: badge.hasUnreadNotifications)
                item(.search, L("search"), "magnifyingglass")
                item(.wallet, L("wallet"), "bolt")
            }
            Section(L("macLibrary")) {
                item(.profile, L("profile"), "person")
                item(.reads, L("reads"), "doc.text")
                item(.live, L("liveTitle"), "dot.radiowaves.left.and.right")
                item(.lists, L("listsTitle"), "list.bullet")
                item(.bookmarks, L("bookmarks"), "bookmark")
                item(.settings, L("settings"), "gearshape")
            }
        }
        .listStyle(.sidebar)
        .id(sidebarRefresh)
        .safeAreaInset(edge: .bottom) { accountBar }
    }

    private func item(_ tab: AppTab, _ title: String, _ icon: String, unread: Bool = false) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                if unread { Circle().fill(AppColors.accent).frame(width: 8, height: 8) }
            }
        } icon: {
            Image(systemName: icon)
        }
        .tag(tab)
        .accessibilityIdentifier("sidebar-\(String(describing: tab))")
    }

    private func path(for tab: AppTab) -> Binding<NavigationPath> {
        Binding(
            get: { router.paths[tab] ?? NavigationPath() },
            set: { if router.selectedTab == tab { router.paths[tab] = $0 } }
        )
    }

    private var tabSelection: Binding<AppTab?> {
        Binding(
            get: { router.selectedTab },
            set: { tab in
                // Clicking the selected row deselects it on macOS. Treat that as a
                // reselect: pop to the section's root and rebuild the list so the row
                // stays highlighted.
                guard let tab else {
                    router.popToRoot(router.selectedTab)
                    sidebarRefresh += 1
                    return
                }
                if tab == router.selectedTab { router.popToRoot(tab) }
                router.selectedTab = tab
            }
        )
    }

    private var accountBar: some View {
        HStack(spacing: 10) {
            Button { router.sheet = .switchAccount } label: {
                HStack(spacing: 10) {
                    AvatarView(url: cache.profile(me)?.picture, size: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(cache.profile(me)?.bestName ?? L("anonymous")).font(.callout.weight(.semibold)).lineLimit(1)
                        Text(L("switchAccount")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sidebar-switch-account")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func root(for tab: AppTab) -> some View {
        switch tab {
        case .feed, .compose: FeedView(model: feedModel)
        case .dm: DMConversationsView()
        case .wallet: WalletView()
        case .notifications: NotificationsView()
        case .search: SearchView()
        case .profile: ProfileView(pubkey: me)
        case .reads: ExploreView()
        case .live: LiveListView()
        case .lists: FollowSetsView()
        case .bookmarks: BookmarksView()
        case .settings: SettingsView()
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
}

struct AppSheetView: View {
    let sheet: AppSheet
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch sheet {
        case .zap(let note): ZapSheet(target: .note(note))
        case .zapProfile(let pubkey): ZapSheet(target: .profile(pubkey))
        case .switchAccount: SwitchAccountSheet()
        case .shareProfile(let pubkey): ShareProfileSheet(pubkey: pubkey)
        case .url(let url):
            Color.clear.onAppear {
                NSWorkspace.shared.open(url)
                dismiss()
            }
        }
    }
}

extension View {
    func readableWidth() -> some View {
        frame(maxWidth: 760).frame(maxWidth: .infinity)
    }
}


