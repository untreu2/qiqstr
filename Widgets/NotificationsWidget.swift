import SwiftUI
import WidgetKit

struct NotificationsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NotificationsWidget", provider: NotificationsProvider()) { entry in
            NotificationsView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
                .widgetURL(DeepLink.notifications)
        }
        .configurationDisplayName(Text("widgetNotificationsTitle"))
        .description(Text("widgetNotificationsDescription"))
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct NotificationsProvider: TimelineProvider {
    func placeholder(in context: Context) -> NotificationsEntry {
        NotificationsEntry(date: Date(), unread: 3, latestName: "satoshi")
    }

    func getSnapshot(in context: Context, completion: @escaping (NotificationsEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : WidgetStore.snapshot())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NotificationsEntry>) -> Void) {
        completion(Timeline(entries: [WidgetStore.snapshot()], policy: .never))
    }
}
