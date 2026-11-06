import Foundation
import WidgetKit

enum WidgetBridge {
    static let appGroup = "group.me.untreu.qiqstrswift"
    static let unreadKey = "widget_unread_count"
    static let latestNameKey = "widget_latest_name"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func update(unread: Int, latestName: String?) {
        guard let defaults else { return }
        let count = max(0, unread)
        let name = latestName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = name?.isEmpty == false ? name : nil
        guard defaults.object(forKey: unreadKey) as? Int != count || defaults.string(forKey: latestNameKey) != normalized else { return }
        defaults.set(count, forKey: unreadKey)
        defaults.set(normalized, forKey: latestNameKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func markRead() {
        update(unread: 0, latestName: defaults?.string(forKey: latestNameKey))
    }

    static func clear() {
        update(unread: 0, latestName: nil)
    }
}
