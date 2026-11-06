import SwiftUI

struct NotificationsView: View {
    @State private var model = NotificationsViewModel()
    @State private var bus = DataBus.shared
    @State private var session = Session.shared
    @State private var router = Router.shared

    private struct ReloadKey: Equatable {
        var version: Int
        var muted: [String]
        var words: [String]
    }

    var body: some View {
        let groups = model.groups
        content(groups)
            .navigationTitle(L("notifications"))
            .navigationSubtitle(model.filter == .all ? "" : model.filter.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbarTitleMenu { NotificationFilterPicker(selection: $model.filter) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NotificationFilterPicker(selection: $model.filter)
                    } label: {
                        Label(L("notificationFilterAll"), systemImage: model.filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel(model.filter.title)
                    .accessibilityIdentifier("notifications-filter-menu")
                }
            }
            .task(id: ReloadKey(version: bus.notificationVersion, muted: session.mutedPubkeys, words: session.mutedWords)) {
                if model.isLoaded { try? await Task.sleep(for: .milliseconds(300)) }
                guard !Task.isCancelled else { return }
                await model.reload()
            }
            .onAppear {
                model.markSeen()
                NotificationBadge.shared.markRead()
            }
            .sensoryFeedback(.selection, trigger: model.filter)
    }

    @ViewBuilder
    private func content(_ groups: [NotificationGroup]) -> some View {
        if !model.isLoaded {
            LoadingView()
        } else if let error = model.errorMessage, model.all.isEmpty {
            EmptyStateView(systemImage: "exclamationmark.triangle", title: L("failedToLoadNotifications"), message: error, actionTitle: L("retryText")) {
                Task { await model.reload() }
            }
        } else {
            List {
                if model.summary.total > 0 {
                    Section {
                        header
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                if groups.isEmpty {
                    EmptyStateView(systemImage: "bell", title: L("noNotificationsYet"), message: L("whenSomeoneInteractsWithYourPosts"))
                        .listRowSeparator(.hidden)
                        .padding(.top, 40)
                } else {
                    Section {
                        ForEach(groups) { group in
                            row(group)
                        }
                        footer
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .refreshable { await model.refresh() }
            .accessibilityIdentifier("notifications-list")
        }
    }

    private func row(_ group: NotificationGroup) -> some View {
        Button { open(group) } label: {
            NotificationRowView(group: group, isUnread: model.isUnread(group))
        }
        .buttonStyle(.plain)
        .listRowBackground(AppColors.background)
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        .accessibilityIdentifier("notification-row-\(group.id)")
        .contextMenu {
            if let noteId = group.focusedNoteId {
                Button { router.push(.thread(noteId)) } label: { Label(L("notificationOpenNote"), systemImage: "text.bubble") }
            }
            ForEach(group.authors.prefix(5), id: \.self) { pubkey in
                Button { router.push(.profile(pubkey)) } label: {
                    Label(ProfileCache.shared.profile(pubkey)?.bestName ?? Profile.shortNpub(pubkey), systemImage: "person.crop.circle")
                }
            }
            if !group.isGrouped, let pubkey = group.authors.first {
                Divider()
                Button(role: .destructive) { Task { await model.mute(pubkey) } } label: {
                    Label(L("mute"), systemImage: "speaker.slash")
                }
            }
        }
        .task { await model.loadMoreIfNeeded(group) }
    }

    @ViewBuilder
    private var header: some View {
        let summary = model.summary
        VStack(alignment: .leading, spacing: 10) {
            summaryText(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            NotificationActivityBar(summary: summary)
        }
    }

    private func summaryText(_ s: NotificationSummary) -> Text {
        var parts: [String] = []
        if s.reactions > 0 { parts.append(SettingsICU.format("notificationReactionCount", ["count": s.reactions])) }
        if s.zaps > 0 {
            let zaps = SettingsICU.format("notificationZapCount", ["count": s.zaps])
            parts.append(s.totalSats > 0 ? "\(zaps) (\(SettingsICU.format("notificationZapSatsCount", ["count": s.totalSats])))" : zaps)
        }
        if s.reposts > 0 { parts.append(SettingsICU.format("notificationRepostCount", ["count": s.reposts])) }
        if s.replies > 0 { parts.append(SettingsICU.format("notificationReplyCount", ["count": s.replies])) }
        if s.mentions > 0 { parts.append(SettingsICU.format("notificationMentionCount", ["count": s.mentions])) }
        if s.quotes > 0 { parts.append(SettingsICU.format("notificationQuoteCount", ["count": s.quotes])) }
        var text = AttributedString(L("notificationSummaryPrefix"))
        for (i, part) in parts.enumerated() {
            if i > 0 { text.append(AttributedString(i == parts.count - 1 ? L("notificationSummaryAnd") : ", ")) }
            var run = AttributedString(part)
            run.font = .subheadline.weight(.semibold)
            run.foregroundColor = AppColors.textPrimary
            text.append(run)
        }
        return Text(text)
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            if model.isLoadingMore {
                ProgressView()
            } else if model.hasReachedEnd {
                Image(systemName: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            } else {
                Button(L("notificationLoadOlder")) { Task { await model.loadMore() } }
                    .font(.subheadline)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .accessibilityIdentifier("notifications-load-more")
            }
            Spacer()
        }
        .padding(.vertical, 16)
        .listRowBackground(AppColors.background)
    }

    private func open(_ group: NotificationGroup) {
        if group.isGrouped {
            if let target = group.targetNoteId { router.push(.thread(target)) }
            return
        }
        if let id = group.focusedNoteId {
            router.push(.thread(id))
        } else if let pubkey = group.authors.first {
            router.push(.profile(pubkey))
        }
    }
}

struct NotificationActivityBar: View {
    let summary: NotificationSummary

    private var segments: [(Int, Color)] {
        [
            (summary.reactions, AppColors.reaction),
            (summary.zaps, AppColors.zap),
            (summary.reposts, AppColors.repost),
            (summary.replies, AppColors.reply),
            (summary.mentions, AppColors.textSecondary.opacity(0.5)),
            (summary.quotes, AppColors.textSecondary.opacity(0.3)),
        ].filter { $0.0 > 0 }
    }

    var body: some View {
        GeometryReader { proxy in
            let items = segments
            let total = max(1, items.reduce(0) { $0 + $1.0 })
            let spacing: CGFloat = 2
            let available = proxy.size.width - spacing * CGFloat(max(0, items.count - 1))
            HStack(spacing: spacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Capsule().fill(item.1).frame(width: max(3, available * CGFloat(item.0) / CGFloat(total)))
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

struct NotificationFilterPicker: View {
    @Binding var selection: NotificationFilter

    var body: some View {
        Picker(L("notifications"), selection: Binding(get: { selection }, set: { value in withAnimation(.snappy) { selection = value } })) {
            ForEach(NotificationFilter.allCases) { filter in
                Label(filter.title, systemImage: filter.symbol)
                    .tag(filter)
                    .accessibilityIdentifier("notifications-filter-\(filter.rawValue)")
            }
        }
    }
}

extension NotificationFilter {
    var symbol: String {
        switch self {
        case .all: "tray.full"
        case .replies: "bubble.left"
        case .reactions: "heart"
        case .reposts: "arrow.2.squarepath"
        case .zaps: "bolt"
        }
    }
}
