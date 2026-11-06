import SwiftUI

struct MarkdownView: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
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

    var body: some View {
        switch block {
        case .heading(let level, let text):
            MarkdownText(text: text, style: headingStyle(level), weight: level <= 3 ? .bold : nil)
                .padding(.top, level <= 2 ? 10 : 4)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            MarkdownText(text: text)
        case .code(let language, let code):
            MarkdownCodeBlock(language: language, code: code)
        case .quote(let inner):
            HStack(alignment: .top, spacing: 12) {
                Capsule().fill(.tertiary).frame(width: 3)
                MarkdownView(blocks: inner)
                    .environment(\.markdownQuoted, true)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .list(let ordered, let start, let items):
            MarkdownListView(ordered: ordered, start: start, items: items)
        case .image(let url, let alt, let link):
            MarkdownImage(url: url, alt: alt, link: link)
        case .table(let header, let rows):
            MarkdownTable(header: header, rows: rows)
        case .nostr(let entity):
            NostrEmbedView(entity: entity)
        case .rule:
            Divider().padding(.vertical, 8)
        }
    }

    private func headingStyle(_ level: Int) -> Font.TextStyle {
        switch level {
        case 1: .title
        case 2: .title2
        case 3: .title3
        default: .headline
        }
    }
}

struct MarkdownText: View {
    let text: String
    var style: Font.TextStyle = .body
    var weight: Font.Weight? = nil
    @Environment(\.markdownQuoted) private var quoted
    @State private var cache = ProfileCache.shared
    @ScaledMetric(relativeTo: .body) private var bodyLineSpacing: CGFloat = 6

    var body: some View {
        Text(MarkdownInline.attributed(text) { cache.profile($0)?.bestName })
            .font(.system(style).weight(weight ?? .regular))
            .lineSpacing(style == .body ? bodyLineSpacing : 2)
            .foregroundStyle(quoted ? .secondary : .primary)
            .tint(AppColors.link)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct MarkdownListView: View {
    let ordered: Bool
    let start: Int
    let items: [MarkdownListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    marker(index: index, item: item)
                        .frame(minWidth: 18, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, block in
                            MarkdownBlockView(block: block)
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
                .font(.body)
                .foregroundStyle(checked ? .primary : .secondary)
        } else if ordered {
            Text("\(start + index).")
                .font(.body.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
        } else {
            Text("•")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
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
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied += 1
                    ToastCenter.shared.show(L("copiedToClipboard"), style: .success)
                } label: {
                    Image(systemName: "doc.on.doc").font(.footnote.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel(L("exploreCopyCode"))
                .accessibilityIdentifier("markdown-copy-code")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.body.monospaced())
                    .foregroundStyle(.primary)
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
        VStack(alignment: .leading, spacing: 6) {
            image
            if alt.contains(" ") {
                Text(alt)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
    }

    private var image: some View {
        RemoteImage(url: url, maxPixel: 1600, contentMode: .fit) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.quaternary)
                .frame(height: 180)
                .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
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
                        MarkdownText(text: cell, style: .subheadline, weight: .semibold).fixedSize()
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            MarkdownText(text: cell, style: .subheadline).fixedSize()
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(AppColors.inputFill.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
