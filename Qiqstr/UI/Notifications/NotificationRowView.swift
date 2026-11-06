import SwiftUI

extension NotificationKind {
    var symbol: String {
        switch self {
        case .reaction: "heart.fill"
        case .repost: "arrow.2.squarepath"
        case .reply: "bubble.left.fill"
        case .mention: "at"
        case .quote: "quote.bubble.fill"
        case .zap: "bolt.fill"
        case .unknown: "bell.fill"
        }
    }

    var tint: Color {
        switch self {
        case .reaction: AppColors.reaction
        case .repost: AppColors.repost
        case .reply: AppColors.reply
        case .zap: AppColors.zap
        case .mention, .quote, .unknown: AppColors.textSecondary
        }
    }

    var actionText: String {
        switch self {
        case .reaction: L("reactedToYourPost")
        case .repost: L("repostedYourPost")
        case .reply: L("repliedToYourPost")
        case .mention: L("mentionedYou")
        case .quote: L("quotedYourPost")
        case .zap: L("zappedYou")
        case .unknown: L("interactedWithYou")
        }
    }
}

struct NotificationRowView: View {
    let group: NotificationGroup
    let isUnread: Bool
    @State private var cache = ProfileCache.shared
    @ScaledMetric(relativeTo: .subheadline) private var avatarSize: CGFloat = 42
    @ScaledMetric(relativeTo: .subheadline) private var stackedAvatarSize: CGFloat = 34
    @ScaledMetric(relativeTo: .caption2) private var badgeSize: CGFloat = 20

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatars
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    headline
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(timestamp)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if isUnread {
                        Circle().fill(AppColors.accent).frame(width: 8, height: 8)
                            .accessibilityLabel(L("notificationUnread"))
                    }
                }
                if showsContent {
                    let text = NotificationText.readable(group.lead.content)
                    if !text.isEmpty {
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(6)
                            .multilineTextAlignment(.leading)
                    }
                }
                if let target = group.targetNoteId, !target.isEmpty, group.kind != .mention {
                    NotificationNotePreview(noteId: target)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var showsContent: Bool {
        !group.isGrouped && (group.kind == .reply || group.kind == .mention || group.kind == .quote)
    }

    private var timestamp: String {
        TimeFormat.now - group.createdAt < 60 ? L("now") : TimeFormat.relative(group.createdAt)
    }

    @ViewBuilder
    private var avatars: some View {
        let shown = Array(group.authors.prefix(3))
        ZStack(alignment: .bottomTrailing) {
            if shown.count <= 1 {
                Button { open(shown.first) } label: {
                    ProfileAvatar(pubkey: group.lead.fromPubkey, size: avatarSize, fallbackURL: group.lead.fromImage)
                }
                .buttonStyle(.plain)
            } else {
                Button { open(shown.first) } label: {
                    HStack(spacing: -14) {
                        ForEach(Array(shown.enumerated()), id: \.element) { index, pubkey in
                            ProfileAvatar(pubkey: pubkey, size: stackedAvatarSize, fallbackURL: group.items.first { $0.fromPubkey == pubkey }?.fromImage)
                                .overlay(Circle().stroke(AppColors.background, lineWidth: 2))
                                .zIndex(Double(shown.count - index))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            kindBadge.offset(x: 4, y: 4)
        }
        .accessibilityIdentifier("notification-avatar")
    }

    private var kindBadge: some View {
        ZStack {
            Circle().fill(AppColors.background).frame(width: badgeSize, height: badgeSize)
            if group.kind == .reaction, !group.isGrouped, let emoji = reactionEmoji {
                Text(emoji).font(.caption2)
            } else {
                Image(systemName: group.kind.symbol)
                    .font(.caption2.weight(.bold))
                    .imageScale(.small)
                    .foregroundStyle(group.kind.tint)
            }
        }
    }

    private var reactionEmoji: String? {
        let content = group.lead.content.trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty, content != "+", content.count <= 2, !content.hasPrefix(":") else { return nil }
        return content
    }

    private var headline: Text {
        var text = AttributedString()
        let authors = group.authors.isEmpty ? [group.lead.fromPubkey] : group.authors
        if authors.count <= 3 {
            for (i, pk) in authors.enumerated() {
                if i > 0 { text.append(AttributedString(", ")) }
                text.append(bold(name(pk)))
            }
        } else {
            text.append(bold(name(authors[0])))
            text.append(AttributedString(", "))
            text.append(bold(name(authors[1])))
            text.append(AttributedString(" " + L("andCountOthers", ["count": authors.count - 2])))
        }
        text.append(AttributedString(" " + group.kind.actionText))
        if group.kind == .zap, group.totalZapAmount > 0 {
            var amount = bold(" " + SettingsICU.format("notificationZapSatsCount", ["count": group.totalZapAmount]))
            amount.foregroundColor = AppColors.zap
            text.append(amount)
        }
        return Text(text).font(.subheadline)
    }

    private func bold(_ string: String) -> AttributedString {
        var run = AttributedString(string)
        run.font = .subheadline.weight(.semibold)
        return run
    }

    private func name(_ pubkey: String) -> String {
        if let profile = cache.profile(pubkey) {
            if !profile.name.isEmpty { return profile.name }
            if !profile.displayName.isEmpty { return profile.displayName }
        }
        if let fromName = group.items.first(where: { $0.fromPubkey == pubkey })?.fromName { return fromName }
        return Profile.shortNpub(pubkey)
    }

    private func open(_ pubkey: String?) {
        guard let pubkey, !pubkey.isEmpty else { return }
        Router.shared.push(.profile(pubkey))
    }
}
