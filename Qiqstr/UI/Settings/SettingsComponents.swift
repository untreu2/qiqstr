import SwiftUI
import UIKit

struct SettingsIcon: View {
    let systemImage: String
    var tint: Color = AppColors.textPrimary
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 29

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(AppColors.tile, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
}

struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = AppColors.textPrimary
    var value: String? = nil

    var body: some View {
        if let value {
            LabeledContent {
                Text(value).lineLimit(1)
            } label: {
                label
            }
        } else {
            label
        }
    }

    private var label: some View {
        Label {
            Text(title).foregroundStyle(tint)
        } icon: {
            SettingsIcon(systemImage: systemImage, tint: tint)
        }
    }
}

enum SettingsClipboard {
    static func copy(_ text: String, sensitive: Bool = false) {
        if sensitive {
            UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: text]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
        } else {
            UIPasteboard.general.string = text
        }
    }
}

enum SettingsByteFormat {
    static func string(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }
}

extension View {
    func settingsListStyle() -> some View {
        self
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
    }
}
