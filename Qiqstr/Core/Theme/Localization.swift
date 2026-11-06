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

    func string(_ key: String) -> String {
        lock.lock(); defer { lock.unlock() }
        let value = bundle.localizedString(forKey: key, value: "\u{0}", table: nil)
        if value != "\u{0}" { return value }
        if let path = Bundle.main.path(forResource: "en", ofType: "lproj"), let en = Bundle(path: path) {
            return en.localizedString(forKey: key, value: key, table: nil)
        }
        return key
    }
}

nonisolated func L(_ key: String, _ args: [String: CustomStringConvertible] = [:]) -> String {
    var s = Localizer.shared.string(key)
    for (name, value) in args {
        s = s.replacingOccurrences(of: "{\(name)}", with: value.description)
    }
    return s
}
