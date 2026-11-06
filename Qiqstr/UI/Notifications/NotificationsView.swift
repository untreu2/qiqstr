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
            .toolbarTitleDisplayMode(.inlineLarge)
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
                Section {
                    header
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
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
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
            NotificationFilterChips(selection: $model.filter)
            if summary.total > 0 {
                summaryText(summary)
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.textSecondary)
                NotificationActivityBar(summary: summary)
            }
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
            run.font = .system(size: 15, weight: .semibold)
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
                Text("·").font(.system(size: 18)).foregroundStyle(AppColors.textSecondary.opacity(0.5))
            } else {
                Button(L("notificationLoadOlder")) { Task { await model.loadMore() } }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .buttonStyle(.plain)
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

struct NotificationFilterChips: View {
    @Binding var selection: NotificationFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NotificationFilter.allCases) { filter in
                    let selected = filter == selection
                    Button {
                        withAnimation(.snappy) { selection = filter }
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .foregroundStyle(selected ? AppColors.background : AppColors.textPrimary)
                            .background(selected ? AppColors.textPrimary : AppColors.overlayLight, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("notifications-filter-\(filter.rawValue)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .scrollClipDisabled()
    }
}
