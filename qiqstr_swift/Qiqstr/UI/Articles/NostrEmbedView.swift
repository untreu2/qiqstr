import SwiftUI

struct NostrEmbedView: View {
    let entity: String

    var body: some View {
        if entity.hasPrefix("npub1") || entity.hasPrefix("nprofile1"), let pubkey = Nip19.pubkeyHex(from: entity) {
            ProfileEmbed(pubkey: pubkey)
        } else if entity.hasPrefix("naddr1") {
            ArticleEmbed(naddr: entity)
        } else if let id = Nip19.decode(entity) {
            NoteEmbed(noteId: id)
        } else {
            MarkdownText(text: entity)
        }
    }
}

private struct ProfileEmbed: View {
    let pubkey: String
    @State private var cache = ProfileCache.shared

    var body: some View {
        Button { Router.shared.push(.profile(pubkey)) } label: {
            HStack(spacing: 12) {
                ProfileAvatar(pubkey: pubkey, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cache.profile(pubkey)?.bestName ?? Profile.shortNpub(pubkey))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let nip05 = cache.profile(pubkey)?.nip05.nilIfEmpty {
                        Text(nip05).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(AppColors.inputFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("markdown-profile-\(pubkey)")
    }
}

private struct ArticleEmbed: View {
    let naddr: String
    @State private var article: Article?
    @State private var failed = false

    var body: some View {
        Group {
            if let article {
                Button { Router.shared.push(.article(article.id)) } label: { CompactArticleCard(article: article) }
                    .buttonStyle(PressableStyle())
            } else if failed {
                Button { Router.shared.push(.articleAddress(naddr)) } label: {
                    EmbedPlaceholder(systemImage: "doc.richtext", title: L("articleNotFound"))
                }
                .buttonStyle(PressableStyle())
            } else {
                EmbedPlaceholder(systemImage: "doc.richtext", title: L("loading"), loading: true)
            }
        }
        .accessibilityIdentifier("markdown-article-embed")
        .task(id: naddr) {
            guard let address = ArticleAddress(naddr: naddr) else { failed = true; return }
            if let local = await ArticleService.article(at: address) { article = local; return }
            article = await ArticleService.fetch(address: address)
            failed = article == nil
        }
    }
}

private struct NoteEmbed: View {
    let noteId: String
    @State private var note: Note?
    @State private var failed = false

    var body: some View {
        Group {
            if let note {
                NoteRowView(note: note, showsThreadContext: false)
                    .background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(AppColors.border, lineWidth: 1))
            } else if failed {
                Button { Router.shared.push(.thread(noteId)) } label: {
                    EmbedPlaceholder(systemImage: "text.bubble", title: L("noteNotFound"))
                }
                .buttonStyle(PressableStyle())
            } else {
                EmbedPlaceholder(systemImage: "text.bubble", title: L("loading"), loading: true)
            }
        }
        .accessibilityIdentifier("markdown-note-embed")
        .task(id: noteId) {
            note = await ArticleService.note(id: noteId)
            failed = note == nil
        }
    }
}

private struct EmbedPlaceholder: View {
    let systemImage: String
    let title: String
    var loading = false

    var body: some View {
        HStack(spacing: 10) {
            if loading { ProgressView() } else { Image(systemName: systemImage).foregroundStyle(.secondary) }
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppColors.inputFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
