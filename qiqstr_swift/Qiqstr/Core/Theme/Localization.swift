import Foundation
import SwiftUI

nonisolated enum AppLanguage: String, CaseIterable, Identifiable {
    case en, tr, de, es
    case ptBR = "pt-BR"
    case fr, it, nl, pl
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .en: "English"
        case .tr: "Türkçe"
        case .de: "Deutsch"
        case .es: "Español"
        case .ptBR: "Português (Brasil)"
        case .fr: "Français"
        case .it: "Italiano"
        case .nl: "Nederlands"
        case .pl: "Polski"
        }
    }

    /// The app language for a code such as "pt-PT", "es-MX" or "fr", matching on the language part.
    static func matching(_ code: String) -> AppLanguage? {
        if let exact = AppLanguage(rawValue: code) { return exact }
        let base = String(code.prefix { $0 != "-" && $0 != "_" }).lowercased()
        return base == "pt" ? .ptBR : AppLanguage(rawValue: base)
    }

    static var locale: Locale {
        if let code = UserDefaults.standard.string(forKey: "app_language") { return Locale(identifier: code) }
        return .current
    }
}

nonisolated final class Localizer: @unchecked Sendable {
    static let shared = Localizer()
    private let lock = NSLock()
    private var bundle: Bundle = .main
    private var activeCode = "en"

    /// The language the UI is showing, such as "pl" or "pt-BR".
    var languageCode: String {
        lock.lock(); defer { lock.unlock() }
        return activeCode
    }

    private init() {
        apply(UserDefaults.standard.string(forKey: "app_language"))
    }

    func apply(_ code: String?) {
        lock.lock(); defer { lock.unlock() }
        let preferred = code ?? Locale.preferredLanguages.first ?? "en"
        let lang = AppLanguage.matching(preferred)?.rawValue ?? "en"
        activeCode = lang
        if let path = Bundle.main.path(forResource: lang, ofType: "lproj"), let b = Bundle(path: path) {
            bundle = b
        } else {
            bundle = .main
        }
    }

    #if os(macOS)
    private static let tables = ["Mac", "Localizable", "Auth", "Feed", "Profile", "Explore", "DM", "Wallet", "Settings"]
    #else
    private static let tables = ["Localizable", "Auth", "Feed", "Profile", "Explore", "DM", "Wallet", "Settings"]
    #endif

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
    var s = ICUPlural.resolve(Localizer.shared.string(key), args: args)
    for (name, value) in args {
        s = s.replacingOccurrences(of: "{\(name)}", with: value.description)
    }
    return s
}

nonisolated enum ICUPlural {
    static func resolve(_ template: String, args: [String: CustomStringConvertible]) -> String {
        var result = template
        while let range = result.range(of: #"\{(\w+), plural,"#, options: .regularExpression) {
            let name = String(result[range].dropFirst().prefix { $0 != "," })
            guard let end = matchingBrace(in: result, from: range.lowerBound) else { break }
            let body = String(result[range.upperBound..<end])
            let count = Int(args[name]?.description ?? "") ?? 0
            let choices = parseChoices(body)
            let chosen = choices["=\(count)"] ?? choices[category(count, language: Localizer.shared.languageCode)] ?? choices["other"] ?? ""
            result.replaceSubrange(range.lowerBound...end, with: chosen.replacingOccurrences(of: "#", with: "\(count)"))
        }
        return result
    }

    /// The CLDR plural category of a whole number in the app's languages.
    static func category(_ n: Int, language: String) -> String {
        switch language {
        case "pl":
            if n == 1 { return "one" }
            let (tens, hundreds) = (n % 10, n % 100)
            return (2...4).contains(tens) && !(12...14).contains(hundreds) ? "few" : "many"
        case "fr", "pt-BR":
            return n == 0 || n == 1 ? "one" : "other"
        default:
            return n == 1 ? "one" : "other"
        }
    }

    private static func matchingBrace(in s: String, from start: String.Index) -> String.Index? {
        var depth = 0
        var i = start
        while i < s.endIndex {
            if s[i] == "{" { depth += 1 }
            if s[i] == "}" { depth -= 1; if depth == 0 { return i } }
            i = s.index(after: i)
        }
        return nil
    }

    private static func parseChoices(_ body: String) -> [String: String] {
        var choices: [String: String] = [:]
        var i = body.startIndex
        while i < body.endIndex {
            while i < body.endIndex, body[i].isWhitespace { i = body.index(after: i) }
            let keyStart = i
            while i < body.endIndex, body[i] != "{" { i = body.index(after: i) }
            guard i < body.endIndex, let close = matchingBrace(in: body, from: i) else { break }
            let key = body[keyStart..<i].trimmingCharacters(in: .whitespaces)
            choices[key] = String(body[body.index(after: i)..<close])
            i = body.index(after: close)
        }
        return choices
    }
}
