import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct DMChatRow: Identifiable, Hashable {
    enum Kind: Hashable {
        case day(Date)
        case message(DMMessage, isFirstInGroup: Bool, isLastInGroup: Bool)
    }
    let id: String
    let kind: Kind
}

struct DMAttachmentDraft: Identifiable, Equatable {
    enum State: Equatable {
        case preparing
        case ready(DMPreparedFile)
    }
    let id = UUID()
    var thumbnail: UIImage?
    var isVideo: Bool
    var state: State = .preparing

    var prepared: DMPreparedFile? {
        if case .ready(let file) = state { return file }
        return nil
    }
}

@MainActor
@Observable
final class DMChatViewModel {
    let peer: String
    var draft = ""
    var pickerItems: [PhotosPickerItem] = []
    private(set) var attachments: [DMAttachmentDraft] = []
    private(set) var sentCount = 0
    private(set) var failureCount = 0
    private let service = DMService.shared
    private let groupWindow = 300

    init(peer: String) { self.peer = peer }

    var messages: [DMMessage] { service.messages(with: peer) }
    var isLoading: Bool { !service.hasLoaded && messages.isEmpty }
    var isPreparingAttachment: Bool { attachments.contains { $0.state == .preparing } }

    var canSend: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasReady = attachments.contains { $0.prepared != nil }
        return (hasText || hasReady) && !isPreparingAttachment
    }

    var rows: [DMChatRow] {
        let list = messages
        var rows: [DMChatRow] = []
        rows.reserveCapacity(list.count + 8)
        let calendar = Calendar.current
        for (index, message) in list.enumerated() {
            let previous = index > 0 ? list[index - 1] : nil
            let next = index + 1 < list.count ? list[index + 1] : nil
            if previous == nil || !calendar.isDate(previous!.date, inSameDayAs: message.date) {
                let day = calendar.startOfDay(for: message.date)
                rows.append(DMChatRow(id: "day-\(Int(day.timeIntervalSince1970))", kind: .day(day)))
            }
            let first = previous.map { !grouped($0, message, calendar) } ?? true
            let last = next.map { !grouped(message, $0, calendar) } ?? true
            rows.append(DMChatRow(id: message.id, kind: .message(message, isFirstInGroup: first, isLastInGroup: last)))
        }
        return rows
    }

    private func grouped(_ a: DMMessage, _ b: DMMessage, _ calendar: Calendar) -> Bool {
        a.isMine == b.isMine && b.createdAt - a.createdAt < groupWindow && calendar.isDate(a.date, inSameDayAs: b.date) && a.state == b.state
    }

    func appeared() async {
        service.activePeer = peer
        let peer = peer
        Task { _ = await self.service.dmRelays(for: peer) }
        await service.start()
        service.markRead(peer)
    }

    func disappeared() {
        if service.activePeer == peer { service.activePeer = nil }
        service.markRead(peer)
    }

    func poll() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await service.refresh()
        }
    }

    func refresh() async { await service.refresh() }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = attachments.compactMap(\.prepared)
        guard canSend else { return }
        draft = ""
        attachments.removeAll()
        sentCount += 1
        Task {
            if !text.isEmpty { await perform { try await self.service.send(text, to: self.peer) } }
            for file in files { await perform { try await self.service.sendPrepared(file, to: self.peer) } }
        }
    }

    func retry(_ message: DMMessage) {
        Task { await perform { try await self.service.retry(message) } }
    }

    func discard(_ message: DMMessage) { service.discard(message) }

    private func perform(_ work: @escaping () async throws -> Void) async {
        do {
            try await work()
        } catch {
            failureCount += 1
            ToastCenter.shared.show(service.errorMessage(error), style: .error)
        }
    }

    func copy(_ message: DMMessage) {
        UIPasteboard.general.string = message.content
        ToastCenter.shared.show(L("copiedToClipboard"), style: .success)
    }

    func copyImage(_ image: UIImage) {
        UIPasteboard.general.image = image
        ToastCenter.shared.show(L("copiedToClipboard"), style: .success)
    }

    func removeAttachment(_ id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    func handlePicked() {
        let items = pickerItems
        pickerItems = []
        for item in items { Task { await prepare(item) } }
    }

    private func prepare(_ item: PhotosPickerItem) async {
        let types = item.supportedContentTypes
        let isVideo = types.contains { $0.conforms(to: .movie) }
        var draftItem = DMAttachmentDraft(thumbnail: nil, isVideo: isVideo)
        attachments.append(draftItem)
        let id = draftItem.id
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else { throw DMChatError.unreadable }
            let (data, mime, thumbnail) = await Self.normalize(raw, types: types, isVideo: isVideo)
            guard data.count <= DMService.maxFileSize else { throw DMChatError.tooLarge }
            draftItem.thumbnail = thumbnail
            update(id) { $0.thumbnail = thumbnail }
            let prepared = try await service.prepareFile(data, mimeType: mime)
            update(id) { $0.state = .ready(prepared) }
        } catch {
            attachments.removeAll { $0.id == id }
            let message: String
            switch error {
            case DMChatError.tooLarge: message = L("fileTooLarge")
            case DMChatError.unreadable: message = L("invalidMediaFileType")
            default: message = service.errorMessage(error)
            }
            ToastCenter.shared.show(message, style: .error)
        }
    }

    private func update(_ id: UUID, _ change: (inout DMAttachmentDraft) -> Void) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        change(&attachments[index])
    }

    private nonisolated static func normalize(_ data: Data, types: [UTType], isVideo: Bool) async -> (Data, String, UIImage?) {
        await Task.detached(priority: .userInitiated) { () -> (Data, String, UIImage?) in
            if isVideo {
                let type = types.first { $0.conforms(to: .movie) }
                let mime = type?.preferredMIMEType ?? (type == .quickTimeMovie ? "video/quicktime" : "video/mp4")
                return (data, mime, nil)
            }
            let thumbnail = ImagePipeline.downsample(data, maxPixel: 240)
            let bytes = [UInt8](data.prefix(4))
            if bytes.starts(with: [0x47, 0x49, 0x46]) { return (data, "image/gif", thumbnail) }
            if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return (data, "image/png", thumbnail) }
            if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return (data, "image/jpeg", thumbnail) }
            if let image = ImagePipeline.downsample(data, maxPixel: 4096), let jpeg = image.jpegData(compressionQuality: 0.88) {
                return (jpeg, "image/jpeg", thumbnail)
            }
            let type = types.first { $0.conforms(to: .image) }
            return (data, type?.preferredMIMEType ?? "application/octet-stream", thumbnail)
        }.value
    }
}

enum DMChatError: Error {
    case tooLarge, unreadable
}
