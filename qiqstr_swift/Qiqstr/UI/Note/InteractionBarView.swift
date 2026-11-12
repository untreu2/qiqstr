import SwiftUI

struct InteractionBarView: View {
    let note: Note
    @Bindable var model: NoteCountsModel
    var compact = false
    var actions: NoteActionHandler
    @State private var store = NoteInteractionStore.shared
    @State private var replyTick = 0
    @State private var repostTick = 0
    @State private var likeTick = 0
    @State private var unlikeTick = 0
    @State private var showReactions = false
    @State private var longPressAt: Date?

    private static let likeContent = "+"

    var body: some View {
        HStack(spacing: 0) {
            replyButton
            Spacer(minLength: 4)
            repostMenu
            Spacer(minLength: 4)
            likeButton
            Spacer(minLength: 4)
            zapButton
            Spacer(minLength: 4)
            moreMenu
        }
        .font(compact ? .subheadline : .body)
        .foregroundStyle(.secondary)
        .sensoryFeedback(.impact(weight: .light), trigger: replyTick)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.9), trigger: likeTick)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: unlikeTick)
        .sensoryFeedback(.impact(weight: .medium), trigger: repostTick)
        .sensoryFeedback(.selection, trigger: showReactions) { _, new in new }
    }

    private var replyButton: some View {
        Button {
            replyTick += 1
            Router.shared.compose(.reply(note))
        } label: {
            InteractionLabel(symbol: "bubble.left", count: model.counts.replies, tint: nil, compact: compact, bounceTick: replyTick)
        }
        .buttonStyle(InteractionPressStyle())
        .accessibilityLabel(L("reply"))
        .accessibilityValue(model.counts.replies > 0 ? "\(model.counts.replies)" : "")
        .accessibilityIdentifier("note-reply")
    }

    private var repostMenu: some View {
        Menu {
            if model.counts.hasReposted {
                Button(L("undoRepost"), systemImage: "arrow.uturn.backward") { Task { await store.toggleRepost(note) } }
                Button(L("repostAgain"), systemImage: "arrow.2.squarepath") {
                    repostTick += 1
                    Task { await store.repostAgain(note) }
                }
            } else {
                Button(L("repost"), systemImage: "arrow.2.squarepath") {
                    repostTick += 1
                    Task { await store.toggleRepost(note) }
                }
            }
            Button(L("quote"), systemImage: "quote.bubble") { Router.shared.compose(.quote(note)) }
        } label: {
            InteractionLabel(
                symbol: "arrow.2.squarepath",
                count: model.counts.reposts,
                tint: model.counts.hasReposted ? AppColors.repost : nil,
                compact: compact,
                popTick: repostTick,
                burstTick: repostTick,
                rotateTick: repostTick
            )
        }
        .menuStyle(.button)
        .buttonStyle(InteractionPressStyle())
        .accessibilityLabel(L("repost"))
        .accessibilityValue(model.counts.hasReposted ? L("reposted") : "")
        .accessibilityIdentifier("note-repost")
    }

    private var likeEmoji: String? {
        guard model.counts.hasReacted, let reaction = model.myReaction, reaction != Self.likeContent, reaction != "❤️" else { return nil }
        return reaction
    }

    private var likeButton: some View {
        Button(action: tapLike) {
            InteractionLabel(
                symbol: model.counts.hasReacted ? "heart.fill" : "heart",
                emoji: likeEmoji,
                count: model.counts.reactions,
                tint: model.counts.hasReacted ? AppColors.reaction : nil,
                compact: compact,
                popTick: likeTick,
                burstTick: likeTick
            )
        }
        .buttonStyle(InteractionPressStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                longPressAt = Date()
                showReactions = true
            }
        )
        .popover(isPresented: $showReactions, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
            ReactionPicker(selected: model.counts.hasReacted ? (model.myReaction ?? Self.likeContent) : nil) { emoji in
                showReactions = false
                pick(emoji)
            }
            .presentationCompactAdaptation(.popover)
        }
        .disabled(model.isReacting)
        .accessibilityLabel(L("reaction"))
        .accessibilityValue(model.counts.hasReacted ? L("liked") : "")
        .accessibilityAction(named: L("reactWithEmoji")) { showReactions = true }
        .accessibilityIdentifier("note-like")
    }

    private func tapLike() {
        if let longPressAt, Date().timeIntervalSince(longPressAt) < 1.5 {
            self.longPressAt = nil
            return
        }
        longPressAt = nil
        if model.counts.hasReacted { unlikeTick += 1 } else { likeTick += 1 }
        Task { await store.toggleReaction(note) }
    }

    private func pick(_ emoji: String) {
        let content = emoji == "❤️" ? Self.likeContent : emoji
        if model.counts.hasReacted, (model.myReaction ?? Self.likeContent) == content { return }
        likeTick += 1
        Task { await store.react(note, with: content) }
    }

    private var zapButton: some View {
        ZapButton(note: note, hasZapped: model.counts.hasZapped) { state in
            ZapBarLabel(state: state, baseAmount: model.counts.zapAmount, compact: compact)
        }
        .buttonStyle(InteractionPressStyle())
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
        .buttonStyle(InteractionPressStyle())
        .accessibilityLabel(L("feedMoreActions"))
        .accessibilityIdentifier("note-more")
    }
}

