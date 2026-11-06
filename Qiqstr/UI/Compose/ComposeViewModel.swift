import Foundation
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class ComposeAttachment: Identifiable {
    enum Status: Equatable {
        case uploading
        case uploaded(UploadedMedia)
        case failed(String)
    }

    let id = UUID()
    let preview: UIImage?
    let isVideo: Bool
    let dimensions: CGSize?
    var status: Status = .uploading
    @ObservationIgnored var payload: (Data, String)?

    init(preview: UIImage?, isVideo: Bool, dimensions: CGSize?) {
        self.preview = preview
        self.isVideo = isVideo
        self.dimensions = dimensions
    }

    var uploaded: UploadedMedia? {
        if case .uploaded(let media) = status { return media }
        return nil
    }
}

@MainActor
@Observable
final class ComposeViewModel {
    static let maxAttachments = 8
    static let maxFileSize = 50 * 1024 * 1024

    let context: ComposeContext
    var text = "" { didSet { if text != oldValue { updateMentionQuery() } } }
    var selection: TextSelection? { didSet { updateMentionQuery() } }
    var pickerItems: [PhotosPickerItem] = []
    private(set) var attachments: [ComposeAttachment] = []
    private(set) var suggestions: [Profile] = []
    private(set) var isPosting = false
    private(set) var didPost = 0
    @ObservationIgnored private var mentionMap: [String: String] = [:]
    @ObservationIgnored private var mentionRange: Range<String.Index>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var lastQuery: String?

    init(context: ComposeContext) {
        self.context = context
    }

    var target: Note? {
        switch context {
        case .newNote: nil
        case .reply(let note), .quote(let note): note
        }
    }

