import PhotosUI
import QiqstrCore
import SwiftUI

@MainActor
@Observable
final class ArticleEditorModel {
    enum Mode: Hashable { case write, preview }

    var draft: ArticleDraft {
        didSet { scheduleSave() }
    }
    var hashtagText: String {
        didSet { draft.hashtags = ArticleDraft.parseHashtags(hashtagText) }
    }
    var mode: Mode = .write
    var selection: TextSelection?
    private(set) var isPublishing = false
    private(set) var isUploadingCover = false
    private(set) var isUploadingImage = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let original: ArticleDraft
    @ObservationIgnored private let wasSaved: Bool

    init(draft: ArticleDraft) {
        self.draft = draft
        original = draft
        wasSaved = ArticleDraftStore.shared.draft(id: draft.id) != nil
        hashtagText = draft.hashtags.joined(separator: ", ")
    }

    var isDirty: Bool {
        var current = draft
        current.updatedAt = original.updatedAt
        return current != original
    }

    var previewBlocks: [MarkdownBlock] { MarkdownParser.parse(draft.content) }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self, !self.isPublishing else { return }
            ArticleDraftStore.shared.save(self.draft)
        }
    }

    func saveNow() {
        saveTask?.cancel()
        ArticleDraftStore.shared.save(draft)
    }

    /// Drops this session's edits: a draft saved earlier goes back to how it was, a new one is removed.
    func discard() {
        saveTask?.cancel()
        if wasSaved { ArticleDraftStore.shared.save(original) } else { ArticleDraftStore.shared.delete(draft.id) }
    }

    func publish() async -> ArticleAddress? {
        guard !isPublishing else { return nil }
        saveTask?.cancel()
        ArticleDraftStore.shared.save(draft)
        isPublishing = true
        defer { isPublishing = false }
        do {
            let address = try await ArticlePublisher.publish(draft)
            ToastCenter.shared.show(L(draft.isEditingPublished ? "articleUpdated" : "articlePublished"), style: .success)
            return address
        } catch {
            ToastCenter.shared.show(coreMessage(error), style: .error)
            return nil
        }
    }

    // MARK: Images

    func uploadCover(_ item: PhotosPickerItem) async {
        isUploadingCover = true
        defer { isUploadingCover = false }
        if let url = await upload(item) { draft.image = url }
    }

    func insertImage(_ item: PhotosPickerItem) async {
        isUploadingImage = true
        defer { isUploadingImage = false }
        guard let url = await upload(item) else { return }
        insert(MarkdownEdit.image(url: url, in: draft.content, at: currentRange))
    }

    private func upload(_ item: PhotosPickerItem) async -> String? {
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else { throw CoreError(L("errorSelectingMedia")) }
            let type = item.supportedContentTypes.first { $0.conforms(to: .image) }
            let (data, mime) = await Task.detached(priority: .userInitiated) { () -> (Data, String) in
                if type?.conforms(to: .gif) == true { return (raw, "image/gif") }
                guard let image = ImagePipeline.downsample(raw, maxPixel: 2048), let jpeg = image.jpegData(compressionQuality: 0.88) else {
                    return (raw, type?.preferredMIMEType ?? "image/jpeg")
                }
                return (jpeg, "image/jpeg")
            }.value
            let url = try await MediaUploadService.shared.upload(data: data, mimeType: mime)
            guard !url.isEmpty else { throw CoreError(L("uploadFailed", ["message": ""])) }
            return url
        } catch {
            ToastCenter.shared.show(L("uploadFailed", ["message": coreMessage(error)]), style: .error)
            return nil
        }
    }

    // MARK: Formatting

    /// The selected text, or the caret position (an empty range). Falls back to the end of the text.
    private var currentRange: Range<String.Index> {
        let text = draft.content
        guard case .selection(let range)? = selection?.indices,
              range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex else {
            return text.endIndex..<text.endIndex
        }
        return range
    }

    func apply(_ style: MarkdownStyle) {
        insert(MarkdownEdit.apply(style, to: draft.content, range: currentRange))
    }

    private func insert(_ edit: MarkdownEdit) {
        draft.content = edit.text
        let caret = draft.content.index(draft.content.startIndex, offsetBy: min(edit.caret, draft.content.count))
        selection = TextSelection(insertionPoint: caret)
    }
}

enum MarkdownStyle: CaseIterable, Identifiable {
    case bold, italic, heading, quote, bullet, numbered, link, code

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .heading: "textformat.size"
        case .quote: "text.quote"
        case .bullet: "list.bullet"
        case .numbered: "list.number"
        case .link: "link"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }

    var title: String {
        switch self {
        case .bold: L("articleFormatBold")
        case .italic: L("articleFormatItalic")
        case .heading: L("articleFormatHeading")
        case .quote: L("articleFormatQuote")
        case .bullet: L("articleFormatBullets")
        case .numbered: L("articleFormatNumbers")
        case .link: L("articleFormatLink")
        case .code: L("articleFormatCode")
        }
    }
}

/// A text change made by a formatting button: the new text and where the caret goes (in characters).
struct MarkdownEdit: Equatable {
    var text: String
    var caret: Int

