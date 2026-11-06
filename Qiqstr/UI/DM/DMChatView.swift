import SwiftUI

struct DMChatView: View {
    let pubkey: String
    @State private var model: DMChatViewModel
    @State private var cache = ProfileCache.shared
    @State private var router = Router.shared
    @State private var position = ScrollPosition(edge: .bottom)
    @FocusState private var inputFocused: Bool

    init(pubkey: String) {
        self.pubkey = pubkey
        _model = State(initialValue: DMChatViewModel(peer: pubkey))
    }

    private var profile: Profile? { cache.profile(pubkey) }
    private var lastMessage: DMMessage? { model.messages.last }

    var body: some View {
        messageList
            .background(AppColors.background)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DMInputBar(model: model, focus: $inputFocused)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .principal) { header }
            }
            .task { await model.appeared() }
            .task { await model.poll() }
            .task(id: pubkey) { await cache.load([pubkey]) }
            .onDisappear { model.disappeared() }
            .onChange(of: lastMessage?.id) { old, new in
                guard old != nil, new != nil else {
                    position.scrollTo(edge: .bottom)
                    return
                }
                withAnimation(.smooth(duration: 0.3)) { position.scrollTo(edge: .bottom) }
            }
            .onChange(of: inputFocused) {
                if inputFocused {
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        withAnimation(.smooth(duration: 0.25)) { position.scrollTo(edge: .bottom) }
                    }
                }
            }
            .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: lastIncomingId)
    }

    private var lastIncomingId: String? { model.messages.last { !$0.isMine }?.id }

    private var header: some View {
        Button {
            router.push(.profile(pubkey))
        } label: {
            HStack(spacing: 8) {
                ProfileAvatar(pubkey: pubkey, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile?.bestName ?? Profile.shortNpub(pubkey))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill").font(.system(size: 8))
                        Text(profile?.nip05.nilIfEmpty ?? Profile.shortNpub(pubkey))
                            .lineLimit(1)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .frame(maxWidth: 240)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("dmViewProfile"))
        .accessibilityIdentifier("dm-chat-header")
    }

    @ViewBuilder
    private var messageList: some View {
        if model.isLoading {
            LoadingView().accessibilityIdentifier("dm-chat-loading")
        } else if model.messages.isEmpty {
            ScrollView {
                VStack(spacing: 14) {
                    ProfileAvatar(pubkey: pubkey, size: 84)
                    Text(profile?.bestName ?? Profile.shortNpub(pubkey))
                        .font(.system(size: 20, weight: .semibold))
                    Text(L("noMessagesYet"))
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.textSecondary)
                    Label(L("dmEncryptionNotice"), systemImage: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.refresh() }
            .accessibilityIdentifier("dm-chat-empty")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        rowView(row)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .animation(.smooth(duration: 0.3), value: model.messages.count)
            }
            .scrollPosition($position)
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("dm-chat-messages")
        }
    }

    @ViewBuilder
    private func rowView(_ row: DMChatRow) -> some View {
        switch row.kind {
        case .day(let date):
            Text(DMFormat.daySeparator(date))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .glassEffect(.regular, in: .capsule)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .padding(.bottom, 6)
        case .message(let message, let first, let last):
            DMMessageBubble(
                message: message,
                isFirstInGroup: first,
                isLastInGroup: last,
                onCopy: model.copy,
                onCopyImage: model.copyImage,
                onRetry: model.retry,
                onDiscard: model.discard
            )
        }
    }
}
