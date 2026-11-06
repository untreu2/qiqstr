import Foundation
import SwiftUI

nonisolated enum AppLanguage: String, CaseIterable, Identifiable {
    case en, tr, de
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .en: "English"
        case .tr: "Türkçe"
        case .de: "Deutsch"
        }
    }
}

nonisolated final class Localizer: @unchecked Sendable {
    static let shared = Localizer()
    private let lock = NSLock()
    private var bundle: Bundle = .main

    private init() {
        apply(UserDefaults.standard.string(forKey: "app_language"))
    }

    func apply(_ code: String?) {
        lock.lock(); defer { lock.unlock() }
        let preferred = code ?? Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        let lang = AppLanguage(rawValue: preferred)?.rawValue ?? "en"
        if let path = Bundle.main.path(forResource: lang, ofType: "lproj"), let b = Bundle(path: path) {
            bundle = b
        } else {
            bundle = .main
        }
    }

    private static let tables = ["Localizable", "Auth", "Feed", "Profile", "Explore", "DM", "Wallet", "Settings"]

    func string(_ key: String) -> String {
        lock.lock(); defer { lock.unlock() }
        if let value = lookup(key, in: bundle) { return value }
        if let path = Bundle.main.path(forResource: "en", ofType: "lproj"), let en = Bundle(path: path), let value = lookup(key, in: en) {
            return value
        }
        return key
    }

    private func lookup(_ key: String, in bundle: Bundle) -> String? {
        for table in Self.tables {
            let value = bundle.localizedString(forKey: key, value: "\u{0}", table: table)
            if value != "\u{0}" { return value }
        }
        return nil
    }
}

nonisolated func L(_ key: String, _ args: [String: CustomStringConvertible] = [:]) -> String {
    var s = Localizer.shared.string(key)
    for (name, value) in args {
        s = s.replacingOccurrences(of: "{\(name)}", with: value.description)
    }
    return s
}
