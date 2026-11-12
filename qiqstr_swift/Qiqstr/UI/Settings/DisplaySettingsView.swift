import SwiftUI

extension ThemePreference {
    var title: String {
        switch self {
        case .system: L("settingsSystemDefault")
        case .light: L("lightMode")
        case .dark: L("darkMode")
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

struct DisplaySettingsView: View {
    @AppStorage("theme_preference") private var theme = ThemePreference.system.rawValue
    @AppStorage("expanded_note_mode") private var expandedNotes = false
    @AppStorage("app_language") private var language: String?

    var body: some View {
        Form {
            Section {
                Picker(L("settingsAppearance"), selection: $theme) {
                    ForEach(ThemePreference.allCases) { option in
                        Label(option.title, systemImage: option.symbol)
                            .tag(option.rawValue)
                            .accessibilityIdentifier("display-theme-\(option.rawValue)")
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text(L("settingsAppearance"))
            } footer: {
                Text(L("displaySubtitle"))
            }
            Section {
                Toggle(isOn: $expandedNotes) {
                    SettingsRowLabel(title: L("expandedNotes"), systemImage: "rectangle.expand.vertical")
                }
                .tint(AppColors.switchActive)
                .accessibilityIdentifier("display-expanded-notes")
            } footer: {
                Text(L("settingsExpandedNotesFooter"))
            }
            Section {
                NavigationLink(value: Route.settingsPage(.language)) {
                    SettingsRowLabel(title: L("language"), systemImage: "character.bubble", value: language.flatMap { AppLanguage(rawValue: $0)?.displayName } ?? L("settingsSystemDefault"))
                }
                .accessibilityIdentifier("display-language")
            }
        }
        .settingsListStyle()
        .navigationTitle(L("displayTitle"))
        .navigationBarTitleDisplayMode(.large)
        .sensoryFeedback(.selection, trigger: theme)
        .sensoryFeedback(.selection, trigger: expandedNotes)
    }
}

struct LanguageSettingsView: View {
    @AppStorage("app_language") private var language: String?

    var body: some View {
        Form {
            Section {
                Picker(L("language"), selection: Binding(get: { language ?? "" }, set: { apply($0.isEmpty ? nil : $0) })) {
                    Text(L("settingsSystemDefault"))
                        .tag("")
                        .accessibilityIdentifier("language-system")
                    ForEach(AppLanguage.allCases) { lang in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.displayName)
                            Text(localizedName(lang))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .tag(lang.rawValue)
                        .accessibilityIdentifier("language-\(lang.rawValue)")
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .settingsListStyle()
        .navigationTitle(L("language"))
        .navigationBarTitleDisplayMode(.large)
        .sensoryFeedback(.selection, trigger: language)
    }

    private func apply(_ code: String?) {
        Localizer.shared.apply(code)
        language = code
    }

    private func localizedName(_ lang: AppLanguage) -> String {
        switch lang {
        case .en: L("english")
        case .tr: L("turkish")
        case .de: L("german")
        }
    }
}
