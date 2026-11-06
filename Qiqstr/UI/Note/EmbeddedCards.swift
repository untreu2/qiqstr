import SwiftUI

@MainActor
enum NoteEmbeddedCache {
    static var notes: [String: Note] = [:]
    static var articles: [String: Article] = [:]
    static var attempted: Set<String> = []
}

struct NoteQuoteCard: View {
    let noteId: String
    var depth = 0
    @State private var note: Note?
    @State private var failed = false
    @State private var cache = ProfileCache.shared

    init(noteId: String, depth: Int = 0, preloaded: Note? = nil) {
        self.noteId = noteId
        self.depth = depth
        _note = State(initialValue: preloaded ?? NoteEmbeddedCache.notes[noteId])
    }

    var body: some View {
        Group {
            if let note {
                Button { Router.shared.push(.thread(note.id)) } label: { content(note) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("note-quote-card")
            } else if failed {
                placeholder(L("eventNotFound"))
            } else {
                placeholder(nil)
            }
        }
        .task(id: noteId) {
            guard note == nil else { return }
            if let loaded = await NoteRepository.note(noteId) {
                NoteEmbeddedCache.notes[noteId] = loaded
                note = loaded
                return
            }
            guard !NoteEmbeddedCache.attempted.contains(noteId) else { failed = true; return }
            NoteEmbeddedCache.attempted.insert(noteId)
            if let loaded = await NoteRepository.ensureNote(noteId) {
                NoteEmbeddedCache.notes[noteId] = loaded
                note = loaded
            } else {
                failed = true
            }
        }
    }

    private func placeholder(_ text: String?) -> some View {
        HStack(spacing: 8) {
            if let text {
                Image(systemName: "exclamationmark.bubble").foregroundStyle(.secondary)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(AppColors.inputFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func content(_ note: Note) -> some View {
        let parsed = NoteContentCache.content(for: note)
        let profile = cache.profile(note.pubkey)
        let name = profile?.bestName ?? note.authorName ?? Profile.shortNpub(note.pubkey)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProfileAvatar(pubkey: note.pubkey, size: 22, fallbackURL: note.authorImage)
                Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(AppColors.textPrimary).lineLimit(1)
                Text("· \(TimeFormat.relative(note.createdAt))").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                if !parsed.isEmptyText {
                    Text(parsed.attributed(parsed.truncatedSegments ?? parsed.segments, font: .subheadline, cache: cache))
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(6)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let first = parsed.images.first {
                    NoteMediaImage(item: first, maxPixel: 800)
                        .frame(height: 150)
                        .clipShape(.rect(cornerRadius: 12, style: .continuous))
                } else if parsed.videos.first != nil {
                    Label(L("videoTapToPlay"), systemImage: "play.rectangle").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .noteSensitiveCover(note.id, reason: parsed.contentWarning, compact: true)
            if depth == 0, let nested = parsed.quoteIds.first {
                NoteQuoteCard(noteId: nested, depth: depth + 1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.inputFill.opacity(0.6))
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AppColors.border, lineWidth: 0.5))
    }
}

struct NoteArticleCard: View {
    let naddr: String
    @State private var article: Article?
    @State private var failed = false
    @State private var cache = ProfileCache.shared

    init(naddr: String) {
        self.naddr = naddr
        _article = State(initialValue: NoteEmbeddedCache.articles[naddr])
    }

    var body: some View {
        Button { Router.shared.push(.articleAddress(naddr)) } label: {
            HStack(spacing: 12) {
                if let image = article?.image {
                    RemoteImage(url: image, maxPixel: 300) { Rectangle().fill(AppColors.tile) }
                        .frame(width: 72, height: 72)
                        .clipShape(.rect(cornerRadius: 12, style: .continuous))
                } else {
                    IconTile(systemImage: "doc.richtext", size: 72, tint: AppColors.textSecondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("article")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(article.map { $0.title.isEmpty ? L("untitledArticle") : $0.title } ?? (failed ? L("articleNotFound") : L("article")))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let article {
                        Text(cache.profile(article.pubkey)?.bestName ?? article.authorName ?? Profile.shortNpub(article.pubkey))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if !failed {
                        ProgressView().controlSize(.mini)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(AppColors.inputFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("note-article-card")
        .task(id: naddr) {
            guard article == nil else { return }
            if let loaded = await NoteRepository.article(naddr: naddr) {
                NoteEmbeddedCache.articles[naddr] = loaded
                article = loaded
            } else {
                failed = true
            }
        }
    }
}
