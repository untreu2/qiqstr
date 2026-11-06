import SwiftUI

struct DMConversationsView: View {
    @State private var model = DMConversationsViewModel()
    @State private var bus = DataBus.shared
    @State private var router = Router.shared

    var body: some View {
        content
            .background(AppColors.background)
            .navigationTitle(L("messages"))
            .toolbar { toolbar }
            .sheet(isPresented: $model.showNewMessage) {
                DMNewMessageSheet { pubkey in
                    model.showNewMessage = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        router.push(.dmChat(pubkey))
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .task { await model.appeared() }
            .task { await model.poll() }
            .task(id: bus.feedVersion) { await model.reloadFollowing() }
            .onChange(of: model.hasLoaded) { model.autoSelectFilter() }
            .onDisappear { model.disappeared() }
    }

    @ViewBuilder
    private var content: some View {
        if model.isInitialLoading {
            LoadingView().accessibilityIdentifier("dm-loading")
        } else {
            List {
                Section {
                    header
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 12, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(model.visibleConversations) { conversation in
                        row(conversation)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await model.refresh() }
            .overlay {
                if model.visibleConversations.isEmpty {
                    EmptyStateView(
                        systemImage: "bubble.left.and.bubble.right",
                        title: L("noConversationsYet"),
                        message: L("startConversationBy"),
                        actionTitle: L("newMessage")
                    ) { model.showNewMessage = true }
                    .padding(.top, 120)
                    .accessibilityIdentifier("dm-empty")
                }
            }
            .animation(.smooth(duration: 0.25), value: model.visibleConversations.map(\.id))
            .accessibilityIdentifier("dm-conversations-list")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(L("dmEncryptionNotice"))
            } icon: {
                Image(systemName: "lock.fill")
            }
            .font(.system(size: 13))
            .foregroundStyle(AppColors.textSecondary)
            .labelStyle(DMNoticeLabelStyle())
            Picker(L("messages"), selection: $model.filter) {
                ForEach(DMConversationFilter.allCases) { filter in
                    Text(model.title(for: filter)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .accessibilityIdentifier("dm-filter")
        }
    }

    private func row(_ conversation: DMConversation) -> some View {
        NavigationLink(value: Route.dmChat(conversation.peer)) {
            DMConversationRow(conversation: conversation)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 76 }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if conversation.isUnread || model.canMarkUnread(conversation) {
                Button {
                    model.toggleRead(conversation)
                } label: {
                    Label(conversation.isUnread ? L("dmMarkRead") : L("dmMarkUnread"), systemImage: conversation.isUnread ? "envelope.open" : "envelope.badge")
                }
                .tint(conversation.isUnread ? AppColors.textPrimary : AppColors.accent)
            }
        }
        .contextMenu {
            Button {
                router.push(.dmChat(conversation.peer))
            } label: {
                Label(L("message"), systemImage: "bubble.left")
            }
            Button {
                router.push(.profile(conversation.peer))
            } label: {
                Label(L("dmViewProfile"), systemImage: "person.crop.circle")
            }
            if conversation.isUnread || model.canMarkUnread(conversation) {
                Button {
                    model.toggleRead(conversation)
                } label: {
                    Label(conversation.isUnread ? L("dmMarkRead") : L("dmMarkUnread"), systemImage: conversation.isUnread ? "envelope.open" : "envelope.badge")
                }
            }
            Button {
                model.copyNpub(conversation.peer)
            } label: {
                Label(L("dmCopyNpub"), systemImage: "doc.on.doc")
            }
        }
        .accessibilityIdentifier("dm-conversation-\(conversation.peer)")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.hasUnread {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        model.markAllRead()
                    } label: {
                        Label(L("dmMarkAllRead"), systemImage: "checkmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityIdentifier("dm-more")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                model.showNewMessage = true
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .accessibilityLabel(L("newMessage"))
            .accessibilityIdentifier("dm-new-message")
        }
    }
}

private struct DMNoticeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.font(.system(size: 11))
            configuration.title
        }
    }
}

struct DMConversationRow: View {
    let conversation: DMConversation
    @State private var cache = ProfileCache.shared

    private var profile: Profile? { cache.profile(conversation.peer) }
    private var name: String { profile?.bestName ?? Profile.shortNpub(conversation.peer) }

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatar(pubkey: conversation.peer, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name)
                        .font(.system(size: 16, weight: conversation.isUnread ? .bold : .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(DMFormat.listTime(conversation.timestamp))
                        .font(.system(size: 13, weight: conversation.isUnread ? .semibold : .regular))
                        .foregroundStyle(conversation.isUnread ? AppColors.textPrimary : AppColors.textSecondary)
                        .monospacedDigit()
                }
                HStack(alignment: .center, spacing: 8) {
                    preview
                        .font(.system(size: 14, weight: conversation.isUnread ? .medium : .regular))
                        .foregroundStyle(conversation.isUnread ? AppColors.textPrimary : AppColors.textSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if conversation.isUnread {
                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 10, height: 10)
                            .accessibilityIdentifier("dm-unread-dot")
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .animation(.snappy, value: conversation.isUnread)
        .accessibilityElement(children: .combine)
    }

    private var preview: Text {
        let message = conversation.lastMessage
        let (icon, text) = DMFormat.preview(message)
        let prefix = message.isMine ? Text(L("dmYouPrefix")).fontWeight(.semibold) : Text(verbatim: "")
        let symbol = icon.map { Text("\(Image(systemName: $0)) ") } ?? Text(verbatim: "")
        return Text("\(prefix)\(symbol)\(text)")
    }
}
