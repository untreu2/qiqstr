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
    let blurhash: String?
    var status: Status = .uploading
    var altText = ""
    @ObservationIgnored var payload: (Data, String)?

    let remoteURL: String?

    init(preview: UIImage?, isVideo: Bool, dimensions: CGSize?, blurhash: String? = nil, remoteURL: String? = nil) {
        self.remoteURL = remoteURL
        self.preview = preview
        self.isVideo = isVideo
        self.dimensions = dimensions
        self.blurhash = blurhash
    }

    var trimmedAlt: String? {
        altText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var uploaded: UploadedMedia? {
        if case .uploaded(let media) = status { return media }
        return nil
    }
}

struct ComposePollOption: Identifiable, Hashable {
    let id = UUID()
    var text = ""
}

@MainActor
@Observable
final class ComposeViewModel {
    static let minPollOptions = 2
    static let maxPollOptions = 6
    static let maxAttachments = 8
    static let maxFileSize = 50 * 1024 * 1024

    let context: ComposeContext
    var text = "" { didSet { if text != oldValue { updateMentionQuery() } } }
    var selection: TextSelection? { didSet { updateMentionQuery() } }
    var pickerItems: [PhotosPickerItem] = []
    var contentWarningEnabled = false
    var contentWarningReason = ""
    var pollEnabled = false
    var pollOptions: [ComposePollOption] = [ComposePollOption(), ComposePollOption()]
    var pollMultiple = false
    var pollHasEnd = false
    var pollEndsAt = Date().addingTimeInterval(86400)
    private(set) var draftId = UUID().uuidString
    private(set) var attachments: [ComposeAttachment] = []
    private(set) var suggestions: [Profile] = []
    private(set) var isPosting = false
    private(set) var didPost = 0
    @ObservationIgnored private var mentionMap: [String: String] = [:]
    @ObservationIgnored private var mentionRange: Range<String.Index>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var lastQuery: String?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var finished = false

    init(context: ComposeContext) {
        self.context = context
        let store = DraftStore.shared
        let pending = store.pendingDraftId.flatMap(store.draft)
        store.pendingDraftId = nil
        if let draft = pending?.contextKey == contextKey ? pending : store.latest(contextKey: contextKey) {
            apply(draft)
        }
        if context == .newNote, let shared = SharedInbox.defaults?.string(forKey: "compose_prefill_text"), !shared.isEmpty {
            text = text.isEmpty ? shared : text + "\n" + shared
            SharedInbox.shared.consume()
        }
    }

    var contextKey: String {
        switch context {
        case .newNote: "new"
        case .reply(let note): "reply-\(note.id)"
        case .quote(let note): "quote-\(note.id)"
        }
    }

    var supportsPoll: Bool { context == .newNote }

    var otherDrafts: [ComposeDraft] {
        DraftStore.shared.drafts.filter { $0.id != draftId }
    }

    private var validPollOptions: [String] {
        var seen: Set<String> = []
        return pollOptions
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    var draftSnapshot: ComposeDraft {
        let kind: ComposeDraft.Kind
        switch context {
        case .newNote: kind = .newNote
        case .reply: kind = .reply
        case .quote: kind = .quote
        }
        let media = attachments.compactMap { attachment -> ComposeDraftMedia? in
            guard let item = attachment.uploaded else { return nil }
            return ComposeDraftMedia(url: item.url, sha256: item.sha256, mimeType: item.mimeType, size: item.size, width: attachment.dimensions.map { Double($0.width) }, height: attachment.dimensions.map { Double($0.height) }, blurhash: attachment.blurhash, altText: attachment.altText, isVideo: attachment.isVideo)
        }
        let poll = pollEnabled ? ComposeDraftPoll(options: pollOptions.map(\.text), multiple: pollMultiple, endsAt: pollHasEnd ? pollEndsAt : nil) : nil
        return ComposeDraft(id: draftId, kind: kind, targetId: target?.id, targetPubkey: target?.pubkey, text: text, mentions: mentionMap, media: media, contentWarningEnabled: contentWarningEnabled, contentWarningReason: contentWarningReason, poll: poll, updatedAt: .distantPast)
    }

    private func apply(_ draft: ComposeDraft) {
        draftId = draft.id
        mentionMap = draft.mentions
        text = draft.text
        selection = nil
        contentWarningEnabled = draft.contentWarningEnabled
        contentWarningReason = draft.contentWarningReason
        attachments = draft.media.map { item in
            let size = item.width.flatMap { w in item.height.map { CGSize(width: w, height: $0) } }
            let attachment = ComposeAttachment(preview: nil, isVideo: item.isVideo, dimensions: size, blurhash: item.blurhash, remoteURL: item.url)
            attachment.status = .uploaded(UploadedMedia(url: item.url, sha256: item.sha256, mimeType: item.mimeType, size: item.size))
            attachment.altText = item.altText
            return attachment
        }
        if let poll = draft.poll, supportsPoll {
            pollEnabled = true
            var options = poll.options.map { ComposePollOption(text: $0) }
            while options.count < Self.minPollOptions { options.append(ComposePollOption()) }
            pollOptions = Array(options.prefix(Self.maxPollOptions))
            pollMultiple = poll.multiple
            pollHasEnd = poll.endsAt != nil
            pollEndsAt = poll.endsAt ?? Date().addingTimeInterval(86400)
        } else {
            pollEnabled = false
            pollOptions = [ComposePollOption(), ComposePollOption()]
            pollMultiple = false
            pollHasEnd = false
        }
        clearSuggestions()
    }

    func scheduleSave() {
        guard !finished else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.saveDraft()
        }
    }

