import Foundation
import Observation

enum NoteThreadRow: Identifiable, Hashable {
    case reply(Note, depth: Int, hasChildren: Bool)
    case moreReplies(parentId: String, hidden: Int, depth: Int)
    case continueThread(noteId: String, count: Int, depth: Int)
    case loadMore(remaining: Int)

    var id: String {
        switch self {
        case .reply(let note, _, _): "r-\(note.id)"
        case .moreReplies(let parent, _, _): "m-\(parent)"
        case .continueThread(let id, _, _): "c-\(id)"
        case .loadMore: "load-more"
        }
    }
}

@MainActor
@Observable
final class ThreadViewModel {
    static let maxDepth = 4
    static let maxNested = 3
    static let pageSize = 20

    let noteId: String
    private(set) var data: NoteThreadData?
    private(set) var placeholder: Note?
    private(set) var isLoading = true
    private(set) var failed = false
    private(set) var repliesSynced = false
    private(set) var quoteCount = 0
    private(set) var rows: [NoteThreadRow] = []
    private var expanded: Set<String> = []
    private var visibleTopLevel = ThreadViewModel.pageSize
    @ObservationIgnored private var stableOrder: [String] = []
    @ObservationIgnored private var liveTask: Task<Void, Never>?
    @ObservationIgnored private var liveIds: Set<String> = []
    @ObservationIgnored private var started = false

    init(noteId: String) {
        self.noteId = noteId
    }

    var focused: Note? { data?.focused ?? placeholder }
    var ancestors: [Note] { data.map { Array($0.chain.dropLast()) } ?? [] }

    func start() async {
        guard !started else { return }
        started = true
        if placeholder == nil { placeholder = await NoteRepository.note(noteId) }
        if let placeholder { NoteInteractionStore.shared.seed([placeholder]) }
        if let local = await NoteRepository.threadLocal(noteId) { apply(local) }
        await loadNetwork()
    }

    func loadNetwork() async {
        failed = false
        do {
            if let remote = try await NoteRepository.threadNetwork(noteId) {
                apply(remote)
                if let local = await NoteRepository.threadLocal(noteId) { apply(local) }
            } else if data == nil {
                failed = placeholder == nil
            }
        } catch {
            if data == nil, placeholder == nil { failed = true }
        }
        repliesSynced = true
        isLoading = false
        await afterNetwork()
    }

    func refresh() async {
        await loadNetwork()
    }

    func reloadLocal() async {
        guard started, repliesSynced else { return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled, let local = await NoteRepository.threadLocal(noteId) else { return }
        apply(local)
    }

    private func apply(_ thread: NoteThreadData) {
        data = thread
        isLoading = false
        rebuild()
        let notes = thread.allNotes
        NoteInteractionStore.shared.seed(notes)
        Task {
            await NoteContentCache.warm(notes)
            await ProfileCache.shared.load(Array(Set(notes.map(\.pubkey))).filter { ProfileCache.shared.profile($0) == nil })
        }
    }

    private func afterNetwork() async {
        guard let focused else { return }
        quoteCount = await NoteRepository.quoteCount(focused.id)
        let ids = [focused.id] + rows.compactMap { row -> String? in
            if case .reply(let note, _, _) = row { return note.id }
            return nil
        }
        startLiveCounts(Array(ids.prefix(120)))
        Task {
            await SyncService.shared.syncInteractions(for: [focused.id])
            NoteInteractionStore.shared.requestCounts([focused.id], relays: false)
        }
        Task {
            await NoteRepository.fetchQuotesFromRelays(focused.id)
            quoteCount = await NoteRepository.quoteCount(focused.id)
        }
    }

    private func startLiveCounts(_ ids: [String]) {
        let wanted = Set(ids)
        guard !wanted.isSubset(of: liveIds) else { return }
        liveIds = wanted
        liveTask?.cancel()
        liveTask = Task {
            do {
                for try await map in InteractionService.shared.liveCounts(ids) {
                    NoteInteractionStore.shared.applyLive(map)
                }
            } catch {}
        }
    }

    func stop() {
        liveTask?.cancel()
        liveTask = nil
        liveIds = []
    }

    func expand(_ parentId: String) {
        expanded.insert(parentId)
        rebuild()
    }

    func showMoreTopLevel() {
        visibleTopLevel += Self.pageSize
        rebuild()
    }

    private func sortedChildren(_ id: String, stable: Bool) -> [Note] {
        guard let children = data?.children[id] else { return [] }
        let me = Session.shared.pubkey
        let deleted = NoteInteractionStore.shared.deletedIds
        let muted = Set(Session.shared.mutedPubkeys)
        let visible = children.filter { !deleted.contains($0.id) && !muted.contains($0.pubkey) }
        let sorted = visible.sorted { a, b in
            let aMine = a.pubkey == me, bMine = b.pubkey == me
            if aMine != bMine { return aMine }
            return a.createdAt < b.createdAt
        }
        guard stable else { return sorted }
        let byId = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        stableOrder.removeAll { byId[$0] == nil }
        let newOnes = sorted.filter { !stableOrder.contains($0.id) }
        stableOrder.append(contentsOf: (stableOrder.isEmpty ? newOnes : newOnes.sorted { $0.createdAt < $1.createdAt }).map(\.id))
        return stableOrder.compactMap { byId[$0] }
    }

    func rebuild() {
        guard let focused = data?.focused else { rows = []; return }
        var result: [NoteThreadRow] = []
        let top = sortedChildren(focused.id, stable: true)
        for note in top.prefix(visibleTopLevel) { flatten(note, depth: 0, into: &result) }
        if top.count > visibleTopLevel { result.append(.loadMore(remaining: top.count - visibleTopLevel)) }
        rows = result
    }

    private func flatten(_ note: Note, depth: Int, into result: inout [NoteThreadRow]) {
        let kids = sortedChildren(note.id, stable: false)
        result.append(.reply(note, depth: depth, hasChildren: !kids.isEmpty && depth < Self.maxDepth))
        guard !kids.isEmpty else { return }
        if depth < Self.maxDepth {
            let shown = expanded.contains(note.id) ? kids : Array(kids.prefix(Self.maxNested))
            for kid in shown { flatten(kid, depth: depth + 1, into: &result) }
            if kids.count > shown.count { result.append(.moreReplies(parentId: note.id, hidden: kids.count - shown.count, depth: depth + 1)) }
        } else {
            result.append(.continueThread(noteId: note.id, count: kids.count, depth: depth + 1))
        }
    }
}
