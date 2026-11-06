import Foundation
import Observation

@MainActor
@Observable
final class NoteCountsModel {
    let noteId: String
    var counts: InteractionCounts
    var isReacting = false
    var isReposting = false
    @ObservationIgnored var lastUserAction: Date?

    init(noteId: String, counts: InteractionCounts) {
        self.noteId = noteId
        self.counts = counts
    }

    var userActionActive: Bool {
        guard let lastUserAction else { return false }
        return Date().timeIntervalSince(lastUserAction) < 30
    }
}

@MainActor
@Observable
final class NoteInteractionStore {
    static let shared = NoteInteractionStore()

    private(set) var deletedIds: Set<String> = []
    @ObservationIgnored private var models: [String: NoteCountsModel] = [:]
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private var pendingLocal: Set<String> = []
    @ObservationIgnored private var pendingRelay: Set<String> = []
    @ObservationIgnored private var relayFetchedAt: [String: Date] = [:]
    @ObservationIgnored private var localTask: Task<Void, Never>?
    @ObservationIgnored private var relayTask: Task<Void, Never>?
    @ObservationIgnored private var owner: String?
    private let capacity = 3000

    private var service: InteractionService { InteractionService.shared }

    func model(for note: Note) -> NoteCountsModel {
        resetIfAccountChanged()
        if let existing = models[note.id] { return existing }
        let model = NoteCountsModel(noteId: note.id, counts: InteractionCounts(note: note))
        models[note.id] = model
        order.append(note.id)
        evict()
        return model
    }

    func seed(_ notes: [Note]) {
        resetIfAccountChanged()
        for note in notes {
            if let existing = models[note.id] {
                if !existing.userActionActive { apply(InteractionCounts(note: note), to: existing, authoritative: false) }
            } else {
                _ = model(for: note)
            }
        }
    }

    func requestCounts(_ noteIds: [String], relays: Bool = true) {
        let ids = noteIds.filter { !$0.isEmpty }
        guard !ids.isEmpty else { return }
        pendingLocal.formUnion(ids)
        scheduleLocal()
        guard relays else { return }
        let now = Date()
        let due = ids.filter { relayFetchedAt[$0].map { now.timeIntervalSince($0) > 300 } ?? true }
        guard !due.isEmpty else { return }
        pendingRelay.formUnion(due)
        scheduleRelay()
    }

    func refreshAll() {
        requestCounts(Array(models.keys.suffix(400)), relays: false)
    }

    func applyLive(_ map: [String: InteractionCounts]) {
        for (id, counts) in map { if let model = models[id] { apply(counts, to: model, authoritative: false) } }
    }

    private func scheduleLocal() {
        localTask?.cancel()
        localTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard let self, !Task.isCancelled else { return }
            let batch = Array(self.pendingLocal)
            self.pendingLocal.removeAll()
            for chunk in batch.chunked(60) {
                let result = await self.service.localCounts(chunk)
                for (id, counts) in result { if let model = self.models[id] { self.apply(counts, to: model, authoritative: false) } }
            }
        }
    }

    private func scheduleRelay() {
        relayTask?.cancel()
        relayTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled else { return }
            let batch = Array(self.pendingRelay)
            self.pendingRelay.removeAll()
            let now = Date()
            for id in batch { self.relayFetchedAt[id] = now }
            await withTaskGroup(of: [String: InteractionCounts].self) { group in
                for chunk in batch.chunked(40) {
                    group.addTask { await InteractionService.shared.relayCounts(chunk) }
                }
                for await result in group {
                    for (id, counts) in result { if let model = self.models[id] { self.apply(counts, to: model, authoritative: false) } }
                }
            }
        }
    }

    private func apply(_ fresh: InteractionCounts, to model: NoteCountsModel, authoritative: Bool) {
        if model.userActionActive { return }
        let old = model.counts
        var next = fresh
        if !authoritative {
            next.reactions = max(fresh.reactions, old.reactions)
            next.reposts = max(fresh.reposts, old.reposts)
            next.replies = max(fresh.replies, old.replies)
            next.zapAmount = max(fresh.zapAmount, old.zapAmount)
            next.hasReacted = fresh.hasReacted || old.hasReacted
            next.hasReposted = fresh.hasReposted || old.hasReposted
            next.hasZapped = fresh.hasZapped || old.hasZapped
        } else {
            next.reactions = max(fresh.reactions, next.hasReacted ? 1 : 0)
        }
        if next != old { model.counts = next }
    }

    func toggleReaction(_ note: Note, content: String = "+") async {
        let model = model(for: note)
        guard !model.isReacting else { return }
        model.isReacting = true
        defer { model.isReacting = false }
        let wasReacted = model.counts.hasReacted
        model.lastUserAction = Date()
        model.counts.hasReacted = !wasReacted
        model.counts.reactions = max(0, model.counts.reactions + (wasReacted ? -1 : 1))
        do {
            if wasReacted { try await service.unreact(note) } else { try await service.react(to: note, content: content) }
        } catch {
            model.counts.hasReacted = wasReacted
            model.counts.reactions = max(0, model.counts.reactions + (wasReacted ? 1 : -1))
            model.lastUserAction = nil
            ToastCenter.shared.error(error)
        }
    }

    func toggleRepost(_ note: Note) async {
        let model = model(for: note)
        guard !model.isReposting else { return }
        model.isReposting = true
        defer { model.isReposting = false }
        let wasReposted = model.counts.hasReposted
        model.lastUserAction = Date()
        model.counts.hasReposted = !wasReposted
        model.counts.reposts = max(0, model.counts.reposts + (wasReposted ? -1 : 1))
        do {
            if wasReposted { try await service.undoRepost(note) } else { try await service.repost(note) }
        } catch {
            model.counts.hasReposted = wasReposted
            model.counts.reposts = max(0, model.counts.reposts + (wasReposted ? 1 : -1))
            model.lastUserAction = nil
            ToastCenter.shared.error(error)
        }
    }

    func repostAgain(_ note: Note) async {
        let model = model(for: note)
        model.lastUserAction = Date()
        model.counts.reposts += 1
        do { try await service.repost(note) } catch {
            model.counts.reposts = max(0, model.counts.reposts - 1)
            ToastCenter.shared.error(error)
        }
    }

    func markReplied(_ noteId: String) {
        guard let model = models[noteId] else { return }
        model.lastUserAction = Date()
        model.counts.replies += 1
    }

    func markDeleted(_ noteId: String) { deletedIds.insert(noteId) }

    func unmarkDeleted(_ noteId: String) { deletedIds.remove(noteId) }

    func isDeleted(_ noteId: String) -> Bool { deletedIds.contains(noteId) }

    private func resetIfAccountChanged() {
        let me = Session.shared.pubkey
        guard me != owner else { return }
        owner = me
        models.removeAll()
        order.removeAll()
        pendingLocal.removeAll()
        pendingRelay.removeAll()
        relayFetchedAt.removeAll()
        if !deletedIds.isEmpty { deletedIds.removeAll() }
    }

    private func evict() {
        guard order.count > capacity else { return }
        let overflow = order.count - capacity
        for id in order.prefix(overflow) { models.removeValue(forKey: id) }
        order.removeFirst(overflow)
    }
}

fileprivate extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
