import SwiftUI

struct DMMessageBubble: View {
    let message: DMMessage
    let isFirstInGroup: Bool
    let isLastInGroup: Bool
    let onCopy: (DMMessage) -> Void
    let onCopyImage: (UIImage) -> Void
    let onRetry: (DMMessage) -> Void
    let onDiscard: (DMMessage) -> Void
    var onQuote: (DMMessage) -> Void = { _ in }
    var onInfo: (DMMessage) -> Void = { _ in }
    var searchQuery = ""
    var isCurrentMatch = false
    var senderName: String? = nil
    var reactions: [DMReaction] = []
    var onReact: ((DMMessage, EmojiChoice) -> Void)? = nil
    @State private var cache = ProfileCache.shared
    @State private var showsEmojiPicker = false

    private var mine: Bool { message.isMine }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if mine { Spacer(minLength: 56) }
            if message.state == .failed { failedBadge }
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                if let senderName, isFirstInGroup, !mine {
                    Text(senderName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .accessibilityIdentifier("dm-message-sender")
                }
                bubble
                    .overlay {
                        if isCurrentMatch {
                            bubbleShape.stroke(AppColors.link, lineWidth: 2)
                        }
                    }
                    .animation(.smooth(duration: 0.2), value: isCurrentMatch)
                if !reactions.isEmpty { reactionRow }
                if isLastInGroup || message.state != .sent { footer }
            }
            if !mine { Spacer(minLength: 56) }
        }
        .padding(.top, isFirstInGroup ? 10 : 2)
        .sheet(isPresented: $showsEmojiPicker) {
            EmojiPickerSheet { onReact?(message, $0) }
        }
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
        .accessibilityIdentifier("dm-message-\(message.id)")
    }

    private var bubbleShape: UnevenRoundedRectangle {
        let large: CGFloat = 24
        let small: CGFloat = 10
        let tail: CGFloat = 24
        if mine {
            return UnevenRoundedRectangle(topLeadingRadius: large, bottomLeadingRadius: large, bottomTrailingRadius: isLastInGroup ? tail : small, topTrailingRadius: isFirstInGroup ? large : small, style: .continuous)
        }
        return UnevenRoundedRectangle(topLeadingRadius: isFirstInGroup ? large : small, bottomLeadingRadius: isLastInGroup ? tail : small, bottomTrailingRadius: large, topTrailingRadius: large, style: .continuous)
    }

    @ViewBuilder
    private var bubble: some View {
        if message.isFile {
            DMMediaGate(message: message, shape: bubbleShape) {
                DMMediaBubble(message: message, shape: bubbleShape, onCopyImage: onCopyImage, menu: { menuItems })
                    .opacity(message.state == .sending ? 0.7 : 1)
            }
        } else if let imageURL = soleImageURL {
            DMMediaGate(message: message, shape: bubbleShape) {
                RemoteImage(url: imageURL, maxPixel: 720, contentMode: .fill) {
                    ZStack {
                        Rectangle().fill(AppColors.tile)
                        ProgressView()
                    }
                }
                .frame(width: 240, height: 240)
                .clipShape(bubbleShape)
                .contentShape(bubbleShape)
                .contextMenu { menuItems }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("dmSpokenPhoto", ["sender": message.spokenSender]))
                .accessibilityAddTraits(.isImage)
            }
        } else {
            Text(DMText.attributed(message.content, mine: mine, cache: cache, highlighting: searchQuery))
                .font(.body)
                .foregroundStyle(mine ? AppColors.background : AppColors.textPrimary)
                .tint(mine ? AppColors.background : AppColors.textPrimary)
                .textSelection(.disabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(mine ? AppColors.textPrimary : AppColors.tile, in: bubbleShape)
                .opacity(message.state == .sending ? 0.7 : 1)
                .contentShape(.contextMenuPreview, bubbleShape)
                .contextMenu { menuItems }
                .accessibilityLabel(L("dmSpokenMessage", ["sender": message.spokenSender, "text": message.content]))
                .environment(\.openURL, OpenURLAction { url in
                    Router.shared.open(url: url)
                    return .handled
                })
        }
    }

    private var soleImageURL: String? {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace), DMText.isImageURL(trimmed) else { return nil }
        return trimmed
    }

    private var reactionGroups: [DMReactionGroup] {
        let me = Session.shared.pubkey
        let grouped = Dictionary(grouping: reactions, by: \.emoji)
        let list: [DMReactionGroup] = grouped.map { emoji, items in
            DMReactionGroup(emoji: emoji, count: items.count, url: items.first?.emojiURL, mine: items.contains { $0.sender == me })
        }
        return list.sorted { $0.count == $1.count ? $0.emoji < $1.emoji : $0.count > $1.count }
    }

    private var reactionRow: some View {
        HStack(spacing: 4) {
            ForEach(reactionGroups) { group in
                DMReactionChip(group: group, enabled: onReact != nil && message.state == .sent) {
                    if let url = group.url, let code = CustomEmoji.shortcode(in: group.emoji) {
                        onReact?(message, .custom(CustomEmoji(shortcode: code, url: url)))
                    } else {
                        onReact?(message, .unicode(group.emoji))
                    }
                }
            }
        }
        .padding(.top, -2)
        .accessibilityIdentifier("dm-reactions")
    }

    @ViewBuilder
    private var menuItems: some View {
        if onReact != nil, message.state == .sent {
            Menu {
                ForEach(ReactionPicker.emojis, id: \.self) { emoji in
                    Button(emoji) { onReact?(message, .unicode(emoji)) }
                }
                Button(L("emojiMore"), systemImage: "face.smiling") { showsEmojiPicker = true }
            } label: {
                Label(L("dmReact"), systemImage: "face.smiling")
            }
            .accessibilityIdentifier("dm-react")
        }
        if !message.isFile {
            Button {
                onCopy(message)
            } label: {
                Label(L("copy"), systemImage: "doc.on.doc")
            }
            Button {
                onQuote(message)
            } label: {
                Label(L("reply"), systemImage: "arrowshape.turn.up.left")
            }
        }
        Button {
            onInfo(message)
        } label: {
            Label(L("dmInfo"), systemImage: "info.circle")
        }
        if message.state == .failed {
            Divider()
            Button {
                onRetry(message)
            } label: {
                Label(L("retry"), systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) {
                onDiscard(message)
            } label: {
                Label(L("delete"), systemImage: "trash")
            }
        }
    }

    private var failedBadge: some View {
        Menu {
            Button {
                onRetry(message)
            } label: {
                Label(L("dmTryAgain"), systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) {
                onDiscard(message)
            } label: {
                Label(L("delete"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(AppColors.error)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(L("dmSendFailed"))
        .accessibilityIdentifier("dm-message-failed-menu")
        .transition(.scale.combined(with: .opacity))
    }

    @ViewBuilder
    private var footer: some View {
        switch message.state {
        case .sending:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(L("dmSending"))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
        case .failed:
            Button {
                onRetry(message)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(L("dmFailedTapRetry"))
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppColors.error)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .accessibilityIdentifier("dm-message-retry")
        case .sent:
            HStack(spacing: 4) {
                if message.isFile, message.file?.isEncrypted == false {
                    Image(systemName: "exclamationmark.triangle")
                    Text("\(L("notEncrypted")) · \(DMFormat.time(message.date))")
                } else {
                    Image(systemName: "lock.fill").opacity(0.6)
                    Text(DMFormat.time(message.date))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .padding(.horizontal, 6)
        }
    }
}

enum DMText {
    private static let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp"]
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let nostrPattern = try? NSRegularExpression(pattern: "nostr:(npub1|nprofile1|note1|nevent1|naddr1)[02-9ac-hj-np-z]+", options: [.caseInsensitive])

    static func isImageURL(_ value: String) -> Bool {
        guard let url = URL(string: value), url.scheme?.hasPrefix("http") == true else { return false }
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    static func attributed(_ text: String, mine: Bool, cache: ProfileCache, highlighting query: String) -> AttributedString {
        var result = attributed(text, mine: mine, cache: cache)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return result }
        var start = result.startIndex
        while start < result.endIndex, let range = result[start...].range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) {
            result[range].backgroundColor = AppColors.link.opacity(mine ? 0.55 : 0.3)
            start = range.upperBound
        }
        return result
    }

    static func attributed(_ text: String, mine: Bool, cache: ProfileCache) -> AttributedString {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var spans: [(NSRange, URL, String?)] = []
        nostrPattern?.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let range = match?.range else { return }
            let entity = ns.substring(with: range)
            guard let url = URL(string: entity) else { return }
            let bech = String(entity.dropFirst(6))
            var label: String?
            if bech.hasPrefix("npub1") || bech.hasPrefix("nprofile1") {
                let hex = Nip19.pubkeyHex(from: bech)
                label = "@" + (hex.flatMap { cache.profile($0)?.bestName } ?? (String(bech.prefix(12)) + "…"))
            } else {
                label = String(bech.prefix(14)) + "…"
            }
            spans.append((range, url, label))
        }
        linkDetector?.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match, let url = match.url, url.scheme?.hasPrefix("http") == true else { return }
            if spans.contains(where: { NSIntersectionRange($0.0, match.range).length > 0 }) { return }
            spans.append((match.range, url, nil))
        }
        spans.sort { $0.0.location < $1.0.location }
        var result = AttributedString()
        var cursor = 0
        for (range, url, label) in spans {
            if range.location > cursor {
                result += AttributedString(ns.substring(with: NSRange(location: cursor, length: range.location - cursor)))
            }
            var link = AttributedString(label ?? ns.substring(with: range))
            link.link = url
            link.underlineStyle = .single
            if label != nil { link.font = .body.weight(.semibold) }
            result += link
            cursor = range.location + range.length
        }
        if cursor < ns.length {
            result += AttributedString(ns.substring(from: cursor))
        }
        return result
    }
}

struct DMReactionGroup: Identifiable, Hashable {
    var id: String { emoji }
    let emoji: String
    let count: Int
    let url: String?
    let mine: Bool
}

struct DMReactionChip: View {
    let group: DMReactionGroup
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let url = group.url {
                    CustomEmojiImage(url: url, size: 16)
                } else {
                    Text(group.emoji).font(.footnote)
                }
                if group.count > 1 {
                    Text("\(group.count)").font(.caption2.weight(.semibold).monospacedDigit())
                }
            }
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(group.mine ? AppColors.link.opacity(0.18) : AppColors.tile, in: .capsule)
            .overlay {
                if group.mine { Capsule().stroke(AppColors.link.opacity(0.6), lineWidth: 1) }
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("\(group.emoji) \(group.count)")
        .accessibilityAddTraits(group.mine ? .isSelected : [])
    }
}
