import SwiftUI
import WidgetKit

struct NotificationsView: View {
    let entry: NotificationsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("widgetNotificationsTitle", systemImage: entry.unread > 0 ? "bell.badge" : "bell")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(entry.unread, format: .number)
                .font(.largeTitle.weight(.semibold))
                .contentTransition(.numericText())
                .widgetAccentable()
            Text(entry.unread > 0 ? "widgetUnread" : "widgetNoNew")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let name = entry.latestName {
                Text("widgetLatestFrom \(name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "bell")
                    .font(.caption)
                Text(entry.unread, format: .number)
                    .font(.title3.weight(.semibold))
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("widgetUnreadCount \(entry.unread)"))
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("qiqstr", systemImage: "bell")
                .font(.headline)
                .widgetAccentable()
            Text(entry.unread > 0 ? "widgetUnreadCount \(entry.unread)" : "widgetNoNew")
                .font(.subheadline)
            if let name = entry.latestName, entry.unread > 0 {
                Text("widgetLatestFrom \(name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
