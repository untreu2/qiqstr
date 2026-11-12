import SwiftUI

struct FeedView: View {
    @State private var model = FeedViewModel()
    @State private var bus = DataBus.shared
    @State private var session = Session.shared
    @State private var store = NoteInteractionStore.shared
    @State private var hashtags = HashtagFollowService.shared
    @State private var isManagingTopics = false
    @State private var explore = ExploreService.shared

    var body: some View {
        ScrollViewReader { proxy in
            NoteList(notes: model.notes, isLoadingMore: model.isLoadingMore, onAppearNote: model.loadMoreIfNeeded)
                .accessibilityIdentifier("feed-list")
                .refreshable { await model.refresh() }
                .overlay { stateOverlay }
                .overlay(alignment: .top) {
                    if model.pendingCount > 0 {
                        FeedNewNotesPill(count: model.pendingCount) { model.acceptPending() }
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.35), value: model.pendingCount > 0)
                .onChange(of: model.scrollToTopToken) { scrollToTop(proxy) }
        }
        .navigationTitle(model.source.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .task { model.start() }
        .task(id: bus.feedVersion) { await model.reload() }
        .task(id: bus.listsVersion) { await model.loadLists() }
        .task(id: bus.interactionVersion) { if bus.interactionVersion > 0 { store.refreshAll() } }
        .onChange(of: session.mutedPubkeys) { model.refilter() }
        .onChange(of: session.mutedWords) { model.refilter() }
        .onChange(of: store.deletedIds) { model.refilter() }
        .onChange(of: model.notes.isEmpty) { _, empty in if empty { Router.shared.expandTabBar() } }
        .onChange(of: hashtags.tags) { model.topicsChanged() }
        .onChange(of: explore.pinned) { model.pinnedFeedsChanged(explore.pinned) }
        .sheet(isPresented: $isManagingTopics) {
            TopicsManagerView { model.select(.topic($0)) }
        }
        .sensoryFeedback(.selection, trigger: model.source)
        .sensoryFeedback(.selection, trigger: model.sort)
    }

    private func scrollToTop(_ proxy: ScrollViewProxy) {
        guard let first = model.notes.first?.listId else { return }
        withAnimation(.snappy(duration: 0.35)) { proxy.scrollTo(first, anchor: .top) }
    }

    private func sourceToggle(_ source: FeedSource, title: String, systemImage: String) -> some View {
        Toggle(isOn: Binding(get: { model.source == source }, set: { if $0 { model.select(source) } })) {
            Label(title, systemImage: systemImage)
        }
    }

    @ViewBuilder
    private var feedMenu: some View {
        Picker(L("feedFeeds"), selection: Binding(get: { model.source }, set: { model.select($0) })) {
            Label(L("feedExplore"), systemImage: "safari").tag(FeedSource.explore)
            Label(L("all"), systemImage: "person.2").tag(FeedSource.following)
            ForEach(model.lists) { set in
                Label(set.title, systemImage: "list.bullet").tag(FeedSource.list(set))
            }
        }
        .accessibilityIdentifier("feed-selector")
        Button(L("feedAddFeed"), systemImage: "plus") { Router.shared.push(.followSets) }
            .accessibilityIdentifier("feed-add-list")
        Section(L("exploreFeeds")) {
            ForEach(explore.pinnedFeeds) { feed in
                sourceToggle(.discover(feed), title: feed.name, systemImage: "sparkles.rectangle.stack")
            }
            Button(L("exploreDiscoverFeeds"), systemImage: "square.grid.2x2") { Router.shared.push(.discoverFeeds) }
                .accessibilityIdentifier("feed-discover-feeds")
        }
        Section(L("feedTopics")) {
            if !hashtags.tags.isEmpty {
                if hashtags.tags.count > 1 {
                    sourceToggle(.topics, title: L("feedAllTopics"), systemImage: "square.stack")
                }
                ForEach(hashtags.tags, id: \.self) { tag in
                    sourceToggle(.topic(tag), title: "#\(tag)", systemImage: "number")
                }
                Toggle(L("feedFollowingPlusTopics"), systemImage: "rectangle.stack.badge.plus", isOn: $model.includeTopics)
                    .accessibilityIdentifier("feed-include-topics")
            }
            Button(L("feedManageTopics"), systemImage: "number") { isManagingTopics = true }
                .accessibilityIdentifier("feed-manage-topics")
        }
        if !model.source.isTopicFeed && !model.source.isCurated {
            Section(L("sortBy")) {
                Picker(L("sortBy"), selection: $model.sort) {
                    ForEach(FeedSortMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { Router.shared.showSidebar = true } label: {
                Group {
                    if let me = session.pubkey {
                        ProfileAvatar(pubkey: me, size: 30)
                    } else {
                        Image(systemName: "person.crop.circle")
                    }
                }
                .frame(width: 30, height: 30)
            }
            .accessibilityLabel(L("profile"))
            .accessibilityIdentifier("feed-avatar")
        }
        ToolbarItem(placement: .principal) {
            Menu { feedMenu } label: {
                HStack(spacing: 6) {
                    Text(model.source.title)
                        .font(.headline)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: 220)
                .contentShape(Capsule())
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            .accessibilityIdentifier("feed-title")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarTrailing) {
            Button(L("newPost"), systemImage: "square.and.pencil") { Router.shared.compose() }
                .accessibilityIdentifier("feed-compose")
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if model.notes.isEmpty {
            if !model.hasLoaded || model.isSyncing {
                FeedSkeleton()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L("loadingYourFeed"))
                    .accessibilityIdentifier("feed-loading")
            } else if case .list = model.source {
                EmptyStateView(systemImage: "list.bullet.rectangle", title: L("noNotesYet"), message: nil, actionTitle: L("refresh")) {
                    Task { await model.refresh() }
                }
            } else if model.source.isTopicFeed || model.source.isCurated {
                EmptyStateView(systemImage: "number", title: L("noNotesYet"), message: nil, actionTitle: L("refresh")) {
                    Task { await model.refresh() }
                }
            } else {
                FeedEmptyState(onExplore: { model.select(.explore) }) { Task { await model.refresh() } }
            }
        }
    }
}

struct NoteList<Header: View>: View {
    let notes: [Note]
    var isLoadingMore = false
    var showsThreadContext = true
    var onAppearNote: (Note) -> Void = { _ in }
    @ViewBuilder var header: Header

    var body: some View {
        List {
            header
            ForEach(notes, id: \.listId) { note in
                NoteRowView(note: note, showsThreadContext: showsThreadContext)
                    .id(note.listId)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(AppColors.background)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    .listRowSeparator(note.listId == notes.first?.listId ? .hidden : .visible, edges: .top)
                    .noteSwipeActions(note)
                    .onAppear { onAppearNote(note) }
            }
            if isLoadingMore {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, 18)
                    .listRowSeparator(.hidden)
                    .listRowBackground(AppColors.background)
                    .accessibilityIdentifier("feed-loading-more")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
    }
}

extension NoteList where Header == EmptyView {
    init(notes: [Note], isLoadingMore: Bool = false, showsThreadContext: Bool = true, onAppearNote: @escaping (Note) -> Void = { _ in }) {
        self.init(notes: notes, isLoadingMore: isLoadingMore, showsThreadContext: showsThreadContext, onAppearNote: onAppearNote) { EmptyView() }
    }
}

struct FeedNewNotesPill: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(count == 1 ? L("feedNewNotesOne") : L("feedNewNotesMany", ["count": count]), systemImage: "arrow.up")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 4)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .sensoryFeedback(.impact(weight: .light), trigger: count)
        .accessibilityIdentifier("feed-new-notes")
    }
}

struct FeedSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { index in
                    FeedSkeletonRow(lines: index % 2 == 0 ? 3 : 2)
                    Divider()
                }
            }
        }
        .scrollDisabled(true)
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .background(AppColors.background)
    }
}

struct FeedSkeletonRow: View {
    let lines: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(.quaternary).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "Placeholder name · 1h").font(.subheadline.weight(.semibold))
                ForEach(0..<lines, id: \.self) { _ in
                    Text(verbatim: "Placeholder note text line that fills the row")
                        .font(.body)
                }
                Text(verbatim: "0  0  0  0").font(.footnote)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct FeedEmptyState: View {
    var onExplore: () -> Void
    var onRefresh: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(L("yourFeedIsEmpty"), systemImage: "sparkles")
        } description: {
            Text(L("followSomeoneToSeePosts"))
        } actions: {
            Button(L("suggestedFollows")) { Router.shared.push(.suggestedFollows) }
                .buttonStyle(.glassProminent)
                .foregroundStyle(AppColors.background)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .accessibilityIdentifier("feed-empty-suggested")
            Button(L("feedExplore"), systemImage: "safari", action: onExplore)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("feed-empty-explore")
            Button(L("refresh"), action: onRefresh)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("feed-empty-refresh")
        }
        .accessibilityIdentifier("feed-empty")
    }
}