struct InteractionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct InteractionLabel: View {
    let symbol: String
    var emoji: String? = nil
    let count: Int
    let tint: Color?
    var compact = false
    var popTick = 0
    var burstTick = 0
    var rotateTick = 0
    var bounceTick = 0
    var isPulsing = false
    var floatingText: String? = nil
    var floatingTick = 0

    private var color: Color { tint ?? .secondary }

    var body: some View {
        HStack(spacing: 5) {
            icon
                .background { ReactionBurst(trigger: burstTick, color: color, size: compact ? 34 : 40) }
                .overlay(alignment: .top) {
                    if let floatingText {
                        FloatingDelta(text: floatingText, color: color, trigger: floatingTick)
                    }
                }
            if count > 0 {
                Text(Sats.compact(count))
                    .font((compact ? Font.caption : Font.footnote).monospacedDigit().weight(tint == nil ? .regular : .semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: Double(count)))
                    .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
            }
        }
        .frame(minWidth: 48, minHeight: 34, alignment: .leading)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: count)
        .animation(.easeOut(duration: 0.18), value: tint)
    }

    @ViewBuilder
    private var icon: some View {
        Group {
            if let emoji {
                Text(emoji)
                    .font(compact ? .callout : .body)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            } else {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                    .symbolEffect(.rotate.clockwise.byLayer, options: .speed(1.8), value: rotateTick)
                    .symbolEffect(.bounce.up, value: bounceTick)
                    .symbolEffect(.pulse, isActive: isPulsing)
            }
        }
        .frame(width: compact ? 20 : 24, height: compact ? 20 : 24)
        .keyframeAnimator(initialValue: 1.0, trigger: popTick) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(0.55, duration: 0.09)
                SpringKeyframe(1.3, duration: 0.17, spring: .snappy)
                SpringKeyframe(1.0, duration: 0.32, spring: .bouncy(duration: 0.32, extraBounce: 0.15))
            }
        }
    }
}

private struct BurstFrame {
    var ring: CGFloat = 0.3
    var ringOpacity: Double = 0
    var ringWidth: CGFloat = 7
    var spread: CGFloat = 8
    var dots: Double = 0
    var dotScale: CGFloat = 1
}

struct ReactionBurst: View {
    let trigger: Int
    let color: Color
    var size: CGFloat = 40
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let dotCount = 8

