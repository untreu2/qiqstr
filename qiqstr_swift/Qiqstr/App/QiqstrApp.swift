import SwiftUI

@main
struct QiqstrApp: App {
    @State private var session = Session.shared
    @AppStorage("theme_preference") private var theme = ThemePreference.system.rawValue
    @AppStorage("app_language") private var language: String?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Perf.start()
        LocalNotificationService.shared.activate()
        DiagnosticsStore.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(ThemePreference(rawValue: theme)?.colorScheme)
                .tint(AppColors.textPrimary)
                .toastOverlay()
                .environment(\.locale, AppLanguage.locale)
                .id(language ?? "system")
                .task { await BackgroundRefresh.launchSession() }
                .onOpenURL { url in
                    if !WalletService.shared.handleIncoming(url: url) { Router.shared.open(url: url) }
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { Router.shared.open(url: url) }
                }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: LocalNotificationService.shared.enteredBackground()
            case .active: Task { await LocalNotificationService.shared.refreshStatus() }
            default: break
            }
        }
    }
}
