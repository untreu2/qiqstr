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
                                        .font(.body.weight(option == selected ? .semibold : .regular))
                                        .foregroundStyle(.primary)
                                    if option.localizedName != option.displayName {
                                        Text(option.localizedName)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if option == selected {
                                    Image(systemName: "checkmark")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
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
