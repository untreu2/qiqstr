import SwiftUI
import UIKit

struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = AppColors.textPrimary
    var value: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemImage: systemImage, size: 32, tint: tint)
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SettingsPageHeader: View {
    let subtitle: String

    var body: some View {
        Text(subtitle)
            .font(.system(size: 15))
            .foregroundStyle(AppColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
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
