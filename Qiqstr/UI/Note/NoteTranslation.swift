import NaturalLanguage
import SwiftUI
import Translation

@MainActor
enum NoteLanguage {
    private static var detected: [String: String] = [:]
    private static let undetermined = ""

    static var appLanguage: String {
        let code = UserDefaults.standard.string(forKey: "app_language") ?? Locale.preferredLanguages.first ?? "en"
        return baseCode(code)
    }

    static func language(of note: Note) -> String? {
        if let hit = detected[note.id] { return hit == undetermined ? nil : hit }
        let code = detect(NoteContentCache.content(for: note).translatableText)
        detected[note.id] = code ?? undetermined
        if detected.count > 3000 { detected.removeAll(keepingCapacity: true) }
        return code
    }

    static func needsTranslation(_ note: Note) -> Bool {
        guard let code = language(of: note) else { return false }
        return code != appLanguage
    }

    static func text(for note: Note) -> String {
        NoteContentCache.content(for: note).translatableText
    }

    private static func detect(_ text: String) -> String? {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= 12 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first, confidence >= 0.6, language != .undetermined else { return nil }
        return baseCode(language.rawValue)
    }

    private static func baseCode(_ identifier: String) -> String {
        String(identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? Substring(identifier)).lowercased()
    }
}

struct NoteTranslateButton: View {
    let note: Note
    @State private var presented = false

    var body: some View {
        if NoteLanguage.needsTranslation(note) {
            Button {
                presented = true
            } label: {
                Label(L("feedTranslatePost"), systemImage: "translate")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColors.link)
            }
            .buttonStyle(.plain)
            .translationPresentation(isPresented: $presented, text: NoteLanguage.text(for: note))
            .accessibilityIdentifier("thread-translate")
        }
    }
}
