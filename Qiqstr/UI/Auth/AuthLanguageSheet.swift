import SwiftUI

struct AuthLanguageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected = AppLanguage.current

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(AppLanguage.allCases) { option in
                        Button {
                            select(option)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.displayName)
                                        .font(.system(size: 17, weight: option == selected ? .semibold : .regular))
                                        .foregroundStyle(AppColors.textPrimary)
                                    if option.localizedName != option.displayName {
                                        Text(option.localizedName)
                                            .font(.system(size: 13))
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                }
                                Spacer()
                                if option == selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(AppColors.textPrimary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(option == selected ? .isSelected : [])
                        .accessibilityIdentifier("language-\(option.rawValue)")
                    }
                } footer: {
                    Text(L("languageSubtitle"))
                }
            }
            .navigationTitle(L("language"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityIdentifier("language-close")
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func select(_ option: AppLanguage) {
        selected = option
        Localizer.shared.apply(option.rawValue)
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            UserDefaults.standard.set(option.rawValue, forKey: "app_language")
        }
    }
}
