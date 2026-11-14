import SwiftUI

struct RootView: View {
    @State private var session = Session.shared
    @State private var badge = NotificationBadge.shared
    @State private var router = Router.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            switch session.phase {
            case .launching, .starting:
                SplashView()
            case .signedOut:
                AuthFlowView()
            case .ready:
                HomeView().id(session.account?.npub).onboardingGate().notificationPrompt()
            case .failed(let message):
                VStack(spacing: 12) {
                    EmptyStateView(systemImage: "exclamationmark.triangle", title: L("errorLoadingProfile"), message: message, actionTitle: L("retry")) {
                        Task { await session.launch() }
                    }
                    Button(L("launchResetCache")) { Task { await session.recoverFromLaunchFailure() } }
                        .secondaryGlassStyle()
                        .accessibilityIdentifier("launch-reset-cache")
                    Button(L("logout"), role: .destructive) { Task { await session.logout() } }
                        .accessibilityIdentifier("launch-logout")
                }
                .padding(.bottom, 32)
            }
        }
        .animation(.smooth(duration: 0.3), value: session.phase)
        .task(id: session.phase) {
            guard session.phase == .ready else { return }
            await LocalNotificationService.shared.sessionReady()
        }
        .onChange(of: badge.hasUnreadNotifications) { _, unread in
            if !unread { LocalNotificationService.shared.clearBadge() }
        }
        .onChange(of: badge.hasUnreadMessages) { _, unread in
            if !unread { LocalNotificationService.shared.clearMessages() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, session.phase == .ready, router.selectedTab == .notifications else { return }
            badge.markRead()
            LocalNotificationService.shared.clearBadge()
        }
    }
}

struct SplashView: View {
    var body: some View {
        ProgressView()
            .accessibilityIdentifier("splash")
    }
}
