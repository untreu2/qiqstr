import AVFoundation
import ImageIO
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
    let audio: ComposeAudio?
    var status: Status = .uploading
    var altText = ""
    @ObservationIgnored var payload: (Data, String)?

    let remoteURL: String?

    init(preview: UIImage?, isVideo: Bool, dimensions: CGSize?, blurhash: String? = nil, remoteURL: String? = nil, audio: ComposeAudio? = nil) {
        self.remoteURL = remoteURL
        self.preview = preview
        self.isVideo = isVideo
        self.dimensions = dimensions
        self.blurhash = blurhash
        self.audio = audio
    }

    var isAudio: Bool { audio != nil }

    var trimmedAlt: String? {
        altText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var uploaded: UploadedMedia? {
        if case .uploaded(let media) = status { return media }
        return nil
    }
}

struct ComposeAudio: Hashable, Sendable {
    var duration: Double
    var waveform: [Int]
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
    var scheduledAt: Date?
    var goalEnabled = false
    var goalAmount = ""
    var goalHasEnd = false
    var goalEndsAt = Date().addingTimeInterval(7 * 86400)
    private(set) var draftId = UUID().uuidString
    private(set) var attachments: [ComposeAttachment] = []
    private(set) var suggestions: [Profile] = []
    private(set) var isPosting = false
    private(set) var didPost = 0
    @ObservationIgnored private var mentionMap: [String: String] = [:]
    @ObservationIgnored private var emojiMap: [String: String] = [:]
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
        if let scheduled = ScheduledPostService.shared.takePendingEdit() {
            apply(scheduled.draft)
            scheduledAt = scheduled.publishAt
        } else if let draft = pending?.contextKey == contextKey ? pending : store.latest(contextKey: contextKey) {
            apply(draft)
        }
        if context == .newNote, let share = SharedInbox.shared.pending {
            if !share.text.isEmpty { text = text.isEmpty ? share.text : text + "\n" + share.text }
            let images = share.imageURLs.prefix(max(0, Self.maxAttachments - attachments.count)).compactMap { try? Data(contentsOf: $0) }
            SharedInbox.shared.consume()
            if !images.isEmpty { Task { await self.importShared(images) } }
        }
    }

    private func importShared(_ images: [Data]) async {
        for data in images {
            guard let image = UIImage(data: data) else { continue }
            let preview = ImagePipeline.downsample(data, maxPixel: 400)
            let attachment = ComposeAttachment(preview: preview, isVideo: false, dimensions: CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale), blurhash: preview.flatMap { BlurHash.encode($0) })
            attachment.payload = (MediaSanitizer.strippedImage(data, mime: "image/jpeg") ?? data, "image/jpeg")
            attachments.append(attachment)
            await upload(attachment)
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
            return ComposeDraftMedia(url: item.url, sha256: item.sha256, mimeType: item.mimeType, size: item.size, width: attachment.dimensions.map { Double($0.width) }, height: attachment.dimensions.map { Double($0.height) }, blurhash: attachment.blurhash, altText: attachment.altText, isVideo: attachment.isVideo, duration: attachment.audio?.duration, waveform: attachment.audio?.waveform)
        }
        let poll = pollEnabled ? ComposeDraftPoll(options: pollOptions.map(\.text), multiple: pollMultiple, endsAt: pollHasEnd ? pollEndsAt : nil) : nil
        return ComposeDraft(id: draftId, kind: kind, targetId: target?.id, targetPubkey: target?.pubkey, text: text, mentions: mentionMap, media: media, contentWarningEnabled: contentWarningEnabled, contentWarningReason: contentWarningReason, poll: poll, updatedAt: .distantPast, emojis: emojiMap.isEmpty ? nil : emojiMap, goal: isGoalActive ? ComposeDraftGoal(amountSats: goalSats ?? 0, closesAt: goalHasEnd ? goalEndsAt : nil) : nil)
    }

    private func apply(_ draft: ComposeDraft) {
        draftId = draft.id
        mentionMap = draft.mentions
        emojiMap = draft.emojis ?? [:]
        text = draft.text
        selection = nil
        contentWarningEnabled = draft.contentWarningEnabled
        contentWarningReason = draft.contentWarningReason
        attachments = draft.media.map { item in
            let size = item.width.flatMap { w in item.height.map { CGSize(width: w, height: $0) } }
            let audio = item.isAudio ? ComposeAudio(duration: item.duration ?? 0, waveform: item.waveform ?? []) : nil
            let attachment = ComposeAttachment(preview: nil, isVideo: item.isVideo, dimensions: size, blurhash: item.blurhash, remoteURL: item.url, audio: audio)
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
        if let goal = draft.goal, supportsPoll {
            goalEnabled = true
            goalAmount = goal.amountSats > 0 ? String(goal.amountSats) : ""
            goalHasEnd = goal.closesAt != nil
            goalEndsAt = goal.closesAt ?? Date().addingTimeInterval(7 * 86400)
        } else {
            goalEnabled = false
            goalAmount = ""
            goalHasEnd = false
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
            if let scheduledAt, ScheduledPostService.shared.contains(draftId) {
                ScheduledPostService.shared.schedule(draft, at: scheduledAt)
                DraftStore.shared.delete(draftId)
            } else {
                ScheduledPostService.shared.cancel(draftId)
                DraftStore.shared.save(draft)
            }
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
        ScheduledPostService.shared.cancel(draftId)
    }

    var scheduledPosts: [ScheduledPost] {
        ScheduledPostService.shared.posts.filter { $0.id != draftId }
    }

    func open(_ post: ScheduledPost) async {
        saveDraft()
        if post.draft.contextKey == contextKey {
            apply(post.draft)
            scheduledAt = post.publishAt
            return
        }
        ScheduledPostService.shared.edit(post)
        await open(post.draft)
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
        if pollEnabled { goalEnabled = false }
    }

    func toggleGoal() {
        goalEnabled.toggle()
        if goalEnabled { pollEnabled = false }
    }

    var isGoalActive: Bool { goalEnabled && supportsPoll }

    var goalSats: Int? {
        guard let value = Int(goalAmount.filter(\.isNumber)), value > 0, SatsAmount.msat(value) != nil else { return nil }
        return value
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
        if isGoalActive {
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && goalSats != nil && (!goalHasEnd || goalEndsAt > Date())
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
        if isGoalActive { return L("zapGoalPlaceholder") }
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

    func insert(_ choice: EmojiChoice) {
        let position = min(cursor(), text.endIndex)
        let offset = text.distance(from: text.startIndex, to: position)
        let inserted: String
        switch choice {
        case .unicode(let emoji): inserted = emoji
        case .custom(let emoji):
            emojiMap[emoji.shortcode] = emoji.url
            inserted = emoji.token
        }
        text.insert(contentsOf: inserted, at: position)
        selection = TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: offset + inserted.count))
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
        var mime = type?.preferredMIMEType ?? (isVideo ? "video/mp4" : "image/jpeg")
        if isVideo, mime.isEmpty { mime = "video/quicktime" }
        if isVideo {
            guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else {
                ToastCenter.shared.show(L("errorSelectingMedia"), style: .error)
                return
            }
            defer { movie.discard() }
            await addVideo(at: movie.url, size: movie.size, mime: mime)
        } else {
            guard let loaded = try? await item.loadTransferable(type: Data.self) else {
                ToastCenter.shared.show(L("errorSelectingMedia"), style: .error)
                return
            }
            await addImage(loaded, mime: mime)
        }
    }

    func addCaptured(image: UIImage) async {
        guard canAttach, let data = image.jpegData(compressionQuality: 0.92) else { return }
        await addImage(data, mime: "image/jpeg")
    }

    func addCaptured(videoAt url: URL) async {
        guard canAttach else { return }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        await addVideo(at: url, size: size, mime: "video/quicktime")
        try? FileManager.default.removeItem(at: url)
    }

    func addGif(_ gif: GifItem) {
        guard canAttach, !attachments.contains(where: { $0.remoteURL == gif.url }) else { return }
        let attachment = ComposeAttachment(preview: nil, isVideo: false, dimensions: gif.size, blurhash: gif.blurhash, remoteURL: gif.url)
        attachment.status = .uploaded(UploadedMedia(url: gif.url, sha256: gif.sha256 ?? "", mimeType: "image/gif", size: 0))
        attachment.altText = gif.title
        attachments.append(attachment)
    }

    func addRecording(_ recording: VoiceRecording) async {
        guard canAttach, let data = try? Data(contentsOf: recording.url) else {
            ToastCenter.shared.show(L("errorSelectingMedia"), style: .error)
            return
        }
        let attachment = ComposeAttachment(preview: nil, isVideo: false, dimensions: nil, audio: ComposeAudio(duration: recording.duration, waveform: recording.waveform))
        attachment.payload = (data, "audio/mp4")
        attachments.append(attachment)
        try? FileManager.default.removeItem(at: recording.url)
        await upload(attachment)
    }

    var canAttach: Bool { attachments.count < Self.maxAttachments }

    private func addVideo(at url: URL, size: Int, mime: String) async {
        guard size <= Self.maxFileSize else {
            ToastCenter.shared.show(L("fileTooLarge"), style: .error)
            return
        }
        guard let stripped = await MediaSanitizer.strippedVideo(at: url, mime: mime) else {
            ToastCenter.shared.show(L("errorSelectingMedia"), style: .error)
            return
        }
        await attach(payload: stripped, mime: mime, isVideo: true, preview: nil, dimensions: nil)
    }

    private func addImage(_ data: Data, mime: String) async {
        var mime = mime
        var payload = data
        var preview: UIImage?
        var dimensions: CGSize?
        do {
            let inputMime = mime
            let prepared = await Task.detached(priority: .userInitiated) { () -> (Data, String, UIImage?, CGSize)? in
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
                      let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
                let preview = ImagePipeline.downsample(data, maxPixel: 400)
                if inputMime == "image/gif" { return (data, inputMime, preview, CGSize(width: width, height: height)) }
                guard let image = ImagePipeline.downsample(data, maxPixel: 4096) else { return nil }
                if inputMime == "image/png", data.count <= 4_000_000, let png = image.pngData() {
                    return (png, "image/png", preview, CGSize(width: image.size.width, height: image.size.height))
                }
                guard let jpeg = image.jpegData(compressionQuality: 0.86) else { return nil }
                return (jpeg, "image/jpeg", preview, CGSize(width: image.size.width, height: image.size.height))
            }.value
            guard let prepared else {
                ToastCenter.shared.show(L("invalidMediaFileType"), style: .error)
                return
            }
            (payload, mime, preview, dimensions) = (prepared.0, prepared.1, prepared.2, prepared.3)
        }
        await attach(payload: payload, mime: mime, isVideo: false, preview: preview, dimensions: dimensions)
    }

    private func attach(payload: Data, mime: String, isVideo: Bool, preview: UIImage?, dimensions: CGSize?) async {
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

    func remove(_ attachment: ComposeAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    func post() async -> Bool {
        guard canPost else {
            if !hasContent { ToastCenter.shared.show(L("emptyNoteMessage"), style: .error) }
            return false
        }
        guard !SearchService.containsSecret(text) else {
            ToastCenter.shared.show(L("composeSecretBlocked"), style: .error)
            return false
        }
        isPosting = true
        defer { isPosting = false }
        var draft = draftSnapshot
        draft.updatedAt = Date()
        if let scheduledAt, scheduledAt > Date() {
            saveTask?.cancel()
            finished = true
            DraftStore.shared.delete(draftId)
            ScheduledPostService.shared.schedule(draft, at: scheduledAt)
            didPost += 1
            ToastCenter.shared.show(L("feedScheduledFor", ["date": scheduledAt.formatted(date: .abbreviated, time: .shortened)]), style: .success)
            return true
        }
        do {
            try await ComposePublisher.publish(draft)
            didPost += 1
            deleteDraft()
            return true
        } catch {
            ToastCenter.shared.show("\(L("errorSharingNote")): \(coreMessage(error))", style: .error)
            return false
        }
    }
}
