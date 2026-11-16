import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import UniformTypeIdentifiers

struct AuthHeader: View {
    let title: String
    var subtitle: String? = nil
    var titleSize: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom("Poppins-SemiBold", size: titleSize, relativeTo: .largeTitle))
                .foregroundStyle(.primary)
                .kerning(-titleSize * 0.02)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
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
                .font(.body)
                .foregroundStyle(.primary)
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
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.red)
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
    /// The language's name in the app's current language, such as "German" or "Almanca".
    var localizedName: String {
        let name = AppLanguage.current.locale.localizedString(forIdentifier: rawValue) ?? displayName
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    var locale: Locale { Locale(identifier: rawValue) }

    static var current: AppLanguage {
        let code = UserDefaults.standard.string(forKey: "app_language") ?? Locale.preferredLanguages.first ?? "en"
        return AppLanguage.matching(code) ?? .en
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
