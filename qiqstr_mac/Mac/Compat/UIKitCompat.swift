import AppKit
import SwiftUI
import UniformTypeIdentifiers

typealias UIImage = NSImage
typealias UIColor = NSColor

nonisolated extension NSImage {
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    var scale: CGFloat {
        guard let cg = cgImage, size.width > 0 else { return 1 }
        return CGFloat(cg.width) / size.width
    }

    var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    func pngData() -> Data? {
        guard let cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}

nonisolated extension NSColor {
    static var link: NSColor { .linkColor }
    static var label: NSColor { .labelColor }
    static var secondaryLabel: NSColor { .secondaryLabelColor }
    static var systemBackground: NSColor { .windowBackgroundColor }
    static var secondarySystemBackground: NSColor { .controlBackgroundColor }
    static var systemGroupedBackground: NSColor { .windowBackgroundColor }
    static var secondarySystemGroupedBackground: NSColor { .controlBackgroundColor }
    static var tertiarySystemFill: NSColor { .quaternaryLabelColor }
    static var systemFill: NSColor { .tertiaryLabelColor }
    static var separator: NSColor { .separatorColor }
}

extension Image {
    init(uiImage: NSImage) { self.init(nsImage: uiImage) }
}

extension Color {
    init(uiColor: NSColor) { self.init(nsColor: uiColor) }
}

@MainActor
final class UIPasteboard {
    static let general = UIPasteboard()
    static let changedNotification = Notification.Name("MacPasteboardChanged")
    static let typeAutomatic = "public.utf8-plain-text"

    nonisolated struct OptionsKey: Hashable {
        let raw: String
        static let localOnly = OptionsKey(raw: "localOnly")
        static let expirationDate = OptionsKey(raw: "expirationDate")
    }

    var changeCount: Int { NSPasteboard.general.changeCount }
    var hasURLs: Bool { url != nil }
    var url: URL? {
        get { NSPasteboard.general.readObjects(forClasses: [NSURL.self])?.first as? URL }
        set {
            NSPasteboard.general.clearContents()
            if let newValue { NSPasteboard.general.writeObjects([newValue as NSURL]) }
        }
    }

    var string: String? {
        get { NSPasteboard.general.string(forType: .string) }
        set {
            NSPasteboard.general.clearContents()
            if let newValue { NSPasteboard.general.setString(newValue, forType: .string) }
        }
    }

    var image: NSImage? {
        get { NSImage(pasteboard: NSPasteboard.general) }
        set {
            NSPasteboard.general.clearContents()
            if let newValue { NSPasteboard.general.writeObjects([newValue]) }
        }
    }

    var hasStrings: Bool { NSPasteboard.general.string(forType: .string) != nil }
    var hasImages: Bool { NSPasteboard.general.canReadObject(forClasses: [NSImage.self]) }

    func setItems(_ items: [[String: Any]], options: [OptionsKey: Any] = [:]) {
        NSPasteboard.general.clearContents()
        for item in items {
            for (_, value) in item {
                if let text = value as? String { NSPasteboard.general.setString(text, forType: .string) }
            }
        }
    }
}

@MainActor
final class UIApplication {
    enum State { case active, inactive, background }
    enum BackgroundRefreshStatus { case available, denied, restricted }

    static let shared = UIApplication()
    static let openSettingsURLString = "x-apple.systempreferences:com.apple.preference.security"
    static let openNotificationSettingsURLString = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"

    var applicationState: State { NSApp?.isActive == true ? .active : .background }
    var backgroundRefreshStatus: BackgroundRefreshStatus { .available }

    func open(_ url: URL, options: [String: Any] = [:], completionHandler: ((Bool) -> Void)? = nil) {
        let opened = NSWorkspace.shared.open(url)
        completionHandler?(opened)
    }

    func canOpenURL(_ url: URL) -> Bool { NSWorkspace.shared.urlForApplication(toOpen: url) != nil }
}

@MainActor
final class UINotificationFeedbackGenerator {
    enum FeedbackType { case success, warning, error }
    func notificationOccurred(_ type: FeedbackType) {}
    func prepare() {}
}

@MainActor
final class UIImpactFeedbackGenerator {
    enum FeedbackStyle { case light, medium, heavy, soft, rigid }
    init(style: FeedbackStyle = .medium) {}
    func impactOccurred() {}
    func prepare() {}
}

final class BGAppRefreshTaskRequest {
    let identifier: String
    var earliestBeginDate: Date?
    init(identifier: String) { self.identifier = identifier }
}

final class BGTaskScheduler: @unchecked Sendable {
    static let shared = BGTaskScheduler()
    func submit(_ request: BGAppRefreshTaskRequest) throws {}
    func cancel(taskRequestWithIdentifier identifier: String) {}
}