    var body: some View {
        Group {
            if !reduceMotion {
                KeyframeAnimator(initialValue: BurstFrame(), trigger: trigger) { frame in
                    ZStack {
                        Circle()
                            .strokeBorder(color, lineWidth: max(frame.ringWidth, 0.1))
                            .scaleEffect(frame.ring)
                            .opacity(frame.ringOpacity)
                        ForEach(0..<Self.dotCount, id: \.self) { index in
                            let angle = Double(index) / Double(Self.dotCount) * 2 * .pi - .pi / 2
                            let radius = frame.spread * (index.isMultiple(of: 2) ? 1 : 0.78)
                            Circle()
                                .fill(color.opacity(index.isMultiple(of: 2) ? 1 : 0.6))
                                .frame(width: index.isMultiple(of: 2) ? 4 : 3, height: index.isMultiple(of: 2) ? 4 : 3)
                                .scaleEffect(frame.dotScale)
                                .offset(x: cos(angle) * radius, y: sin(angle) * radius)
                                .opacity(frame.dots)
                        }
                    }
                    .frame(width: size, height: size)
                } keyframes: { _ in
                    KeyframeTrack(\.ringOpacity) {
                        LinearKeyframe(0.85, duration: 0.02)
                        LinearKeyframe(0.85, duration: 0.12)
                        LinearKeyframe(0, duration: 0.2)
                    }
                    KeyframeTrack(\.ring) {
                        LinearKeyframe(0.3, duration: 0.02)
                        CubicKeyframe(1.05, duration: 0.32)
                    }
                    KeyframeTrack(\.ringWidth) {
                        LinearKeyframe(7, duration: 0.02)
                        CubicKeyframe(0, duration: 0.32)
                    }
                    KeyframeTrack(\.spread) {
                        LinearKeyframe(8, duration: 0.1)
                        CubicKeyframe(size * 0.62, duration: 0.42)
                    }
                    KeyframeTrack(\.dots) {
                        LinearKeyframe(0, duration: 0.1)
                        LinearKeyframe(1, duration: 0.04)
                        LinearKeyframe(1, duration: 0.18)
                        LinearKeyframe(0, duration: 0.2)
                    }
                    KeyframeTrack(\.dotScale) {
                        LinearKeyframe(1, duration: 0.3)
                        LinearKeyframe(0.2, duration: 0.22)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FloatFrame {
    var offset: CGFloat = 0
    var opacity: Double = 0
    var scale: CGFloat = 0.7
}

struct FloatingDelta: View {
    let text: String
    let color: Color
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            KeyframeAnimator(initialValue: FloatFrame(), trigger: trigger) { frame in
                    Text(text)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(color)
                        .fixedSize()
                        .scaleEffect(frame.scale)
                        .offset(y: frame.offset)
                        .opacity(frame.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.offset) {
                        LinearKeyframe(0, duration: 0.01)
                        CubicKeyframe(reduceMotion ? -14 : -30, duration: 0.9)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(1, duration: 0.12)
                        LinearKeyframe(1, duration: 0.5)
                        LinearKeyframe(0, duration: 0.3)
                    }
                    KeyframeTrack(\.scale) {
                        SpringKeyframe(1.15, duration: 0.2, spring: .snappy)
                        SpringKeyframe(1, duration: 0.3)
                    }
                }
                .offset(y: -6)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ZapBarLabel: View {
    let state: ZapButtonState
    var baseAmount: Int
    var compact = false
    @State private var zapTick = 0
    @State private var delta = 0

    var body: some View {
        InteractionLabel(
            symbol: state.isZapped ? "bolt.fill" : "bolt",
            count: baseAmount + state.addedSats,
            tint: state.isZapped ? AppColors.zap : nil,
            compact: compact,
            popTick: zapTick,
            burstTick: zapTick,
            isPulsing: state.isPending,
            floatingText: delta > 0 ? "+\(Sats.compact(delta))" : nil,
            floatingTick: zapTick
        )
        .opacity(state.isPending ? 0.85 : 1)
        .onChange(of: state.addedSats) { old, new in
            guard new > old else { return }
            delta = new - old
            zapTick += 1
        }
    }
}

struct ReactionPicker: View {
    let selected: String?
    let onPick: (String) -> Void
    @State private var appeared = false
    @State private var pickTick = 0

    static let emojis = ["❤️", "🤙", "🔥", "😂", "🫂", "👀", "⚡️", "💜"]

    private func isSelected(_ emoji: String) -> Bool {
        guard let selected else { return false }
        return selected == emoji || (emoji == "❤️" && selected == "+")
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(Self.emojis.enumerated()), id: \.element) { index, emoji in
                Button {
                    pickTick += 1
                    onPick(emoji)
                } label: {
                    Text(emoji)
                        .font(.title2)
                        .frame(width: 42, height: 46)
                        .background {
                            if isSelected(emoji) {
                                Circle().fill(.quaternary).frame(width: 40, height: 40)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(ReactionEmojiStyle())
                .scaleEffect(appeared ? 1 : 0.1)
                .offset(y: appeared ? 0 : 12)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.38, dampingFraction: 0.58).delay(Double(index) * 0.025), value: appeared)
                .accessibilityLabel(emoji)
                .accessibilityAddTraits(isSelected(emoji) ? .isSelected : [])
                .accessibilityIdentifier("reaction-\(index)")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .onAppear { appeared = true }
        .sensoryFeedback(.selection, trigger: pickTick)
        .accessibilityIdentifier("reaction-picker")
    }
}

private struct ReactionEmojiStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.4 : 1)
            .offset(y: configuration.isPressed ? -8 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
