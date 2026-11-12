import SwiftUI

struct DMChatView: View {
    let pubkey: String
    @State private var model: DMChatViewModel
    @State private var cache = ProfileCache.shared
    @State private var router = Router.shared
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var awayFromBottom = false
    @State private var unseenCount = 0
    @State private var searchPresented = false
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
            .overlay(alignment: .bottomTrailing) { jumpToLatest }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.isSearching {
                    matchNavigator
                } else {
                    DMInputBar(model: model, focus: $inputFocused, placeholder: L("dmMessagePlaceholder", ["name": profile?.bestName ?? Profile.shortNpub(pubkey)]))
                }
            }
            .searchable(text: $model.searchQuery, isPresented: $searchPresented, placement: .navigationBarDrawer(displayMode: .automatic), prompt: L("dmSearchPrompt"))
            .onSubmit(of: .search) { model.previousMatch() }
            .onChange(of: searchPresented) { if !searchPresented { model.searchQuery = "" } }
            .onChange(of: model.currentMatchId) {
                guard let id = model.currentMatchId else { return }
                withAnimation(.smooth(duration: 0.3)) { position.scrollTo(id: id, anchor: .center) }
            }
            .onChange(of: model.focusRequest) { inputFocused = true }
            .onChange(of: model.attachments.count) { old, new in
                guard new > old, !awayFromBottom else { return }
                withAnimation(.smooth(duration: 0.25)) { position.scrollTo(edge: .bottom) }
            }
            .sheet(item: $model.infoMessage) { message in
                DMMessageInfoSheet(message: message, deliveryRelays: model.deliveryRelays(for: message), chatRelays: model.chatRelays())
                    .presentationDetents([.medium, .large])
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
                guard !model.isSearching else { return }
                if awayFromBottom, lastMessage?.isMine == false {
                    unseenCount += 1
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
            Button(L("dmSearchInChat"), systemImage: "magnifyingglass") { searchPresented = true }
                .disabled(model.messages.isEmpty)
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
    private var jumpToLatest: some View {
        if awayFromBottom, !model.messages.isEmpty, !model.isSearching {
            Button {
                unseenCount = 0
                withAnimation(.smooth(duration: 0.35)) { position.scrollTo(edge: .bottom) }
            } label: {
                Image(systemName: "arrow.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .overlay(alignment: .topTrailing) {
                if unseenCount > 0 {
                    Text(unseenCount > 99 ? "99+" : "\(unseenCount)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppColors.background)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.textPrimary, in: Capsule())
                        .offset(x: 4, y: -4)
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 10)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
            .accessibilityLabel(L("dmJumpToLatest"))
            .accessibilityValue(unseenCount > 0 ? L("dmNewMessagesCount", ["count": unseenCount]) : "")
            .accessibilityIdentifier("dm-jump-latest")
        }
    }

    private var matchNavigator: some View {
        GlassEffectContainer {
            HStack(spacing: 12) {
                Text(model.matchPositionText)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("dm-search-position")
                Spacer(minLength: 0)
                Button(action: model.previousMatch) {
                    Image(systemName: "chevron.up").frame(width: 24, height: 24)
                }
                .accessibilityLabel(L("dmSearchPrevious"))
                .accessibilityIdentifier("dm-search-previous")
                Button(action: model.nextMatch) {
                    Image(systemName: "chevron.down").frame(width: 24, height: 24)
                }
                .accessibilityLabel(L("dmSearchNext"))
                .accessibilityIdentifier("dm-search-next")
            }
            .buttonStyle(.borderless)
            .font(.body.weight(.semibold))
            .disabled(model.searchMatches.isEmpty)
            .padding(.leading, 20)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(.snappy, value: model.matchPositionText)
        .sensoryFeedback(.selection, trigger: model.currentMatchId)
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
                    if model.isPeerUnavailable {
                        Label(L("dmPeerNotOnMarmot", ["name": profile?.bestName ?? Profile.shortNpub(pubkey)]), systemImage: "exclamationmark.lock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .accessibilityIdentifier("dm-chat-peer-unavailable")
                    } else {
                        Text(L("noMessagesYet"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
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
                            .padding(.horizontal, 12)
                    }
                }
                .frame(maxWidth: .infinity)
                .scrollTargetLayout()
                .padding(.top, 8)
                .padding(.bottom, 6)
                .animation(.smooth(duration: 0.3), value: model.messages.count)
            }
            .scrollPosition($position)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height - (geometry.contentOffset.y + geometry.containerSize.height) > 360
            } action: { _, away in
                withAnimation(.snappy(duration: 0.25)) { awayFromBottom = away }
                if !away { unseenCount = 0 }
            }
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("dm-chat-messages")
        }
    }

    @ViewBuilder
    private func rowView(_ row: DMChatRow) -> some View {
        switch row.kind {
        case .day(let date):
            Text(DMFormat.daySeparator(date))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .glassEffect(.regular, in: .capsule)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
        case .message(let message, let first, let last):
            DMMessageBubble(
                message: message,
                isFirstInGroup: first,
                isLastInGroup: last,
                onCopy: model.copy,
                onCopyImage: model.copyImage,
                onRetry: model.retry,
                onDiscard: model.discard,
                onQuote: model.quote,
                onInfo: model.showInfo,
                searchQuery: model.trimmedSearch,
                isCurrentMatch: model.currentMatchId == message.id
            )
        }
    }
}
