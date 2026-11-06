import SwiftUI

struct InteractionBarView: View {
    let note: Note
    @Bindable var model: NoteCountsModel
    var compact = false
    var actions: NoteActionHandler
    @State private var store = NoteInteractionStore.shared

    var body: some View {
        HStack(spacing: 0) {
            replyButton
            Spacer(minLength: 4)
            repostMenu
            Spacer(minLength: 4)
            reactionMenu
            Spacer(minLength: 4)
            zapButton
            Spacer(minLength: 4)
            moreMenu
        }
        .font(compact ? .subheadline : .body)
        .foregroundStyle(.secondary)
        .sensoryFeedback(.impact(weight: .light), trigger: model.counts.hasReacted)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.counts.hasReposted)
    }

    private var replyButton: some View {
        Button { Router.shared.compose(.reply(note)) } label: {
            barLabel("bubble.left", count: model.counts.replies, tint: nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("reply"))
        .accessibilityIdentifier("note-reply")
    }

    private var repostMenu: some View {
        Menu {
            if model.counts.hasReposted {
                Button(L("undoRepost"), systemImage: "arrow.uturn.backward") { Task { await store.toggleRepost(note) } }
                Button(L("repostAgain"), systemImage: "arrow.2.squarepath") { Task { await store.repostAgain(note) } }
            } else {
                Button(L("repost"), systemImage: "arrow.2.squarepath") { Task { await store.toggleRepost(note) } }
            }
            Button(L("quote"), systemImage: "quote.bubble") { Router.shared.compose(.quote(note)) }
        } label: {
            barLabel("arrow.2.squarepath", count: model.counts.reposts, tint: model.counts.hasReposted ? AppColors.repost : nil)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(L("repost"))
        .accessibilityIdentifier("note-repost")
    }

    private var reactionMenu: some View {
        Menu {
            ForEach(["🤙", "🔥", "😂", "🫂", "👀", "⚡️", "💜"], id: \.self) { emoji in
                Button(emoji) { Task { await store.toggleReaction(note, content: emoji) } }
            }
        } label: {
            barLabel(model.counts.hasReacted ? "heart.fill" : "heart", count: model.counts.reactions, tint: model.counts.hasReacted ? AppColors.reaction : nil)
                .contentTransition(.symbolEffect(.replace))
        } primaryAction: {
            Task { await store.toggleReaction(note) }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(model.isReacting)
        .accessibilityLabel(L("reaction"))
        .accessibilityIdentifier("note-like")
    }

    private var zapButton: some View {
        Button { Router.shared.sheet = .zap(note) } label: {
            barLabel(model.counts.hasZapped ? "bolt.fill" : "bolt", count: model.counts.zapAmount, tint: model.counts.hasZapped ? AppColors.zap : nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("zap"))
        .accessibilityIdentifier("note-zap")
    }

    private var moreMenu: some View {
        Menu {
            NoteMenuItems(note: note, actions: actions)
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(L("feedMoreActions"))
        .accessibilityIdentifier("note-more")
    }

    private func barLabel(_ symbol: String, count: Int, tint: Color?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(tint ?? Color.secondary)
            if count > 0 {
                Text(Sats.compact(count))
                    .font((compact ? Font.caption : Font.footnote).monospacedDigit())
                    .foregroundStyle(tint ?? Color.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: Double(count)))
            }
        }
        .frame(minWidth: 44, minHeight: 32, alignment: .leading)
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.2), value: count)
    }
}
