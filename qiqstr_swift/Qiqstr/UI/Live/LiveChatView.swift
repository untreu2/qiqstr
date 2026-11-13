import SwiftUI

struct LiveChatList: View {
    let messages: [LiveChatMessage]
    let loaded: Bool
    let isLive: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !loaded {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else if messages.isEmpty {
                        Text(L(isLive ? "liveChatEmpty" : "liveChatEmptyEnded"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                    ForEach(messages) { message in
                        LiveChatRow(message: message).id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .accessibilityIdentifier("live-chat")
    }
}

struct LiveChatRow: View {
    let message: LiveChatMessage
    @State private var cache = ProfileCache.shared
    @State private var reportTarget: ReportTarget?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { Router.shared.push(.profile(message.pubkey)) } label: {
                ProfileAvatar(pubkey: message.pubkey, size: 28)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(cache.profile(message.pubkey)?.bestName.nilIfEmpty ?? Profile.shortNpub(message.pubkey))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(TimeFormat.relative(message.createdAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(message.content)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .contentShape(Rectangle())
        .contextMenu {
            if message.pubkey != Session.shared.pubkey {
                Button(L("mute"), systemImage: "speaker.slash", role: .destructive) {
                    Task {
                        await Moderation.mute(message.pubkey)
                        ToastCenter.shared.show(L("feedUserMuted"), style: .success)
                    }
                }
                Button(L("report"), systemImage: "flag", role: .destructive) {
                    reportTarget = ReportTarget(pubkey: message.pubkey, eventId: message.id)
                }
            }
        }
        .reportSheet($reportTarget)
    }
}

struct LiveChatInput: View {
    @Binding var text: String
    let canSend: Bool
    let isSending: Bool
    let onSend: () -> Void

    var body: some View {
        GlassEffectContainer {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(L("liveChatPlaceholder"), text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                    .submitLabel(.send)
                    .onSubmit { if canSend { onSend() } }
                    .accessibilityIdentifier("live-chat-field")
                Button(action: onSend) {
                    Group {
                        if isSending { ProgressView() } else { Image(systemName: "arrow.up").font(.body.weight(.semibold)) }
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.glassProminent)
                .foregroundStyle(AppColors.background)
                .buttonBorderShape(.circle)
                .disabled(!canSend)
                .accessibilityLabel(L("liveSend"))
                .accessibilityIdentifier("live-chat-send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
