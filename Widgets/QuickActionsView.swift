import AppIntents
import SwiftUI
import WidgetKit

struct QuickActionsView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(spacing: 6) {
            ForEach(QuickAction.allCases) { action in
                Button(intent: OpenURLIntent(action.url)) {
                    Label(action.title, systemImage: action.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.primary)
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 10) {
            ForEach(QuickAction.allCases) { action in
                Link(destination: action.url) {
                    VStack(spacing: 8) {
                        Image(systemName: action.systemImage)
                            .font(.title2.weight(.semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.fill.tertiary, in: .rect(cornerRadius: 18))
                            .widgetAccentable()
                        Text(action.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .foregroundStyle(.primary)
    }
}
