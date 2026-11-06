import SwiftUI

@MainActor
@Observable
final class BookmarksViewModel {
    private(set) var notes: [Note] = []
    private(set) var isLoading = true
    private(set) var removing: Set<String> = []
    private(set) var removedCount = 0
    private let service = BookmarkService.shared

    func load() async {
        if !service.isLoaded { await service.load() }
        await reload()
    }

    func refresh() async {
        await service.refresh()
        await reload()
    }

    func reload() async {
        let ids = Set(service.bookmarkedIds)
        notes.removeAll { !ids.contains($0.id) }
        let loaded = await service.notes()
        notes = loaded
        isLoading = false
    }

    func remove(_ note: Note) async {
        removing.insert(note.id)
        defer { removing.remove(note.id) }
        let snapshot = notes
        notes.removeAll { $0.id == note.id }
        do {
            try await service.remove(note.id)
            removedCount += 1
            ToastCenter.shared.show(L("bookmarkRemoved"), style: .success)
        } catch {
            notes = snapshot
            ToastCenter.shared.error(error)
        }
    }
}

struct BookmarksView: View {
    @State private var model = BookmarksViewModel()
    @State private var service = BookmarkService.shared

    var body: some View {
        List {
            Section {
                Text(L("bookmarksSubtitle"))
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(model.notes) { note in
                NoteRowView(note: note)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .opacity(model.removing.contains(note.id) ? 0.4 : 1)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await model.remove(note) }
                        } label: {
                            Label(L("removeBookmark"), systemImage: "bookmark.slash")
                        }
                        .accessibilityIdentifier("bookmark-remove-\(note.id)")
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await model.remove(note) }
                        } label: {
                            Label(L("removeBookmark"), systemImage: "bookmark.slash")
                        }
                    }
                    .accessibilityIdentifier("bookmark-row-\(note.id)")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .accessibilityIdentifier("bookmarks-list")
        .overlay { overlay }
        .animation(.snappy, value: model.notes.map(\.id))
        .navigationTitle(L("bookmarksTitle"))
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await model.refresh() }
        .sensoryFeedback(.success, trigger: model.removedCount)
        .task { await model.load() }
        .onChange(of: service.bookmarkedIds) {
            Task { await model.reload() }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if model.notes.isEmpty {
            if model.isLoading || service.isSyncing {
                LoadingView()
            } else {
                EmptyStateView(systemImage: "bookmark", title: L("noBookmarks"), message: L("youHaventBookmarkedAnyNotesYet"))
            }
        }
    }
}
