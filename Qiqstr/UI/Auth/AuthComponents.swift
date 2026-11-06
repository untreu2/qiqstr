import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AuthHeader: View {
    let title: String
    var subtitle: String? = nil
    var titleSize: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppFont.brand(titleSize))
                .foregroundStyle(AppColors.textPrimary)
                .kerning(-titleSize * 0.02)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AuthFeatureRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemImage: systemImage, size: 40)
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(AppColors.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AuthErrorText: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(message).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(AppColors.error)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityIdentifier("auth-error")
    }
}

enum SecureClipboard {
    static func copy(_ value: String) {
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: value]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)]
        )
    }
}

extension AppLanguage {
    var localizedName: String {
        switch self {
        case .en: L("english")
        case .tr: L("turkish")
        case .de: L("german")
        }
    }

    static var current: AppLanguage {
        let stored = UserDefaults.standard.string(forKey: "app_language")
        let code = stored ?? Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        return AppLanguage(rawValue: code) ?? .en
    }
}

enum SuggestedUsers {
    static let pubkeys = [
        "ded3db39158474a8d1dfeb3400e5f1c206f89d1c94d579c18eb2a79a9502043e",
        "fa90c095c6eca1fd3813beb3cfb054836cfa217d949d29a893ad20523123e2ac",
        "5ffb8e1b6b629c0e34a013f9298ebb0759b98a3d24029916321d5eb4255b6735",
        "3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24",
        "6e468422dfb74a5738702a8823b9b28168abab8655faacb6853cd0ee15deee93",
        "c4eabae1be3cf657bc1855ee05e69de9f059cb7a059227168b80b89761cbc4e0",
    ]
}
