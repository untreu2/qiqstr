import SwiftUI

struct SettingsView: View {
    @State private var session = Session.shared
    @State private var cache = ProfileCache.shared
    @State private var router = Router.shared
    @State private var notifications = LocalNotificationService.shared
    @State private var showLogout = false
    @State private var showTerms = false
    @State private var isLoggingOut = false
    @State private var copiedNpub = 0
    @AppStorage("app_language") private var language: String?
    @ScaledMetric(relativeTo: .title3) private var avatarSize: CGFloat = 58

    static let supportURL = URL(string: AuthTermsText.supportURL)!
    static let sourceURL = URL(string: "https://github.com/untreu2/qiqstr")!

    var body: some View {
        List {
            if let pubkey = session.pubkey {
                Section { accountHeader(pubkey) }
            }
            Section {
                link(.keys, L("keys"), "key.horizontal.fill", fill: AppColors.settingsTile)
                link(.relays, L("relays"), "point.3.connected.trianglepath.dotted", fill: AppColors.settingsTile)
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    SettingsRowLabel(title: L("notifications"), systemImage: "bell.badge.fill", value: notifications.isDelivering ? L("localNotifyOn") : L("localNotifyOff"), fill: AppColors.settingsTile)
                }
                .accessibilityIdentifier("settings-row-notifications")
                link(.muted, L("muted"), "bell.slash.fill", fill: AppColors.settingsTile)
                NavigationLink {
                    SafetySettingsView()
                } label: {
                    SettingsRowLabel(title: L("safetyTitle"), systemImage: "hand.raised.fill", fill: AppColors.settingsTile)
                }
                .accessibilityIdentifier("settings-row-safety")
            }
            Section {
                link(.display, L("display"), "circle.lefthalf.filled", fill: AppColors.settingsTile)
                link(.language, L("language"), "character.bubble", fill: AppColors.settingsTile, value: currentLanguageName)
                link(.payments, L("payments"), "bolt.fill", fill: AppColors.settingsTile)
            }
            Section {
                link(.database, L("databaseCache"), "internaldrive.fill", fill: AppColors.settingsTile)
                link(.eventManager, L("yourDataOnRelays"), "antenna.radiowaves.left.and.right", fill: AppColors.settingsTile)
            }
            Section {
                Button { router.sheet = .switchAccount } label: {
                    SettingsRowLabel(title: L("switchAccount"), systemImage: "person.2.fill", value: session.accounts.count > 1 ? "\(session.accounts.count)" : nil, fill: AppColors.settingsTile)
                }
                .accessibilityIdentifier("settings-switch-account")
            }
            Section {
                Button { showTerms = true } label: {
                    SettingsRowLabel(title: L("settingsTerms"), systemImage: "doc.text.fill", fill: AppColors.settingsTile)
                }
                .accessibilityIdentifier("settings-terms")
                Button { router.sheet = .url(Self.supportURL) } label: {
                    SettingsRowLabel(title: L("settingsContactSupport"), systemImage: "envelope.fill", fill: AppColors.settingsTile)
                }
                .accessibilityIdentifier("settings-contact")
                Button { router.sheet = .url(Self.sourceURL) } label: {
                    SettingsRowLabel(title: L("settingsSourceCode"), systemImage: "chevron.left.forwardslash.chevron.right", fill: AppColors.settingsTile)
                }
                .accessibilityIdentifier("settings-source")
                SettingsRowLabel(title: L("version"), systemImage: "info", value: Self.versionString, fill: AppColors.settingsTile)
                    .accessibilityIdentifier("settings-version")
            }
            Section {
                Button(role: .destructive) { showLogout = true } label: {
                    HStack(spacing: 8) {
                        Spacer()
                        Text(L("logout"))
                        if isLoggingOut { ProgressView() }
                        Spacer()
                    }
                }
                .disabled(isLoggingOut)
                .accessibilityIdentifier("settings-logout")
                .confirmationDialog(L("areYouSureLogout"), isPresented: $showLogout, titleVisibility: .visible) {
                    Button(L("logout"), role: .destructive) { logout() }
                        .accessibilityIdentifier("settings-logout-confirm")
                    Button(L("cancel"), role: .cancel) {}
                } message: {
                    Text(L("seedPhraseWarning"))
                }
            }
            if session.canSign {
                Section {
                    NavigationLink(value: Route.settingsPage(.eventManager)) {
                        Text(L("deleteAccount")).foregroundStyle(.red)
                    }
                    .accessibilityIdentifier("settings-delete-account")
                } footer: {
                    Text(L("settingsDeleteAccountFooter"))
                }
            }
        }
        .settingsListStyle()
        .navigationTitle(L("settings"))
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showTerms) { AuthTermsSheet() }
        .contentMargins(.bottom, 72, for: .scrollContent)
        .sensoryFeedback(.success, trigger: copiedNpub)
        .accessibilityIdentifier("settings-list")
    }

    private func accountHeader(_ pubkey: String) -> some View {
        let profile = cache.profile(pubkey)
        let npub = session.npub ?? ""
        return NavigationLink(value: Route.profile(pubkey)) {
            HStack(spacing: 14) {
                ProfileAvatar(pubkey: pubkey, size: min(avatarSize, 80))
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile?.givenName ?? L("anonymous"))
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    if let nip05 = profile?.nip05.nilIfEmpty {
                        Text(nip05)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(Profile.shortNpub(pubkey))
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        }
        .contextMenu {
            Button {
                SettingsClipboard.copy(npub)
                copiedNpub += 1
                ToastCenter.shared.show(L("copiedNpub"), style: .success)
            } label: { Label(L("settingsCopyNpub"), systemImage: "doc.on.doc") }
            Button { router.sheet = .shareProfile(pubkey) } label: { Label(L("settingsShareProfile"), systemImage: "qrcode") }
        }
        .accessibilityIdentifier("settings-account-header")
    }

    private func link(_ page: SettingsRoute, _ title: String, _ icon: String, fill: Color, value: String? = nil) -> some View {
        NavigationLink(value: Route.settingsPage(page)) {
            SettingsRowLabel(title: title, systemImage: icon, value: value, fill: fill)
        }
        .accessibilityIdentifier("settings-row-\(page)")
    }

    private var currentLanguageName: String {
        guard let language, let lang = AppLanguage(rawValue: language) else { return L("settingsSystemDefault") }
        return lang.displayName
    }

    private func logout() {
        isLoggingOut = true
        Task {
            await session.logout()
            isLoggingOut = false
        }
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
