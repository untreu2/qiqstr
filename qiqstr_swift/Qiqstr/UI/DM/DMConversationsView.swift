import SwiftUI

struct DMConversationsView: View {
    @State private var model = DMConversationsViewModel()
    @State private var bus = DataBus.shared
    @State private var router = Router.shared

    var body: some View {
        content
            .background(AppColors.background)
            .navigationTitle(L("messages"))
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $model.query, prompt: L("search"))
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
                    ForEach(model.visibleConversations) { conversation in
                        row(conversation)
                    }
                } footer: {
                    if !model.isSearching, !model.visibleConversations.isEmpty { notice }
                }
                .listSectionSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await model.refresh() }
            .overlay {
                if model.visibleConversations.isEmpty, model.isSearching {
                    ContentUnavailableView.search(text: model.query)
                } else if model.visibleConversations.isEmpty, model.filter == .requests {
                    EmptyStateView(
                        systemImage: "tray",
                        title: L("dmRequestsEmptyTitle"),
                        message: L("dmRequestsEmptyMessage")
                    )
                    .padding(.top, 120)
                    .accessibilityIdentifier("dm-requests-empty")
                } else if model.visibleConversations.isEmpty {
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
            .safeAreaBar(edge: .top) {
                if !model.isSearching { filterPicker }
            }
        }
    }

    private var filterPicker: some View {
        Picker(L("messages"), selection: $model.filter) {
            ForEach(DMConversationFilter.allCases) { filter in
                Text(model.title(for: filter)).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .sensoryFeedback(.selection, trigger: model.filter)
        .accessibilityIdentifier("dm-filter")
    }

    private var notice: some View {
        Label {
            Text(L("dmEncryptionNotice"))
        } icon: {
            Image(systemName: "lock.fill")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .labelStyle(DMNoticeLabelStyle())
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, 12)
    }

    private func row(_ conversation: DMConversation) -> some View {
        NavigationLink(value: Route.dmChat(conversation.peer)) {
            DMConversationRow(conversation: conversation)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 78 }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if conversation.isUnread || model.canMarkUnread(conversation) {
                Button {
                    model.toggleRead(conversation)
                } label: {
                    Label(conversation.isUnread ? L("dmMarkRead") : L("dmMarkUnread"), systemImage: conversation.isUnread ? "envelope.open" : "envelope.badge")
                }
                .tint(conversation.isUnread ? Color.primary : AppColors.accent)
            }
        }
        .swipeActions(edge: .trailing) {
            Button {
                router.push(.profile(conversation.peer))
            } label: {
                Label(L("dmViewProfile"), systemImage: "person.crop.circle")
            }
            .tint(.gray)
            Button {
                model.copyNpub(conversation.peer)
            } label: {
                Label(L("dmCopyNpub"), systemImage: "doc.on.doc")
            }
            .tint(.indigo)
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
            configuration.icon.font(.caption2)
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
        HStack(alignment: .top, spacing: 10) {
            Group {
                if conversation.isUnread {
                    Circle()
                        .fill(AppColors.accent)
                        .accessibilityIdentifier("dm-unread-dot")
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Color.clear
                }
            }
            .frame(width: 10, height: 10)
            .padding(.top, 20)
            ProfileAvatar(pubkey: conversation.peer, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(DMFormat.listTime(conversation.timestamp))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                preview
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .animation(.snappy, value: conversation.isUnread)
        .accessibilityElement(children: .combine)
        .accessibilityValue(conversation.isUnread ? L("dmUnread") : "")
    }

    private var preview: Text {
        let message = conversation.lastMessage
        let (icon, text) = DMFormat.preview(message)
        let prefix = message.isMine ? Text(L("dmYouPrefix")).fontWeight(.semibold) : Text(verbatim: "")
        let symbol = icon.map { Text("\(Image(systemName: $0)) ") } ?? Text(verbatim: "")
        return Text("\(prefix)\(symbol)\(text)")
    }
}
