import WidgetKit

struct NotificationsEntry: TimelineEntry {
    let date: Date
    let unread: Int
    let latestName: String?
}
