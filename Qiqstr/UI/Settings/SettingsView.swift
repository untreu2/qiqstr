import SwiftUI

struct SettingsView: View {
    @State private var session = Session.shared
    @State private var cache = ProfileCache.shared
    @State private var router = Router.shared
    @State private var showLogout = false
    @State private var isLoggingOut = false
    @State private var copiedNpub = 0
    @AppStorage("app_language") private var language: String?

    static let termsURL = URL(string: "https://github.com/untreu2/qiqstr/blob/master/TERMS.md")!
    static let sourceURL = URL(string: "https://github.com/untreu2/qiqstr")!

    var body: some View {
        List {
            if let pubkey = session.pubkey {
                Section { accountHeader(pubkey) }
            }
            Section {
                link(.keys, L("keys"), "key.horizontal")
                link(.relays, L("relays"), "point.3.connected.trianglepath.dotted")
                link(.muted, L("muted"), "bell.slash")
            }
            Section {
                link(.display, L("display"), "circle.lefthalf.filled")
                link(.language, L("language"), "character.bubble", value: currentLanguageName)
                link(.payments, L("payments"), "bolt")
            }
            Section {
                link(.database, L("databaseCache"), "internaldrive")
                link(.eventManager, L("yourDataOnRelays"), "antenna.radiowaves.left.and.right")
            }
            Section {
                Button { router.sheet = .switchAccount } label: {
                    SettingsRowLabel(title: L("switchAccount"), systemImage: "person.2", value: session.accounts.count > 1 ? "\(session.accounts.count)" : nil)
                }
                .accessibilityIdentifier("settings-switch-account")
            }
            Section {
                Button { router.sheet = .url(Self.termsURL) } label: {
                    SettingsRowLabel(title: L("settingsTerms"), systemImage: "doc.text")
                }
                .accessibilityIdentifier("settings-terms")
                Button { router.sheet = .url(Self.sourceURL) } label: {
                    SettingsRowLabel(title: L("settingsSourceCode"), systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .accessibilityIdentifier("settings-source")
                SettingsRowLabel(title: L("version"), systemImage: "info.circle", value: Self.versionString)
                    .accessibilityIdentifier("settings-version")
            }
            Section {
                Button(role: .destructive) { showLogout = true } label: {
                    HStack {
                        SettingsRowLabel(title: L("logout"), systemImage: "rectangle.portrait.and.arrow.right", tint: AppColors.error)
                        if isLoggingOut { ProgressView() }
                    }
                }
                .disabled(isLoggingOut)
                .accessibilityIdentifier("settings-logout")
            } footer: {
                Text(L("settingsSubtitle"))
            }
        }
        .settingsListStyle()
        .navigationTitle(L("settings"))
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    SettingsLanguagePicker()
                } label: {
                    Image(systemName: "translate")
                }
                .accessibilityLabel(L("language"))
                .accessibilityIdentifier("settings-language-menu")
            }
        }
        .confirmationDialog(L("areYouSureLogout"), isPresented: $showLogout, titleVisibility: .visible) {
            Button(L("logout"), role: .destructive) { logout() }
                .accessibilityIdentifier("settings-logout-confirm")
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(L("seedPhraseWarning"))
        }
        .sensoryFeedback(.success, trigger: copiedNpub)
        .accessibilityIdentifier("settings-list")
    }

    private func accountHeader(_ pubkey: String) -> some View {
        let profile = cache.profile(pubkey)
        let npub = session.npub ?? ""
        return NavigationLink(value: Route.profile(pubkey)) {
            HStack(spacing: 14) {
                ProfileAvatar(pubkey: pubkey, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile?.bestName ?? Profile.shortNpub(pubkey))
                        .font(AppFont.brandSemibold(19))
                        .lineLimit(1)
                    if let nip05 = profile?.nip05.nilIfEmpty {
                        Text(nip05)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                    Text(Profile.shortNpub(pubkey))
                        .font(.system(size: 13).monospaced())
                        .foregroundStyle(AppColors.textSecondary)
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

    private func link(_ page: SettingsRoute, _ title: String, _ icon: String, value: String? = nil) -> some View {
        NavigationLink(value: Route.settingsPage(page)) {
            SettingsRowLabel(title: title, systemImage: icon, value: value)
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

struct SettingsLanguagePicker: View {
    @AppStorage("app_language") private var language: String?

    var body: some View {
        Picker(L("language"), selection: Binding(get: { language ?? "" }, set: { apply($0.isEmpty ? nil : $0) })) {
            Text(L("settingsSystemDefault")).tag("")
            ForEach(AppLanguage.allCases) { lang in
                Text(lang.displayName).tag(lang.rawValue)
            }
        }
    }

    private func apply(_ code: String?) {
        Localizer.shared.apply(code)
        language = code
    }
}
