import SwiftUI

@MainActor
@Observable
final class HashtagFeedViewModel {
    let tag: String
    private(set) var notes: [Note] = []
    private(set) var hasLoaded = false
    private(set) var isSyncing = true
    private(set) var isLoadingMore = false
    private(set) var canLoadMore = true
    private(set) var recentCount: Int?
    private(set) var followFeedback = 0
    @ObservationIgnored private var limit = FeedViewModel.pageSize
    @ObservationIgnored private var seen: Set<String> = []
    @ObservationIgnored private var exhausted = false

    init(tag: String) {
        self.tag = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
    }

    var isFollowing: Bool { HashtagFollowService.shared.isFollowing(tag) }
    var isFollowPending: Bool { HashtagFollowService.shared.isPending(tag) }

    func toggleFollow() {
        followFeedback &+= 1
        Task {
            do { try await HashtagFollowService.shared.toggle(tag) } catch { ToastCenter.shared.error(error) }
        }
    }

    func sync(force: Bool = false) async {
        isSyncing = true
        await SyncService.shared.syncHashtag(tag, force: force)
        isSyncing = false
        await reload()
    }

    func loadRecentCount() async {
        recentCount = await HashtagFollowService.shared.recentCount(tag)
    }

    func reload() async {
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        let result = await NoteRepository.hashtag(tag, limit: limit)
        apply(result)
    }

    private func apply(_ result: [Note]) {
        let muted = Set(Session.shared.mutedPubkeys)
        let words = Session.shared.mutedWords.map { $0.lowercased() }.filter { !$0.isEmpty }
        let deleted = NoteInteractionStore.shared.deletedIds
        var ids: Set<String> = []
        notes = result.filter { note in
            guard ids.insert(note.listId).inserted, !deleted.contains(note.id), !muted.contains(note.pubkey) else { return false }
            let content = note.content.lowercased()
            return !words.contains { content.contains($0) }
        }
        hasLoaded = true
        canLoadMore = !exhausted || result.count >= limit
        let fresh = notes.filter { !seen.contains($0.listId) }
        seen.formUnion(fresh.map(\.listId))
        guard !fresh.isEmpty else { return }
        NoteInteractionStore.shared.seed(fresh)
        NoteInteractionStore.shared.requestCounts(fresh.map(\.id))
        NoteRepository.prefetchEmbedded(fresh)
        Task {
            await NoteContentCache.warm(fresh)
            await ProfileCache.shared.load(Array(Set(fresh.map(\.pubkey))).filter { ProfileCache.shared.profile($0) == nil })
        }
    }

    func loadMoreIfNeeded(_ note: Note) {
        guard canLoadMore, !isLoadingMore, let index = notes.firstIndex(where: { $0.listId == note.listId }), index >= notes.count - 6 else { return }
        Task { await loadMore() }
    }

    func loadMore() async {
        guard canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let previous = notes.count
        limit += FeedViewModel.pageSize
        var result = await NoteRepository.hashtag(tag, limit: limit)
        if result.count <= previous || result.count < limit {
            let oldest = (result.isEmpty ? notes : result).map(\.createdAt).filter { $0 > 0 }.min() ?? TimeFormat.now
            if await NoteRepository.fetchOlderHashtag(tag, until: oldest) == 0 { exhausted = true }
            result = await NoteRepository.hashtag(tag, limit: limit)
        }
        apply(result)
        if notes.count <= previous { canLoadMore = !exhausted }
    }
}

struct HashtagFeedView: View {
    let tag: String
    @State private var model: HashtagFeedViewModel
    @State private var bus = DataBus.shared

    init(tag: String) {
        self.tag = tag
        _model = State(initialValue: HashtagFeedViewModel(tag: tag))
    }

    var body: some View {
        ScrollViewReader { proxy in
            NoteList(notes: model.notes, isLoadingMore: model.isLoadingMore, onAppearNote: model.loadMoreIfNeeded) {
                if let count = model.recentCount, count > 0, !model.notes.isEmpty {
                    HashtagFeedHeader(count: count)
                        .listRowBackground(AppColors.background)
                        .listRowSeparator(.hidden)
                }
            }
                .accessibilityIdentifier("hashtag-list")
                .refreshable { await model.sync(force: true) }
                .overlay {
                    if model.notes.isEmpty {
                        if !model.hasLoaded || model.isSyncing {
                            ProgressView().controlSize(.large)
                        } else {
                            EmptyStateView(systemImage: "number", title: L("noNotesYet"), actionTitle: L("refresh")) {
                                Task { await model.sync(force: true) }
                            }
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Button {
                            if let first = model.notes.first?.listId { withAnimation { proxy.scrollTo(first, anchor: .top) } }
                        } label: {
                            Text("#\(model.tag)")
                                .font(.headline)
                                .foregroundStyle(AppColors.background)
                                .padding(.horizontal, 14)
                                .frame(height: 32)
                                .background(AppColors.textPrimary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("hashtag-title")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HashtagFollowButton(isFollowing: model.isFollowing, isPending: model.isFollowPending, action: model.toggleFollow)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.sync() }
        .task(id: bus.feedVersion) {
            await model.reload()
            await model.loadRecentCount()
        }
        .sensoryFeedback(.selection, trigger: model.followFeedback)
    }
}

struct HashtagFeedHeader: View {
    let count: Int

    var body: some View {
        Label(L("feedTopicPostsLastDay", ["count": count]), systemImage: "chart.line.uptrend.xyaxis")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .listRowInsets(EdgeInsets())
            .accessibilityIdentifier("hashtag-recent-count")
    }
}

struct HashtagFollowButton: View {
    let isFollowing: Bool
    let isPending: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isFollowing {
                Button(action: action) { Text(L("following")).font(.subheadline.weight(.semibold)) }
                    .buttonStyle(.glass)
            } else {
                Button(action: action) { Text(L("follow")).font(.subheadline.weight(.semibold)) }
                    .buttonStyle(.glassProminent)
                    .foregroundStyle(AppColors.background)
            }
        }
        .buttonBorderShape(.capsule)
        .disabled(isPending)
        .animation(.snappy, value: isFollowing)
        .accessibilityIdentifier("hashtag-follow")
    }
}
