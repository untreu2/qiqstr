import SwiftUI

struct QiqTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var axis: Axis = .horizontal
    var keyboard: UIKeyboardType = .default
    var autocapitalize = false
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text, axis: axis)
                }
            }
            .keyboardType(keyboard)
            .textInputAutocapitalization(autocapitalize ? .sentences : .never)
            .autocorrectionDisabled(!autocapitalize)
            .font(.body)
            if let trailing { trailing }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(AppColors.inputFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppColors.textSecondary)
            .textCase(nil)
    }
}
