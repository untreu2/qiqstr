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
        List {
            SettingsPageHeader(subtitle: L("displaySubtitle"))
            Section(L("settingsAppearance")) {
                HStack(spacing: 10) {
                    ForEach(ThemePreference.allCases) { option in
                        themeCard(option)
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            }
            Section {
                Toggle(isOn: $expandedNotes) {
                    SettingsRowLabel(title: expandedNotes ? L("expandedNotes") : L("normalNotes"), systemImage: expandedNotes ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                }
                .tint(AppColors.switchActive)
                .accessibilityIdentifier("display-expanded-notes")
            } footer: {
                Text(L("settingsExpandedNotesFooter"))
            }
            Section(L("language")) {
                NavigationLink(value: Route.settingsPage(.language)) {
                    SettingsRowLabel(title: L("language"), systemImage: "character.bubble", value: language.flatMap { AppLanguage(rawValue: $0)?.displayName } ?? L("settingsSystemDefault"))
                }
                .accessibilityIdentifier("display-language")
            }
        }
        .settingsListStyle()
        .navigationTitle(L("displayTitle"))
        .sensoryFeedback(.selection, trigger: theme)
        .sensoryFeedback(.selection, trigger: expandedNotes)
    }

    private func themeCard(_ option: ThemePreference) -> some View {
        let selected = theme == option.rawValue
        return Button {
            withAnimation(.snappy) { theme = option.rawValue }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: option.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .frame(height: 28)
                Text(option.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .foregroundStyle(selected ? AppColors.background : AppColors.textPrimary)
            .background(selected ? AppColors.textPrimary : AppColors.tile, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("display-theme-\(option.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct LanguageSettingsView: View {
    @AppStorage("app_language") private var language: String?

    var body: some View {
        List {
            Section {
                row(code: nil, title: L("settingsSystemDefault"), subtitle: nil)
                ForEach(AppLanguage.allCases) { lang in
                    row(code: lang.rawValue, title: lang.displayName, subtitle: localizedName(lang))
                }
            }
        }
        .settingsListStyle()
        .navigationTitle(L("language"))
        .sensoryFeedback(.selection, trigger: language)
    }

    private func row(code: String?, title: String, subtitle: String?) -> some View {
        Button {
            Localizer.shared.apply(code)
            language = code
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(AppColors.textPrimary)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 13)).foregroundStyle(AppColors.textSecondary)
                    }
                }
                Spacer()
                if language == code {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(AppColors.textPrimary)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("language-\(code ?? "system")")
    }

    private func localizedName(_ lang: AppLanguage) -> String {
        switch lang {
        case .en: L("english")
        case .tr: L("turkish")
        case .de: L("german")
        }
    }
}
