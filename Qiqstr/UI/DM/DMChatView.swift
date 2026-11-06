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
                DMInputBar(model: model, focus: $inputFocused, placeholder: L("dmMessagePlaceholder", ["name": profile?.bestName ?? Profile.shortNpub(pubkey)]))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .principal) { header }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) { moreMenu }
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
                ProfileAvatar(pubkey: pubkey, size: 30)
                Text(profile?.bestName ?? Profile.shortNpub(pubkey))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.leading, 4)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: 230)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel(L("dmViewProfile"))
        .accessibilityIdentifier("dm-chat-header")
    }

    private var moreMenu: some View {
        Menu {
            Button(L("dmViewProfile"), systemImage: "person.crop.circle") { router.push(.profile(pubkey)) }
            Button(L("dmCopyNpub"), systemImage: "doc.on.doc") {
                UIPasteboard.general.string = Nip19.npub(pubkey)
                ToastCenter.shared.show(L("copiedToClipboard"), style: .success)
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(L("profileMoreActions"))
        .accessibilityIdentifier("dm-chat-more")
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
                        .font(.title3.weight(.semibold))
                    Text(L("noMessagesYet"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label(L("dmEncryptionNotice"), systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
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
