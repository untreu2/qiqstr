import SwiftUI

struct FeedView: View {
    @State private var model = FeedViewModel()
    @State private var bus = DataBus.shared
    @State private var session = Session.shared
    @State private var store = NoteInteractionStore.shared

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
                .safeAreaBar(edge: .top) {
                    if !model.lists.isEmpty {
                        FeedSourceBar(lists: model.lists, selected: model.source) { model.select($0) }
                    }
                }
                .onChange(of: model.scrollToTopToken) { scrollToTop(proxy) }
                .toolbar { toolbar(proxy) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { model.start() }
        .task(id: bus.feedVersion) { await model.reload() }
        .task(id: bus.listsVersion) { await model.loadLists() }
        .task(id: bus.interactionVersion) { if bus.interactionVersion > 0 { store.refreshAll() } }
        .onChange(of: session.mutedPubkeys) { model.refilter() }
        .onChange(of: session.mutedWords) { model.refilter() }
        .onChange(of: store.deletedIds) { model.refilter() }
        .sensoryFeedback(.selection, trigger: model.source)
    }

    private func scrollToTop(_ proxy: ScrollViewProxy) {
        guard let first = model.notes.first?.listId else { return }
        withAnimation(.snappy(duration: 0.35)) { proxy.scrollTo(first, anchor: .top) }
    }

    @ToolbarContentBuilder
    private func toolbar(_ proxy: ScrollViewProxy) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { Router.shared.showSidebar = true } label: {
                if let me = session.pubkey {
                    ProfileAvatar(pubkey: me, size: 32)
                } else {
                    Image(systemName: "person.crop.circle")
                }
            }
            .accessibilityLabel(L("profile"))
            .accessibilityIdentifier("feed-avatar")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .principal) {
            Button { scrollToTop(proxy) } label: {
                Image("Logo")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(height: 22)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("qiqstr")
            .accessibilityIdentifier("feed-logo")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section(L("feedFeeds")) {
                    Picker(L("feedFeeds"), selection: Binding(get: { model.source }, set: { model.select($0) })) {
                        Label(L("all"), systemImage: "person.2").tag(FeedSource.following)
                        ForEach(model.lists) { set in
                            Label(set.title, systemImage: "list.bullet").tag(FeedSource.list(set))
                        }
                    }
                    Button(L("addAnotherFeed"), systemImage: "plus") { Router.shared.push(.followSets) }
                }
                Section(L("sortBy")) {
                    Picker(L("sortBy"), selection: $model.sort) {
                        ForEach(FeedSortMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .accessibilityLabel(L("feedFeedOptions"))
            .accessibilityIdentifier("feed-selector")
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if model.notes.isEmpty {
            if !model.hasLoaded || model.isSyncing {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text(L("loadingYourFeed")).font(.system(size: 15)).foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityIdentifier("feed-loading")
            } else if case .list = model.source {
                EmptyStateView(systemImage: "list.bullet.rectangle", title: L("noNotesYet"), message: nil, actionTitle: L("refresh")) {
                    Task { await model.refresh() }
                }
            } else {
                FeedEmptyState { Task { await model.refresh() } }
            }
        }
    }
}

struct NoteList: View {
    let notes: [Note]
    var isLoadingMore = false
    var showsThreadContext = true
    var onAppearNote: (Note) -> Void = { _ in }

    var body: some View {
        List {
            ForEach(notes, id: \.listId) { note in
                NoteRowView(note: note, showsThreadContext: showsThreadContext)
                    .id(note.listId)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(AppColors.background)
                    .listRowSeparatorTint(AppColors.divider)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
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

struct FeedNewNotesPill: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold))
                Text(count == 1 ? L("feedNewNotesOne") : L("feedNewNotesMany", ["count": count]))
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, 16)
            .frame(height: 38)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .sensoryFeedback(.impact(weight: .light), trigger: count)
        .accessibilityIdentifier("feed-new-notes")
    }
}

struct FeedSourceBar: View {
    let lists: [FeedFollowSet]
    let selected: FeedSource
    let onSelect: (FeedSource) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        chip(.following)
                        ForEach(lists) { chip(.list($0)) }
                        Button { Router.shared.push(.followSets) } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel(L("addAnotherFeed"))
                        .accessibilityIdentifier("feed-add-list")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }
            .onChange(of: selected) { withAnimation { proxy.scrollTo(selected.id, anchor: .center) } }
        }
    }

    private func chip(_ source: FeedSource) -> some View {
        let isSelected = source == selected
        let title = source.title.count > 22 ? "\(source.title.prefix(20))…" : source.title
        return Button { onSelect(source) } label: {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? AppColors.background : AppColors.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background { if isSelected { Capsule().fill(AppColors.textPrimary) } }
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? .identity : .regular.interactive(), in: .capsule)
        .id(source.id)
        .accessibilityIdentifier("feed-source-\(source.id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct FeedEmptyState: View {
    var onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            IconTile(systemImage: "sparkles", size: 72, tint: AppColors.textSecondary)
            Text(L("yourFeedIsEmpty")).font(AppFont.brand(24)).multilineTextAlignment(.center)
            Text(L("followSomeoneToSeePosts"))
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                PrimaryButton(title: L("suggestedFollows")) { Router.shared.push(.suggestedFollows) }
                    .accessibilityIdentifier("feed-empty-suggested")
                SecondaryButton(title: L("feedExplore"), systemImage: "safari") { Router.shared.push(.explore) }
                    .accessibilityIdentifier("feed-empty-explore")
                Button(L("refresh"), action: onRefresh)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.top, 4)
                    .accessibilityIdentifier("feed-empty-refresh")
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: 420)
        .accessibilityIdentifier("feed-empty")
    }
}
