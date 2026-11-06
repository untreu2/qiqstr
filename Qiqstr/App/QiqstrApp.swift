import SwiftUI

@main
struct QiqstrApp: App {
    @State private var session = Session.shared
    @AppStorage("theme_preference") private var theme = ThemePreference.system.rawValue
    @AppStorage("app_language") private var language: String?

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(ThemePreference(rawValue: theme)?.colorScheme)
                .tint(AppColors.textPrimary)
                .toastOverlay()
                .id(language ?? "system")
                .task { await session.launch() }
                .onOpenURL { Router.shared.open(url: $0) }
        }
    }
}

struct RootView: View {
    @State private var session = Session.shared

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            switch session.phase {
            case .launching, .starting:
                SplashView()
            case .signedOut:
                AuthFlowView()
            case .ready:
                HomeView().id(session.account?.npub).onboardingGate()
            case .failed(let message):
                EmptyStateView(systemImage: "exclamationmark.triangle", title: L("errorLoadingProfile"), message: message, actionTitle: L("retry")) {
                    Task { await session.launch() }
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: session.phase)
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image("Logo").resizable().renderingMode(.template).scaledToFit().frame(width: 140).foregroundStyle(AppColors.textPrimary)
            ProgressView().opacity(0.6)
        }
        .accessibilityIdentifier("splash")
    }
}
