import Foundation
import QiqstrCore

@MainActor
enum ComposePublisher {
    static func publish(_ draft: ComposeDraft) async throws {
        guard !SearchService.containsSecret(draft.text) else { throw CoreError(L("composeSecretBlocked")) }
        let urls = draft.media.map(\.url)
        var extraTags = draft.media.map(imeta)
        if draft.contentWarningEnabled {
            let reason = draft.contentWarningReason.trimmingCharacters(in: .whitespacesAndNewlines)
            extraTags.append(reason.isEmpty ? ["content-warning"] : ["content-warning", reason])
        }
        let content = finalContent(draft)
        let service = InteractionService.shared
        switch draft.kind {
        case .newNote:
            if let poll = draft.poll {
                let options = pollOptions(poll)
                guard options.count >= 2 else { throw CoreError(L("feedPollNeedsOptions")) }
                _ = try await service.publishPoll(question: content, options: options, multiple: poll.multiple, endsAt: poll.endsAt, mediaUrls: urls, extraTags: extraTags)
            } else {
                _ = try await service.publishNote(content: content, mediaUrls: urls, extraTags: extraTags)
            }
        case .reply:
            let note = try await target(draft)
            _ = try await service.publishReply(to: note, content: content, mediaUrls: urls, extraTags: extraTags)
            await NoteInteractionStore.shared.markReplied(note.id)
        case .quote:
            let note = try await target(draft)
            _ = try await service.publishQuote(of: note, content: content, mediaUrls: urls, extraTags: extraTags)
        }
        DataBus.shared.feedChanged()
    }

    static func pollOptions(_ poll: ComposeDraftPoll) -> [String] {
        var seen: Set<String> = []
        return poll.options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private static func target(_ draft: ComposeDraft) async throws -> Note {
        guard let id = draft.targetId, let note = await NoteRepository.ensureNote(id) else { throw CoreError(L("eventNotFound")) }
        return note
    }

    private static func finalContent(_ draft: ComposeDraft) -> String {
        var content = draft.text
        for key in draft.mentions.keys.sorted(by: { $0.count > $1.count }) {
            if let value = draft.mentions[key] { content = content.replacingOccurrences(of: key, with: value) }
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func imeta(_ item: ComposeDraftMedia) -> [String] {
        var tag = ["imeta", "url \(item.url)", "m \(item.mimeType)"]
        if !item.sha256.isEmpty { tag.append("x \(item.sha256)") }
        if let width = item.width, let height = item.height { tag.append("dim \(Int(width))x\(Int(height))") }
        if let blurhash = item.blurhash { tag.append("blurhash \(blurhash)") }
        let alt = item.altText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !alt.isEmpty { tag.append("alt \(alt)") }
        if let duration = item.duration, duration > 0 { tag.append("duration \(Int(duration.rounded()))") }
        if let waveform = item.waveform, !waveform.isEmpty { tag.append("waveform \(waveform.map(String.init).joined(separator: " "))") }
        return tag
    }
}