    func saveDraft() {
        saveTask?.cancel()
        guard !finished else { return }
        if hasContent {
            var draft = draftSnapshot
            draft.updatedAt = Date()
            DraftStore.shared.save(draft)
        } else {
            DraftStore.shared.delete(draftId)
        }
    }

    func finishSaving() {
        saveDraft()
        finished = true
    }

    func deleteDraft() {
        saveTask?.cancel()
        finished = true
        DraftStore.shared.delete(draftId)
    }

    func deleteDraft(_ id: String) {
        DraftStore.shared.delete(id)
    }

    func open(_ draft: ComposeDraft) async {
        saveDraft()
        if draft.contextKey == contextKey {
            apply(draft)
            return
        }
        let next: ComposeContext
        switch draft.kind {
        case .newNote:
            next = .newNote
        case .reply, .quote:
            guard let id = draft.targetId, let note = await NoteRepository.ensureNote(id) else {
                ToastCenter.shared.show(L("eventNotFound"), style: .error)
                return
            }
            next = draft.kind == .reply ? .reply(note) : .quote(note)
        }
        finished = true
        DraftStore.shared.pendingDraftId = draft.id
        Router.shared.composeContext = next
    }

    func togglePoll() {
        pollEnabled.toggle()
    }

    func addPollOption() {
        guard pollOptions.count < Self.maxPollOptions else { return }
        pollOptions.append(ComposePollOption())
    }

    func removePollOption(_ option: ComposePollOption) {
        guard pollOptions.count > Self.minPollOptions else { return }
        pollOptions.removeAll { $0.id == option.id }
    }

    var target: Note? {
        switch context {
        case .newNote: nil
        case .reply(let note), .quote(let note): note
        }
    }

    var isUploading: Bool { attachments.contains { $0.status == .uploading } }
    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
            || (pollEnabled && pollOptions.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    var isPollActive: Bool { pollEnabled && supportsPoll }

    var canPost: Bool {
        guard !isPosting, !isUploading else { return false }
        if isPollActive {
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validPollOptions.count >= Self.minPollOptions && (!pollHasEnd || pollEndsAt > Date())
        }
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
        if isPollActive { return L("feedPollQuestion") }
        switch context {
        case .newNote, .quote: return L("hintText")
        case .reply: return L("addAReply")
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
        let attachment = ComposeAttachment(preview: preview, isVideo: isVideo, dimensions: dimensions, blurhash: preview.flatMap { BlurHash.encode($0) })
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

    private var contentWarningTags: [[String]] {
        guard contentWarningEnabled else { return [] }
        let reason = contentWarningReason.trimmingCharacters(in: .whitespacesAndNewlines)
        return [reason.isEmpty ? ["content-warning"] : ["content-warning", reason]]
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
        let uploaded = attachments.filter { $0.uploaded != nil }
        let urls = uploaded.compactMap { $0.uploaded?.url }
        let imeta: [[String]] = uploaded.compactMap { attachment in
            guard let item = attachment.uploaded else { return nil }
            var tag = ["imeta", "url \(item.url)", "m \(item.mimeType)"]
            if !item.sha256.isEmpty { tag.append("x \(item.sha256)") }
            if let size = attachment.dimensions { tag.append("dim \(Int(size.width))x\(Int(size.height))") }
            if let blurhash = attachment.blurhash { tag.append("blurhash \(blurhash)") }
            if let alt = attachment.trimmedAlt { tag.append("alt \(alt)") }
            return tag
        }
        let extraTags = imeta + contentWarningTags
        let content = finalContent()
        let service = InteractionService.shared
        do {
            switch context {
            case .newNote where isPollActive:
                _ = try await service.publishPoll(question: content, options: validPollOptions, multiple: pollMultiple, endsAt: pollHasEnd ? pollEndsAt : nil, mediaUrls: urls, extraTags: extraTags)
            case .newNote:
                _ = try await service.publishNote(content: content, mediaUrls: urls, extraTags: extraTags)
            case .reply(let note):
                _ = try await service.publishReply(to: note, content: content, mediaUrls: urls, extraTags: extraTags)
                NoteInteractionStore.shared.markReplied(note.id)
            case .quote(let note):
                _ = try await service.publishQuote(of: note, content: content, mediaUrls: urls, extraTags: extraTags)
            }
            didPost += 1
            deleteDraft()
            DataBus.shared.feedChanged()
            return true
        } catch {
            ToastCenter.shared.show("\(L("errorSharingNote")): \(coreMessage(error))", style: .error)
            return false
        }
    }
}
