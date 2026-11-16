import SwiftUI

struct NoteContentView: View {
    let note: Note
    var font: Font = .body
    var selectable = false
    var expandedByDefault = false
    @State private var expanded = false
    @State private var cache = ProfileCache.shared

    var body: some View {
        let content = NoteContentCache.content(for: note)
        let isTruncated = content.truncatedSegments != nil && !expanded && !expandedByDefault
        VStack(alignment: .leading, spacing: 10) {
            if !content.isEmptyText {
                VStack(alignment: .leading, spacing: 4) {
                    textView(content, truncated: isTruncated)
                    if isTruncated {
                        Button {
                            withAnimation(.snappy(duration: 0.25)) { expanded = true }
                        } label: {
                            Text(L("feedShowMore"))
                                .font(font.weight(.semibold))
                                .foregroundStyle(AppColors.link)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("note-show-more")
                    }
                }
            }
            if let poll = NotePoll(id: note.id, tags: note.tags) {
                NotePollView(poll: poll, author: note.pubkey)
            }
            if let goal = ZapGoal(note: note) {
                ZapGoalView(goal: goal, note: note)
            }
            if !content.media.isEmpty {
                NoteMediaGridView(media: content.media)
            }
            ForEach(content.audio) { item in
                NoteAudioView(item: item)
            }
            if let link = content.previewLink, !MediaPolicy.shared.defersMedia {
                NoteLinkPreviewView(url: link)
            }
            ForEach(content.quoteIds, id: \.self) { id in
                NoteQuoteCard(noteId: id)
            }
            ForEach(content.articleIds, id: \.self) { naddr in
                NoteArticleCard(naddr: naddr)
            }
        }
        .noteSensitiveCover(note.id, reason: content.contentWarning)
        .environment(\.openURL, OpenURLAction { NoteLink.handle($0) })
        .task(id: content.mentionPubkeys) {
            let missing = content.mentionPubkeys.filter { cache.profile($0) == nil }
            if !missing.isEmpty { await cache.load(missing) }
        }
    }

    @ViewBuilder
    private func textView(_ content: NoteContent, truncated: Bool) -> some View {
        let text = content.text(truncated ? (content.truncatedSegments ?? content.segments) : content.segments, font: font, cache: cache, emojis: InlineEmojiStore.shared)
            .font(font)
            .foregroundStyle(AppColors.textPrimary)
            .lineSpacing(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        if selectable {
            text.textSelection(.enabled)
        } else {
            text
        }
    }
}
