import SwiftUI

struct NotificationsView: View {
    @State private var model = NotificationsViewModel()
    @State private var bus = DataBus.shared
    @State private var session = Session.shared
    @State private var router = Router.shared
    @AppStorage(WebOfTrustService.filterNotificationsKey) private var onlyTrusted = true

    private struct ReloadKey: Equatable {
        var version: Int
        var muted: [String]
        var words: [String]
    }

    var body: some View {
        let visible = model.visible
        content(visible.groups, hidden: visible.hidden)
            .navigationTitle(L("notifications"))
            .navigationSubtitle(model.filter == .all ? "" : model.filter.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbarTitleMenu { NotificationFilterPicker(selection: $model.filter) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NotificationFilterPicker(selection: $model.filter)
                        Divider()
                        Toggle(isOn: $onlyTrusted) {
                            Label(L("notificationsOnlyKnown"), systemImage: "person.2")
                        }
                        .accessibilityIdentifier("notifications-only-known")
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
            .onChange(of: router.selectedTab, initial: true) { _, tab in
                guard tab == .notifications else { return }
                model.markSeen()
                NotificationBadge.shared.markRead()
            }
            .onChange(of: onlyTrusted, initial: true) { _, value in model.onlyTrusted = value }
            .sensoryFeedback(.selection, trigger: model.filter)
            .sensoryFeedback(.selection, trigger: onlyTrusted)
    }

    @ViewBuilder
    private func content(_ groups: [NotificationGroup], hidden: Int) -> some View {
        if !model.isLoaded {
            LoadingView()
        } else if let error = model.errorMessage, model.all.isEmpty {
            EmptyStateView(systemImage: "exclamationmark.triangle", title: L("failedToLoadNotifications"), message: error, actionTitle: L("retryText")) {
                Task { await model.reload() }
            }
        } else {
            List {
                if groups.isEmpty && hidden == 0 {
                    EmptyStateView(
                        systemImage: model.filter == .all ? "bell" : model.filter.symbol,
                        title: model.filter == .all ? L("noNotificationsYet") : L("notificationsFilterEmpty", ["filter": AppLanguage.locale.language.languageCode == .german ? model.filter.title : model.filter.title.lowercased(with: AppLanguage.locale)]),
                        message: L("whenSomeoneInteractsWithYourPosts")
                    )
                        .listRowSeparator(.hidden)
                        .padding(.top, 40)
                } else {
                    Section {
                        ForEach(groups) { group in
                            row(group)
                        }
                        if hidden > 0 { hiddenRow(hidden) }
                        footer
                            .listRowSeparator(.hidden)
                    }
                    .listSectionSeparator(.hidden)
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

    private func hiddenRow(_ count: Int) -> some View {
        Button {
            withAnimation(.snappy) { model.revealHidden() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "eye.slash")
                    .font(.body)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("notificationsHiddenCount", ["count": count]))
                        .font(.subheadline.weight(.semibold))
                    Text(L("notificationsHiddenFooter"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(L("showKey"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(AppColors.background)
        .accessibilityIdentifier("notifications-hidden-row")
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
