import AppKit
import SwiftUI

@main
struct QiqstrMacApp: App {
    @NSApplicationDelegateAdaptor private var delegate: MacAppDelegate
    @State private var session = Session.shared
    @AppStorage("theme_preference") private var theme = ThemePreference.system.rawValue
    @AppStorage("app_language") private var language: String?

    init() {
        Perf.start()
        LocalNotificationService.shared.activate()
        DiagnosticsStore.shared.activate()
    }

    var body: some Scene {
        Window("qiqstr", id: "main") {
            RootView()
                .frame(minWidth: 900, minHeight: 620)
                .preferredColorScheme(ThemePreference(rawValue: theme)?.colorScheme)
                .tint(AppColors.textPrimary)
                .toastOverlay()
                .environment(\.locale, AppLanguage.locale)
                .id(language ?? "system")
                .task { await BackgroundRefresh.launchSession() }
                .onOpenURL { url in
                    if !WalletService.shared.handleIncoming(url: url) { Router.shared.open(url: url) }
                }
        }
        .defaultSize(width: 1180, height: 820)
        .windowToolbarStyle(.unified)
        .commands { QiqstrCommands() }
    }
}

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    static let sheetMinimum = NSSize(width: 540, height: 480)
    private var observer: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow, window.sheetParent != nil, window.contentMinSize != Self.sheetMinimum,
                  !(window is NSPanel), String(describing: type(of: window.contentView ?? NSView())).contains("Hosting") else { return }
            MainActor.assumeIsolated { Self.sizeSheet(window) }
        }
    }

    private static func sizeSheet(_ window: NSWindow) {
        window.contentMinSize = sheetMinimum
        let size = window.contentLayoutRect.size
        if size.width < sheetMinimum.width || size.height < sheetMinimum.height {
            window.setContentSize(NSSize(width: max(size.width, sheetMinimum.width), height: max(size.height, sheetMinimum.height)))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidResignActive(_ notification: Notification) {
        LocalNotificationService.shared.enteredBackground()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await LocalNotificationService.shared.refreshStatus() }
    }
}

struct QiqstrCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("newPost")) { if ready { Router.shared.compose() } }
                .keyboardShortcut("n")
        }
        CommandGroup(replacing: .appSettings) {
            Button(L("settings") + "…") { if ready { Router.shared.popToRoot(.settings); Router.shared.selectedTab = .settings } }
                .keyboardShortcut(",")
        }
        CommandMenu(L("macGoMenu")) {
            go(.feed, L("home"), "1")
            go(.dm, L("messages"), "2")
            go(.notifications, L("notifications"), "3")
            go(.search, L("search"), "4")
            go(.wallet, L("wallet"), "5")
            Divider()
            go(.profile, L("profile"), "6")
            go(.bookmarks, L("bookmarks"), "7")
            Divider()
            Button(L("switchAccount")) { if ready { Router.shared.sheet = .switchAccount } }
                .keyboardShortcut("a", modifiers: [.command, .shift])
        }
    }

    private func go(_ tab: AppTab, _ title: String, _ key: KeyEquivalent) -> some View {
        Button(title) {
            guard ready else { return }
            Router.shared.popToRoot(tab)
            Router.shared.selectedTab = tab
        }
        .keyboardShortcut(key)
    }

    private var ready: Bool { Session.shared.phase == .ready }
}
