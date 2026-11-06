import SwiftUI

struct AuthTermsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private enum Block {
        case heading(Int, String)
        case bullet(String)
        case paragraph(String)
        case divider
    }

    private let blocks: [Block] = AuthTermsText.markdown
        .components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .map { line in
            if line == "---" { return .divider }
            if line.hasPrefix("#") {
                let level = line.prefix { $0 == "#" }.count
                return .heading(level, String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces))
            }
            if line.hasPrefix("- ") { return .bullet(String(line.dropFirst(2))) }
            return .paragraph(line)
        }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        view(for: block)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .textSelection(.enabled)
            }
            .background(AppColors.background)
            .navigationTitle(L("authTermsTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("done")) { dismiss() }
                        .accessibilityIdentifier("terms-done")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("terms-sheet")
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(level == 1 ? AppFont.brand(26) : level == 2 ? AppFont.brandSemibold(21) : .system(size: level == 3 ? 17 : 15, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.top, level <= 2 ? 10 : 6)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                Text(inline(text)).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 15))
            .foregroundStyle(AppColors.textPrimary)
            .padding(.leading, 4)
        case .paragraph(let text):
            Text(inline(text))
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .divider:
            Divider().overlay(AppColors.divider).padding(.vertical, 8)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