    static func apply(_ style: MarkdownStyle, to text: String, range: Range<String.Index>) -> MarkdownEdit {
        switch style {
        case .bold: wrap(text, range, "**", "**")
        case .italic: wrap(text, range, "*", "*")
        case .code: wrap(text, range, "`", "`")
        case .link: link(text, range)
        case .heading: prefixLine(text, range, "## ")
        case .quote: prefixLine(text, range, "> ")
        case .bullet: prefixLine(text, range, "- ")
        case .numbered: prefixLine(text, range, "1. ")
        }
    }

    static func image(url: String, in text: String, at range: Range<String.Index>) -> MarkdownEdit {
        let before = text[..<range.lowerBound]
        let lead = before.isEmpty || before.hasSuffix("\n\n") ? "" : (before.hasSuffix("\n") ? "\n" : "\n\n")
        let snippet = "\(lead)![](\(url))\n\n"
        var result = text
        result.replaceSubrange(range, with: snippet)
        return MarkdownEdit(text: result, caret: before.count + snippet.count)
    }

    private static func wrap(_ text: String, _ range: Range<String.Index>, _ open: String, _ close: String) -> MarkdownEdit {
        let selected = String(text[range])
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        var result = text
        result.replaceSubrange(range, with: open + selected + close)
        // With nothing selected the caret lands between the markers, ready to type.
        let caret = selected.isEmpty ? start + open.count : start + open.count + selected.count + close.count
        return MarkdownEdit(text: result, caret: caret)
    }

    private static func link(_ text: String, _ range: Range<String.Index>) -> MarkdownEdit {
        let selected = String(text[range])
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        let isURL = selected.hasPrefix("http://") || selected.hasPrefix("https://")
        let snippet = isURL ? "[](\(selected))" : "[\(selected)](https://)"
        var result = text
        result.replaceSubrange(range, with: snippet)
        // Put the caret where the user still has to type: the label for a pasted URL, otherwise the URL.
        let caret = isURL || selected.isEmpty ? start + 1 : start + snippet.count - 1
        return MarkdownEdit(text: result, caret: caret)
    }

    private static func prefixLine(_ text: String, _ range: Range<String.Index>, _ prefix: String) -> MarkdownEdit {
        let lineStart = text[..<range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let offset = text.distance(from: text.startIndex, to: range.lowerBound)
        var result = text
        if text[lineStart...].hasPrefix(prefix) {
            result.removeSubrange(lineStart..<text.index(lineStart, offsetBy: prefix.count))
            return MarkdownEdit(text: result, caret: max(text.distance(from: text.startIndex, to: lineStart), offset - prefix.count))
        }
        result.insert(contentsOf: prefix, at: lineStart)
        return MarkdownEdit(text: result, caret: offset + prefix.count)
    }
}

struct ArticleEditorView: View {
    @State private var model: ArticleEditorModel
    @State private var coverItem: PhotosPickerItem?
    @State private var imageItem: PhotosPickerItem?
    @State private var confirmClose = false
    @State private var confirmPublish = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var contentFocused: Bool

    init(draft: ArticleDraft) {
        _model = State(initialValue: ArticleEditorModel(draft: draft))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.mode {
                case .write: editor
                case .preview: preview
                }
            }
            .background(AppColors.background)
            .navigationTitle(model.draft.isEditingPublished ? L("articleEditTitle") : L("articleNewTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .confirmationDialog(L("articleCloseTitle"), isPresented: $confirmClose, titleVisibility: .visible) {
                Button(L("articleKeepDraft")) {
                    model.saveNow()
                    dismiss()
                }
                .accessibilityIdentifier("article-keep-draft")
                Button(L("articleDiscardDraft"), role: .destructive) {
                    model.discard()
                    dismiss()
                }
                .accessibilityIdentifier("article-discard-draft")
            }
            .confirmationDialog(model.draft.isEditingPublished ? L("articleUpdateConfirm") : L("articlePublishConfirm"), isPresented: $confirmPublish, titleVisibility: .visible) {
                Button(model.draft.isEditingPublished ? L("articleUpdate") : L("articlePublish")) {
                    Task { await publish() }
                }
                .accessibilityIdentifier("article-publish-confirm")
            } message: {
                Text(L("articlePublishMessage"))
            }
            #if os(macOS)
            .onExitCommand { close() }
            #endif
        }
        .interactiveDismissDisabled(model.isPublishing || model.isDirty)
        .onChange(of: coverItem) { _, item in
            guard let item else { return }
            coverItem = nil
            Task { await model.uploadCover(item) }
        }
        .onChange(of: imageItem) { _, item in
            guard let item else { return }
            imageItem = nil
            Task { await model.insertImage(item) }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(L("close"), systemImage: "xmark") { close() }
                .disabled(model.isPublishing)
                .accessibilityIdentifier("article-editor-close")
        }
        ToolbarItem(placement: .principal) {
            Picker(L("articleMode"), selection: $model.mode) {
                Text(L("articleWrite")).tag(ArticleEditorModel.Mode.write)
                Text(L("articlePreview")).tag(ArticleEditorModel.Mode.preview)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier("article-editor-mode")
        }
        ToolbarItem(placement: .confirmationAction) {
            if model.isPublishing {
                ProgressView()
            } else {
                Button(model.draft.isEditingPublished ? L("articleUpdate") : L("articlePublish")) {
                    contentFocused = false
                    confirmPublish = true
                }
                .fontWeight(.semibold)
                .disabled(!model.draft.canPublish || model.isUploadingCover || model.isUploadingImage)
                .accessibilityIdentifier("article-publish")
            }
        }
    }