    var isUploading: Bool { attachments.contains { $0.status == .uploading } }
    var hasContent: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty }

    var canPost: Bool {
        guard !isPosting, !isUploading else { return false }
        if case .quote = context { return true }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachments.contains { $0.uploaded != nil }
    }

    var title: String {
        switch context {
        case .newNote: L("newPost")
        case .reply: L("reply")
        case .quote: L("quote")
        }
    }

    var placeholder: String {
        switch context {
        case .newNote, .quote: L("hintText")
        case .reply: L("addAReply")
        }
    }

    private func cursor() -> String.Index {
        if let selection, case .selection(let range) = selection.indices, range.upperBound <= text.endIndex { return range.upperBound }
        return text.endIndex
    }

    private func updateMentionQuery() {
        let end = cursor()
        guard end <= text.endIndex else { clearSuggestions(); return }
        let prefix = text[text.startIndex..<end]
        guard let at = prefix.lastIndex(of: "@") else { clearSuggestions(); return }
        let token = prefix[prefix.index(after: at)...]
        let before = at == text.startIndex ? nil : text[text.index(before: at)]
        guard before == nil || before!.isWhitespace, !token.contains(where: { $0.isWhitespace || $0 == "@" }), token.count <= 32 else {
            clearSuggestions()
            return
        }
        let query = String(token)
        mentionRange = at..<end
        guard !query.isEmpty else { suggestions = []; lastQuery = nil; return }
        guard query != lastQuery else { return }
        lastQuery = query
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let results = await NoteRepository.searchProfiles(query, limit: 8)
            guard !Task.isCancelled, let self else { return }
            let follows = FollowService.shared.following
            self.suggestions = results.sorted { a, b in
                let af = follows.contains(a.pubkey), bf = follows.contains(b.pubkey)
                return af != bf ? af : a.bestName.count < b.bestName.count
            }
        }
    }

    private func clearSuggestions() {
        mentionRange = nil
        lastQuery = nil
        searchTask?.cancel()
        if !suggestions.isEmpty { suggestions = [] }
    }

    func insertMention(_ profile: Profile) {
        guard let range = mentionRange, range.upperBound <= text.endIndex, let npub = Nip19.npub(profile.pubkey) else { return }
        let name = profile.bestName.replacingOccurrences(of: "\n", with: " ")
        let key = "@\(name)"
        mentionMap[key] = "nostr:\(npub)"
        let lower = text.distance(from: text.startIndex, to: range.lowerBound)
        text.replaceSubrange(range, with: "\(key) ")
        let newCursor = text.index(text.startIndex, offsetBy: min(lower + key.count + 1, text.count))
        selection = TextSelection(insertionPoint: newCursor)
        clearSuggestions()
        ProfileCache.shared.set(profile)
    }

    func handlePicked() async {
        let items = pickerItems
        pickerItems = []
        for item in items.prefix(max(0, Self.maxAttachments - attachments.count)) {
            await add(item)
        }
    }

    private func add(_ item: PhotosPickerItem) async {
        let type = item.supportedContentTypes.first
        let isVideo = type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            ToastCenter.shared.show(L("errorSelectingMedia"), style: .error)
            return
        }
        var payload = data
        var mime = type?.preferredMIMEType ?? (isVideo ? "video/mp4" : "image/jpeg")
        var preview: UIImage?
        var dimensions: CGSize?
        if isVideo {
            if mime == "video/quicktime" || mime.isEmpty { mime = "video/quicktime" }
        } else if let image = UIImage(data: data) {
            dimensions = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
            preview = ImagePipeline.downsample(data, maxPixel: 400)
            if mime != "image/gif", mime != "image/png" || data.count > 4_000_000 {
                if let jpeg = image.jpegData(compressionQuality: 0.86) {
                    payload = jpeg
                    mime = "image/jpeg"
                }
            }
        } else {
            ToastCenter.shared.show(L("invalidMediaFileType"), style: .error)
            return
        }
        guard payload.count <= Self.maxFileSize else {
            ToastCenter.shared.show(L("fileTooLarge"), style: .error)
            return
        }
        let attachment = ComposeAttachment(preview: preview, isVideo: isVideo, dimensions: dimensions)
        attachment.payload = (payload, mime)
        attachments.append(attachment)
        await upload(attachment)
    }

    func retry(_ attachment: ComposeAttachment) {
        Task { await upload(attachment) }
    }

    private func upload(_ attachment: ComposeAttachment) async {
        guard let (data, mime) = attachment.payload else { return }
        attachment.status = .uploading
        do {
            let media = try await MediaUploadService.shared.uploadMedia(data: data, mimeType: mime)
            attachment.status = .uploaded(media)
            attachment.payload = nil
        } catch {
            attachment.status = .failed(coreMessage(error))
            ToastCenter.shared.show(L("mediaUploadFailed"), style: .error)
        }
    }

    func remove(_ attachment: ComposeAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    private func finalContent() -> String {
        var content = text
        for key in mentionMap.keys.sorted(by: { $0.count > $1.count }) {
            if let value = mentionMap[key] { content = content.replacingOccurrences(of: key, with: value) }
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func post() async -> Bool {
        guard canPost else {
            if !hasContent { ToastCenter.shared.show(L("emptyNoteMessage"), style: .error) }
            return false
        }
        isPosting = true
        defer { isPosting = false }
        let media = attachments.compactMap { attachment -> (UploadedMedia, CGSize?)? in
            attachment.uploaded.map { ($0, attachment.dimensions) }
        }
        let urls = media.map(\.0.url)
        let imeta: [[String]] = media.map { item, size in
            var tag = ["imeta", "url \(item.url)", "m \(item.mimeType)"]
            if !item.sha256.isEmpty { tag.append("x \(item.sha256)") }
            if let size { tag.append("dim \(Int(size.width))x\(Int(size.height))") }
            return tag
        }
        let content = finalContent()
        let service = InteractionService.shared
        do {
            switch context {
            case .newNote:
                _ = try await service.publishNote(content: content, mediaUrls: urls, extraTags: imeta)
            case .reply(let note):
                _ = try await service.publishReply(to: note, content: content, mediaUrls: urls, extraTags: imeta)
                NoteInteractionStore.shared.markReplied(note.id)
            case .quote(let note):
                _ = try await service.publishQuote(of: note, content: content, mediaUrls: urls, extraTags: imeta)
            }
            didPost += 1
            DataBus.shared.feedChanged()
            return true
        } catch {
            ToastCenter.shared.show("\(L("errorSharingNote")): \(coreMessage(error))", style: .error)
            return false
        }
    }
}
