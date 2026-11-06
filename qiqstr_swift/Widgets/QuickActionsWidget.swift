import SwiftUI
import WidgetKit

struct QuickActionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickActionsWidget", provider: QuickActionsProvider()) { _ in
            QuickActionsView()
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName(Text("widgetQuickActionsTitle"))
        .description(Text("widgetQuickActionsDescription"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickActionsEntry: TimelineEntry {
    let date: Date
}

struct QuickActionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickActionsEntry { QuickActionsEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (QuickActionsEntry) -> Void) {
        completion(QuickActionsEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickActionsEntry>) -> Void) {
        completion(Timeline(entries: [QuickActionsEntry(date: Date())], policy: .never))
    }
}