    private func close() {
        if model.draft.isBlank {
            model.discard()
            dismiss()
        } else if model.isDirty {
            confirmClose = true
        } else {
            dismiss()
        }
    }

    private func publish() async {
        let isEdit = model.draft.isEditingPublished
        guard let address = await model.publish() else { return }
        dismiss()
        // An edit is usually made from the article itself, which refreshes in place.
        if !isEdit, let naddr = address.naddr {
            try? await Task.sleep(for: .milliseconds(350))
            Router.shared.push(.articleAddress(naddr))
        }
    }

    // MARK: Write

    private var editor: some View {
        Form {
            Section {
                coverRow
                TextField(L("articleTitlePlaceholder"), text: $model.draft.title, axis: .vertical)
                    .font(.title2.weight(.bold))
                    .lineLimit(1...4)
                    .accessibilityIdentifier("article-title")
                TextField(L("articleSummaryPlaceholder"), text: $model.draft.summary, axis: .vertical)
                    .lineLimit(1...5)
                    .accessibilityIdentifier("article-summary")
                TextField(L("articleHashtagsPlaceholder"), text: $model.hashtagText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("article-hashtags")
            }
            Section {
                TextEditor(text: $model.draft.content, selection: $model.selection)
                    .font(.body)
                    .frame(minHeight: 360)
                    .focused($contentFocused)
                    .overlay(alignment: .topLeading) {
                        if model.draft.content.isEmpty {
                            Text(L("articleContentPlaceholder"))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel(L("articleContent"))
                    .accessibilityIdentifier("article-content")
            } header: {
                formatBar
            } footer: {
                Text(L("articleWordCount", ["words": model.draft.wordCount, "minutes": max(1, model.draft.wordCount / 220)]))
                    .monospacedDigit()
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var coverRow: some View {
        if model.draft.image.isEmpty {
            PhotosPicker(selection: $coverItem, matching: .images) {
                HStack {
                    Label(L("articleAddCover"), systemImage: "photo")
                    Spacer()
                    if model.isUploadingCover { ProgressView() }
                }
            }
            .disabled(model.isUploadingCover)
            .accessibilityIdentifier("article-add-cover")
        } else {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    RemoteImage(url: model.draft.image, maxPixel: 1200) {
                        Rectangle().fill(.quaternary)
                    }
                }
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 8) {
                        PhotosPicker(selection: $coverItem, matching: .images) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .frame(width: 32, height: 32)
                                .background(.ultraThinMaterial, in: .circle)
                        }
                        .accessibilityLabel(L("articleReplaceCover"))
                        Button {
                            model.draft.image = ""
                        } label: {
                            Image(systemName: "xmark")
                                .frame(width: 32, height: 32)
                                .background(.ultraThinMaterial, in: .circle)
                        }
                        .accessibilityLabel(L("articleRemoveCover"))
                        .accessibilityIdentifier("article-remove-cover")
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
                .overlay { if model.isUploadingCover { ProgressView() } }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        }
    }

    private var formatBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(MarkdownStyle.allCases) { style in
                    Button { model.apply(style) } label: {
                        Image(systemName: style.systemImage)
                            .frame(width: 36, height: 32)
                    }
                    .accessibilityLabel(style.title)
                    .help(style.title)
                }
                PhotosPicker(selection: $imageItem, matching: .images) {
                    Group {
                        if model.isUploadingImage { ProgressView().controlSize(.small) } else { Image(systemName: "photo.badge.plus") }
                    }
                    .frame(width: 36, height: 32)
                }
                .disabled(model.isUploadingImage)
                .accessibilityLabel(L("articleInsertImage"))
                .help(L("articleInsertImage"))
            }
            .buttonStyle(.borderless)
            .font(.body)
            .foregroundStyle(AppColors.textPrimary)
        }
        .textCase(nil)
        .accessibilityIdentifier("article-format-bar")
    }

    // MARK: Preview

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !model.draft.image.isEmpty {
                    Color.clear
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay { RemoteImage(url: model.draft.image, maxPixel: 1600) { Rectangle().fill(.quaternary) } }
                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                }
                Text(model.draft.displayTitle)
                    .font(.largeTitle.weight(.bold))
                if !model.draft.summary.isEmpty {
                    Text(model.draft.summary)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                if !model.draft.hashtags.isEmpty {
                    Text(model.draft.hashtags.map { "#\($0)" }.joined(separator: " "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Divider()
                if model.draft.content.isEmpty {
                    Text(L("articlePreviewEmpty")).foregroundStyle(.secondary)
                } else {
                    MarkdownView(blocks: model.previewBlocks)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("article-preview")
    }
}
