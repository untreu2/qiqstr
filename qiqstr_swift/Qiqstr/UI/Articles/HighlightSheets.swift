import SwiftUI
import UIKit

struct HighlightDraft: Identifiable, Hashable {
    let id = UUID()
    let passage: String
}

struct HighlightComposerSheet: View {
    let draft: HighlightDraft
    let onPublish: (_ text: String, _ comment: String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selection = ""
    @State private var comment = ""
    @State private var confirming = false
    @State private var publishing = false

    private var quote: String {
        let picked = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        return picked.isEmpty ? draft.passage.trimmingCharacters(in: .whitespacesAndNewlines) : picked
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SelectableTextView(text: draft.passage, selection: $selection)
                        .frame(minHeight: 120)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .accessibilityIdentifier("highlight-passage")
                } header: {
                    Text(L("highlightPassage"))
                } footer: {
                    Text(L("highlightSelectHint"))
                }
                Section(L("highlightPreview")) {
                    Text(quote)
                        .font(.body)
                        .underline(color: AppColors.link.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("highlight-preview")
                }
                Section {
                    TextField(L("highlightCommentPlaceholder"), text: $comment, axis: .vertical)
                        .lineLimit(1...5)
                        .accessibilityIdentifier("highlight-comment")
                } header: {
                    Text(L("highlightComment"))
                } footer: {
                    Text(L("highlightPublicNotice"))
                }
            }
            .navigationTitle(L("highlightNew"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("cancel"), role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if publishing {
                        ProgressView()
                    } else {
                        Button(L("highlightAction"), systemImage: "highlighter") { confirming = true }
                            .buttonStyle(.glassProminent)
                            .foregroundStyle(AppColors.background)
                            .disabled(quote.isEmpty)
                            .accessibilityIdentifier("highlight-publish")
                    }
                }
            }
            .confirmationDialog(L("highlightConfirmTitle"), isPresented: $confirming, titleVisibility: .visible) {
                Button(L("highlightConfirmAction")) { publish() }
                Button(L("cancel"), role: .cancel) {}
            } message: {
                Text(L("highlightConfirmMessage"))
            }
            .interactiveDismissDisabled(publishing)
        }
    }

    private func publish() {
        publishing = true
        let text = quote
        let note = comment
        Task {
            let ok = await onPublish(text, note)
            publishing = false
            if ok { dismiss() }
        }
    }
}

struct SelectableTextView: UIViewRepresentable {
    let text: String
    @Binding var selection: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.font = .preferredFont(forTextStyle: .body)
        view.textColor = .label
        view.text = text
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var selection: Binding<String>
        init(selection: Binding<String>) { self.selection = selection }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let range = textView.selectedRange
            let ns = (textView.text ?? "") as NSString
            let picked = range.length > 0 && NSMaxRange(range) <= ns.length ? ns.substring(with: range) : ""
            if selection.wrappedValue != picked { selection.wrappedValue = picked }
        }
    }
}

struct HighlightsSheet: View {
    let highlights: [ArticleHighlight]
    let isLoading: Bool
    let onSelect: (ArticleHighlight) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cache = ProfileCache.shared
    @State private var reportTarget: ReportTarget?
    @State private var session = Session.shared

    var body: some View {
        NavigationStack {
            Group {
                if highlights.isEmpty {
                    if isLoading {
                        LoadingView()
                    } else {
                        EmptyStateView(systemImage: "highlighter", title: L("highlightsEmpty"), message: L("highlightsEmptyHint"))
                    }
                } else {
                    List(highlights.filter { !session.mutedPubkeys.contains($0.pubkey) }) { highlight in
                        Button {
                            dismiss()
                            onSelect(highlight)
                        } label: {
                            row(highlight)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(L("copy"), systemImage: "doc.on.doc") { UIPasteboard.general.string = highlight.content }
                            Button(L("exploreViewAuthor"), systemImage: "person.crop.circle") {
                                dismiss()
                                Router.shared.push(.profile(highlight.pubkey))
                            }
                            if highlight.pubkey != session.pubkey {
                                Section {
                                    Button(L("feedMuteAuthor"), systemImage: "speaker.slash", role: .destructive) {
                                        Task { await Moderation.mute(highlight.pubkey) }
                                    }
                                    Button(L("report"), systemImage: "flag", role: .destructive) {
                                        reportTarget = ReportTarget(pubkey: highlight.pubkey, eventId: highlight.id)
                                    }
                                }
                            }
                        }
                        .accessibilityIdentifier("highlight-row-\(highlight.id)")
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .reportSheet($reportTarget)
            .navigationTitle(L("highlightsTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("done")) { dismiss() }
                }
            }
            .task { await cache.load(Array(Set(highlights.map(\.pubkey)))) }
        }
    }

    private func row(_ highlight: ArticleHighlight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProfileAvatar(pubkey: highlight.pubkey, size: 24)
                Text(cache.profile(highlight.pubkey)?.bestName ?? Profile.shortNpub(highlight.pubkey))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(TimeFormat.relative(highlight.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 10) {
                Capsule().fill(AppColors.link.opacity(0.55)).frame(width: 3)
                Text(highlight.content)
                    .font(.body)
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
            if let comment = highlight.comment {
                Text(comment)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
