import Foundation

enum WidgetStore {
    static let appGroup = "group.me.untreu.qiqstrswift"
    static let unreadKey = "widget_unread_count"
    static let latestNameKey = "widget_latest_name"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func snapshot() -> NotificationsEntry {
        let defaults = defaults
        let name = defaults?.string(forKey: latestNameKey)
        return NotificationsEntry(
            date: Date(),
            unread: max(0, defaults?.integer(forKey: unreadKey) ?? 0),
            latestName: name?.isEmpty == false ? name : nil
        )
    }
}
