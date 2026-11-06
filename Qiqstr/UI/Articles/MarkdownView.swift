import SwiftUI

struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    var baseSize: CGFloat = 17

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, baseSize: baseSize)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in MarkdownLinkHandler.open(url) })
    }
}

extension EnvironmentValues {
    @Entry var markdownQuoted = false
}

enum MarkdownLinkHandler {
    @MainActor
    static func open(_ url: URL) -> OpenURLAction.Result {
        switch url.scheme?.lowercased() {
        case "nostr":
            Router.shared.open(url: url)
            return .handled
        case "http", "https":
            Router.shared.sheet = .url(url)
            return .handled
        default:
            return .systemAction
        }
    }
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock
    var baseSize: CGFloat = 17

    var body: some View {
        switch block {
        case .heading(let level, let text):
            MarkdownText(text: text, size: headingSize(level), weight: level <= 2 ? .bold : .semibold)
                .padding(.top, level <= 2 ? 10 : 4)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            MarkdownText(text: text, size: baseSize)
        case .code(let language, let code):
            MarkdownCodeBlock(language: language, code: code)
        case .quote(let inner):
            HStack(alignment: .top, spacing: 12) {
                Capsule().fill(AppColors.border).frame(width: 3)
                MarkdownView(blocks: inner, baseSize: baseSize)
                    .environment(\.markdownQuoted, true)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .list(let ordered, let start, let items):
            MarkdownListView(ordered: ordered, start: start, items: items, baseSize: baseSize)
        case .image(let url, let alt, let link):
            MarkdownImage(url: url, alt: alt, link: link)
        case .table(let header, let rows):
            MarkdownTable(header: header, rows: rows)
        case .nostr(let entity):
            NostrEmbedView(entity: entity)
        case .rule:
            Rectangle().fill(AppColors.divider).frame(height: 1).padding(.vertical, 8)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 28
        case 2: 24
        case 3: 21
        case 4: 19
        default: 17
        }
    }
}

struct MarkdownText: View {
    let text: String
    var size: CGFloat = 17
    var weight: Font.Weight = .regular
    @Environment(\.markdownQuoted) private var quoted
    @State private var cache = ProfileCache.shared

    var body: some View {
        Text(MarkdownInline.attributed(text) { cache.profile($0)?.bestName })
            .font(.system(size: size, weight: weight))
            .lineSpacing(size * 0.3)
            .foregroundStyle(quoted ? AppColors.textSecondary : AppColors.textPrimary)
            .tint(AppColors.textPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct MarkdownListView: View {
    let ordered: Bool
    let start: Int
    let items: [MarkdownListItem]
    var baseSize: CGFloat = 17

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    marker(index: index, item: item)
                        .frame(minWidth: 18, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, block in
                            MarkdownBlockView(block: block, baseSize: baseSize)
                        }
                    }
                }
            }
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func marker(index: Int, item: MarkdownListItem) -> some View {
        if let checked = item.checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: baseSize - 1))
                .foregroundStyle(checked ? AppColors.textPrimary : AppColors.textSecondary)
        } else if ordered {
            Text("\(start + index).")
                .font(.system(size: baseSize, weight: .medium).monospacedDigit())
                .foregroundStyle(AppColors.textSecondary)
        } else {
            Text("•")
                .font(.system(size: baseSize, weight: .bold))
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}

struct MarkdownCodeBlock: View {
    let language: String
    let code: String
    @State private var copied = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !language.isEmpty {
                    Text(language.lowercased())
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied += 1
                    ToastCenter.shared.show(L("copiedToClipboard"), style: .success)
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.textSecondary)
                .accessibilityLabel(L("exploreCopyCode"))
                .accessibilityIdentifier("markdown-copy-code")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.inputFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sensoryFeedback(.success, trigger: copied)
    }
}

struct MarkdownImage: View {
    let url: String
    let alt: String
    let link: String?

    var body: some View {
        RemoteImage(url: url, maxPixel: 1600, contentMode: .fit) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColors.overlayLight)
                .frame(height: 180)
                .overlay { Image(systemName: "photo").foregroundStyle(AppColors.textSecondary) }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if let target = URL(string: link ?? url) { _ = MarkdownLinkHandler.open(target) }
        }
        .accessibilityLabel(alt.isEmpty ? L("exploreImage") : alt)
        .accessibilityAddTraits(.isImage)
    }
}

struct MarkdownTable: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        MarkdownText(text: cell, size: 15, weight: .semibold).fixedSize()
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            MarkdownText(text: cell, size: 15).fixedSize()
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(AppColors.inputFill.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
