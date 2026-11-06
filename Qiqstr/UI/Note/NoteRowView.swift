import SwiftUI

struct NoteRowView: View {
    let note: Note
    var showsThreadContext = true
    var compact = false
    var showsConnector = false
    @State private var cache = ProfileCache.shared
    @State private var store = NoteInteractionStore.shared
    @State private var actions = NoteActionHandler()

    var body: some View {
        if store.isDeleted(note.id) {
            EmptyView()
        } else {
            row
        }
    }

    private var row: some View {
        let avatarSize: CGFloat = compact ? 34 : 44
        return VStack(alignment: .leading, spacing: 6) {
            if note.isRepost, let reposter = note.repostedBy {
                NoteRepostHeader(pubkey: reposter, fallbackName: note.repostedByName)
                    .padding(.leading, avatarSize - 16)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    Button { Router.shared.push(.profile(note.pubkey)) } label: {
                        ProfileAvatar(pubkey: note.pubkey, size: avatarSize, fallbackURL: note.authorImage)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(authorName)
                    .accessibilityIdentifier("note-avatar")
                    if showsConnector {
                        Rectangle().fill(AppColors.divider).frame(width: 2).frame(maxHeight: .infinity)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    NoteAuthorLine(note: note, name: authorName, nip05: nip05)
                    if showsThreadContext, note.isReply, let target = replyTarget {
                        NoteReplyContextLine(pubkey: target)
                    }
                    NoteContentView(note: note, font: compact ? .subheadline : .body)
                    InteractionBarView(note: note, model: store.model(for: note), compact: compact, actions: actions)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, showsConnector ? 0 : 6)
        .contentShape(Rectangle())
        .onTapGesture { Router.shared.push(.thread(note.id)) }
        .contextMenu {
            NoteMenuItems(note: note, actions: actions)
        } preview: {
            NoteContextPreview(note: note, authorName: authorName)
        }
        .noteActionDialogs(actions)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("note-row")
    }

    private var authorName: String {
        cache.profile(note.pubkey)?.bestName ?? note.authorName ?? Profile.shortNpub(note.pubkey)
    }

    private var nip05: String? {
        cache.profile(note.pubkey)?.nip05.nilIfEmpty ?? note.authorNip05
    }

    private var replyTarget: String? {
        for tag in note.tags where tag.count > 4 && tag[0] == "e" && tag[3] == "reply" && tag[4].count == 64 { return tag[4] }
        let pTags = note.tags.filter { $0.count > 1 && $0[0] == "p" && $0[1].count == 64 }.map { $0[1] }
        return pTags.first { $0 != note.pubkey } ?? pTags.first
    }
}

struct NoteAuthorLine: View {
    let note: Note
    let name: String
    let nip05: String?
    var large = false

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(large ? .headline : .subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(1)
            if let nip05, !nip05.isEmpty {
                Image(systemName: "checkmark.seal.fill")
                    .font(large ? .subheadline : .caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L("nip05"))
                if large {
                    Text(nip05.hasPrefix("_@") ? String(nip05.dropFirst(2)) : nip05)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if !large {
                Text("· \(TimeFormat.relative(note.createdAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 0)
        }
    }
}

struct NoteRepostHeader: View {
    let pubkey: String
    var fallbackName: String?
    @State private var cache = ProfileCache.shared

    var body: some View {
        Button { Router.shared.push(.profile(pubkey)) } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.2.squarepath")
                Text(L("feedRepostedBy", ["name": cache.profile(pubkey)?.bestName ?? fallbackName ?? Profile.shortNpub(pubkey)]))
                    .lineLimit(1)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("note-repost-header")
        .task(id: pubkey) {
            if cache.profile(pubkey) == nil { await cache.load([pubkey]) }
        }
    }
}

struct NoteReplyContextLine: View {
    let pubkey: String
    @State private var cache = ProfileCache.shared

    var body: some View {
        Button { Router.shared.push(.profile(pubkey)) } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrowshape.turn.up.left").font(.caption)
                Text(L("replyingTo"))
                Text("@\(cache.profile(pubkey)?.bestName ?? Profile.shortNpub(pubkey))")
                    .fontWeight(.medium)
                    .foregroundStyle(AppColors.link)
                    .lineLimit(1)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("note-reply-context")
        .task(id: pubkey) {
            if cache.profile(pubkey) == nil { await cache.load([pubkey]) }
        }
    }
}

struct NoteContextPreview: View {
    let note: Note
    let authorName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProfileAvatar(pubkey: note.pubkey, size: 36, fallbackURL: note.authorImage)
                VStack(alignment: .leading, spacing: 0) {
                    Text(authorName).font(.headline).lineLimit(1)
                    Text(TimeFormat.relative(note.createdAt)).font(.footnote).foregroundStyle(.secondary)
                }
            }
            let content = NoteContentCache.content(for: note)
            if !content.isEmptyText {
                Text(content.attributed(content.truncatedSegments ?? content.segments, cache: ProfileCache.shared))
                    .font(.body)
                    .lineLimit(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let image = content.images.first {
                Color.clear
                    .frame(height: 180)
                    .overlay { RemoteImage(url: image.url, maxPixel: 800) { Rectangle().fill(AppColors.tile) } }
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background(AppColors.background)
    }
}

struct NoteSwipeActions: ViewModifier {
    let note: Note
    @State private var store = NoteInteractionStore.shared

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { Router.shared.compose(.reply(note)) } label: { Label(L("reply"), systemImage: "arrowshape.turn.up.left.fill") }
                    .tint(AppColors.reply)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                let reacted = store.model(for: note).counts.hasReacted
                Button { Task { await store.toggleReaction(note) } } label: { Label(L("reaction"), systemImage: reacted ? "heart.slash.fill" : "heart.fill") }
                    .tint(AppColors.reaction)
                Button { Task { await store.toggleRepost(note) } } label: { Label(L("repost"), systemImage: "arrow.2.squarepath") }
                    .tint(AppColors.repost)
            }
    }
}

extension View {
    func noteSwipeActions(_ note: Note) -> some View { modifier(NoteSwipeActions(note: note)) }
}
