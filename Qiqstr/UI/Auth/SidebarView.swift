import QiqstrCore
import SwiftUI

@MainActor
@Observable
final class SidebarViewModel {
    private(set) var followerCount: Int?
    private(set) var followingCount: Int?
    private(set) var relayCount: Int?

    func loadProfile() async {
        guard let me = Session.shared.pubkey else { return }
        await ProfileCache.shared.refresh(me)
        await SyncService.shared.syncProfile(me)
        await ProfileCache.shared.refresh(me)
    }

    func loadFollowing() async {
        guard let me = Session.shared.pubkey else { return }
        let list = await SyncService.shared.followingList(me)
        followingCount = Set(list.filter { $0 != me }).count
    }

    func loadFollowers() async {
        guard let me = Session.shared.pubkey else { return }
        guard let raw = try? await fetchFollowerCounts(pubkeyHexes: [me]), let map = JSON.object(raw) else {
            if followerCount == nil { followerCount = 0 }
            return
        }
        followerCount = map.int(me)
    }

    func loadRelays() async {
        relayCount = (try? await getConnectedRelayCount()).map(Int.init)
    }

    func refresh() async {
        async let profile: Void = loadProfile()
        async let following: Void = loadFollowing()
        async let followers: Void = loadFollowers()
        async let relays: Void = loadRelays()
        _ = await (profile, following, followers, relays)
    }
}

struct SidebarView: View {
    @State private var model = SidebarViewModel()
    @State private var session = Session.shared
    @State private var cache = ProfileCache.shared
    @State private var bus = DataBus.shared
    @State private var router = Router.shared
    @AppStorage("theme_preference") private var theme = ThemePreference.system.rawValue

    private var me: String { session.pubkey ?? "" }
    private var profile: Profile? { cache.profile(me) }

    var body: some View {
        NavigationStack {
            List {
                Section { header }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
                Section {
                    row(L("profile"), systemImage: "person", identifier: "sidebar-profile") { open(.profile(me)) }
                    row(L("reads"), systemImage: "doc.text", identifier: "sidebar-reads") { open(.explore) }
                    row(L("listsTitle"), systemImage: "list.bullet", identifier: "sidebar-lists") { open(.followSets) }
                    row(L("bookmarks"), systemImage: "bookmark", identifier: "sidebar-bookmarks") { open(.bookmarks) }
                }
                Section {
                    row(L("switchAccount"), systemImage: "person.2", identifier: "sidebar-switch-account", trailing: accountsBadge) { openSwitchAccount() }
                    row(L("settings"), systemImage: "gearshape", identifier: "sidebar-settings") { open(.settings) }
                }
                Section {
                    themePicker
                } header: {
                    Text(L("authAppearance"))
                } footer: {
                    if let relays = model.relayCount {
                        Label(L("authConnectedRelays", ["count": relays]), systemImage: relays > 0 ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.top, 4)
                            .accessibilityIdentifier("sidebar-relay-count")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { router.showSidebar = false }
                        .accessibilityIdentifier("sidebar-close")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppColors.background)
        .task { await model.refresh() }
        .task(id: bus.feedVersion) { await model.loadFollowing() }
        .task(id: bus.profileVersion) { await cache.refresh(me) }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await model.loadRelays()
            }
        }
        .sensoryFeedback(.selection, trigger: theme)
        .accessibilityIdentifier("sidebar")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button { open(.profile(me)) } label: {
                HStack(spacing: 16) {
                    ProfileAvatar(pubkey: me, size: 60)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile?.bestName.nilIfEmpty ?? L("anonymous"))
                            .font(.system(size: 22, weight: .bold))
                            .kerning(-0.3)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                        if let nip05 = profile?.nip05.nilIfEmpty {
                            Label(nip05, systemImage: "checkmark.seal")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)
                        }
                        Text(Profile.shortNpub(me))
                            .font(.system(size: 13))
                            .kerning(0.3)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sidebar-header")
            .contextMenu {
                if let npub = session.npub {
                    Button {
                        UIPasteboard.general.string = npub
                        ToastCenter.shared.show(L("copiedNpub"), style: .success)
                    } label: {
                        Label(L("copy"), systemImage: "doc.on.doc")
                    }
                }
            }
            HStack(spacing: 18) {
                countButton(model.followingCount, label: L("followingCount"), identifier: "sidebar-following-count") { open(.followList(me, .following)) }
                countButton(model.followerCount, label: L(model.followerCount == 1 ? "followerSingular" : "followers"), identifier: "sidebar-followers-count") { open(.followList(me, .followers)) }
                Spacer(minLength: 0)
            }
        }
    }

    private func countButton(_ value: Int?, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let value {
                    Text(value.formatted(.number.notation(.compactName)))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .contentTransition(.numericText())
                } else {
                    ProgressView().controlSize(.mini)
                }
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: value)
        .accessibilityIdentifier(identifier)
    }

    private var accountsBadge: String? {
        session.accounts.count > 1 ? "\(session.accounts.count)" : nil
    }

    private func row(_ title: String, systemImage: String, identifier: String, trailing: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                IconTile(systemImage: systemImage, size: 34)
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.textSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary.opacity(0.6))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var themePicker: some View {
        Picker(L("authAppearance"), selection: $theme) {
            Text(L("authThemeSystem")).tag(ThemePreference.system.rawValue)
            Text(L("authThemeLight")).tag(ThemePreference.light.rawValue)
            Text(L("authThemeDark")).tag(ThemePreference.dark.rawValue)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("sidebar-theme")
    }

    private func open(_ route: Route) {
        guard !me.isEmpty else { return }
        router.showSidebar = false
        router.push(route)
    }

    private func openSwitchAccount() {
        router.showSidebar = false
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            router.sheet = .switchAccount
        }
    }
}
