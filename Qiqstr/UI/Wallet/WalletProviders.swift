import SwiftUI

struct WalletProvider: Identifiable, Hashable {
    let id: String
    let name: String
    let detailKey: String
    let systemImage: String
    var connectScheme: String? = nil
    let fallback: URL

    var supportsOneTap: Bool { connectScheme != nil }
    var opensInBrowser: Bool { fallback.host()?.contains("apple.com") == false }

    static let appIcon = "https://raw.githubusercontent.com/untreu2/qiqstr/master/assets/main_icon_uni.png"

    static let all: [WalletProvider] = [
        WalletProvider(id: "primal", name: "Primal", detailKey: "walletProviderPrimal", systemImage: "bolt.circle", connectScheme: "nostrnwc+primal", fallback: URL(string: "https://apps.apple.com/app/id1673134518")!),
        WalletProvider(id: "alby-go", name: "Alby Go", detailKey: "walletProviderAlbyGo", systemImage: "iphone.gen3", connectScheme: "nostrnwc+alby", fallback: URL(string: "https://apps.apple.com/app/id6471335774")!),
        WalletProvider(id: "alby-hub", name: "Alby Hub", detailKey: "walletProviderAlbyHub", systemImage: "server.rack", fallback: URL(string: "https://getalby.com/alby-hub")!),
        WalletProvider(id: "coinos", name: "Coinos", detailKey: "walletProviderCoinos", systemImage: "globe", fallback: URL(string: "https://coinos.io")!),
        WalletProvider(id: "minibits", name: "Minibits", detailKey: "walletProviderMinibits", systemImage: "banknote", fallback: URL(string: "https://apps.apple.com/app/id6744454479")!),
        WalletProvider(id: "zeus", name: "ZEUS", detailKey: "walletProviderZeus", systemImage: "bolt.horizontal.circle", fallback: URL(string: "https://apps.apple.com/app/id1456038895")!),
    ]

    static var oneTap: [WalletProvider] { all.filter(\.supportsOneTap) }

    var connectURL: URL? {
        guard let connectScheme else { return nil }
        var comps = URLComponents()
        comps.scheme = connectScheme
        comps.host = "connect"
        comps.queryItems = [
            URLQueryItem(name: "appname", value: "qiqstr"),
            URLQueryItem(name: "appicon", value: Self.appIcon),
            URLQueryItem(name: "callback", value: WalletService.callbackURL),
        ]
        comps.percentEncodedQuery = comps.percentEncodedQuery?
            .replacingOccurrences(of: ":", with: "%3A")
            .replacingOccurrences(of: "/", with: "%2F")
        return comps.url
    }

    func open() {
        if let connectURL {
            UIApplication.shared.open(connectURL) { opened in
                if !opened { openFallback() }
            }
        } else {
            openFallback()
        }
    }

    private func openFallback() {
        if opensInBrowser {
            Router.shared.sheet = .url(fallback)
        } else {
            UIApplication.shared.open(fallback)
        }
    }
}

struct WalletProviderRow: View {
    let provider: WalletProvider

    var body: some View {
        Button(action: provider.open) {
            LabeledContent {
                HStack(spacing: 8) {
                    if provider.supportsOneTap {
                        Text(L("walletOneTap"))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.fill.tertiary, in: Capsule())
                    }
                    Image(systemName: "arrow.up.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.name).foregroundStyle(AppColors.textPrimary)
                        Text(L(provider.detailKey))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    SettingsIcon(systemImage: provider.systemImage)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(provider.supportsOneTap ? L("walletProviderOneTapHint") : L("walletProviderOpenHint"))
        .accessibilityIdentifier("wallet-provider-\(provider.id)")
    }
}
