import Foundation
import Observation
import QiqstrCore

@MainActor
@Observable
final class PinnedNotesService {
    static let shared = PinnedNotesService()
    private(set) var pinnedIds: [String] = []
    private(set) var version = 0
    private var owner: String?
    private var extraTags: [[String]] = []
    private var latestCreatedAt = 0
    private var generation = 0

    private static let kind = 10001

    func isPinned(_ noteId: String) -> Bool { pinnedIds.contains(noteId) }

    func reset() {
        generation += 1
        owner = nil
        pinnedIds = []
        extraTags = []
        latestCreatedAt = 0
        version &+= 1
    }

    func cachedIds(for pubkey: String) async -> [String] {
        guard let event = await localEvent(for: pubkey) else { return pubkey == owner ? pinnedIds : [] }
        if pubkey == Session.shared.pubkey { adopt(event, owner: pubkey) }
        return Self.noteIds(in: event)
    }

    func load(for pubkey: String) async -> [String] {
        let generation = self.generation
        let local = await localEvent(for: pubkey)
        let remote = await SyncService.shared
            .fetchEvents(["kinds": [Self.kind], "authors": [pubkey], "limit": 1], timeout: 8)
            .filter { $0.str("pubkey") == pubkey && $0.int("kind") == Self.kind }
            .max { $0.int("created_at") < $1.int("created_at") }
        if let remote, remote.int("created_at") > (local?.int("created_at") ?? -1) {
            _ = try? await dbSaveEvents(eventsJson: JSON.string([remote]))
        }
        let newest = [local, remote].compactMap { $0 }.max { $0.int("created_at") < $1.int("created_at") }
        guard generation == self.generation else { return newest.map(Self.noteIds) ?? [] }
        if pubkey == Session.shared.pubkey {
            if let newest { adopt(newest, owner: pubkey) } else if owner != pubkey { owner = pubkey; pinnedIds = []; version &+= 1 }
        }
        return newest.map(Self.noteIds) ?? []
    }

    func toggle(_ noteId: String) async throws {
        let key = try Session.shared.requireSigner()
        guard let me = Session.shared.pubkey else { throw CoreError("Not signed in") }
        if let base = try await SyncService.shared.latestEditableEvent(kind: Self.kind, author: me) {
            adopt(base, owner: me)
        } else if owner != me || latestCreatedAt == 0 {
            owner = me
            pinnedIds = []
            extraTags = []
        }
        let previous = pinnedIds
        let updated = previous.contains(noteId) ? previous.filter { $0 != noteId } : previous + [noteId]
        owner = me
        pinnedIds = updated
        version &+= 1
        let previousLatest = latestCreatedAt
        latestCreatedAt = max(latestCreatedAt, TimeFormat.now)
        do {
            let tags = updated.map { ["e", $0] } + extraTags
            let eventJson = try createSignedEvent(kind: UInt16(Self.kind), content: "", tags: tags, privateKeyHex: key)
            let event = try await SyncService.shared.publish(eventJson)
            latestCreatedAt = max(latestCreatedAt, event.int("created_at"))
            DataBus.shared.listsChanged()
        } catch {
            if owner == me, pinnedIds == updated {
                latestCreatedAt = previousLatest
                pinnedIds = previous
                version &+= 1
            }
            throw error
        }
    }

    private func adopt(_ event: JSONObject, owner pubkey: String) {
        let created = event.int("created_at")
        guard owner != pubkey || created >= latestCreatedAt else { return }
        owner = pubkey
        latestCreatedAt = created
        extraTags = event.tags().filter { !($0.first == "e" && $0.count > 1) }
        let ids = Self.noteIds(in: event)
        if ids != pinnedIds {
            pinnedIds = ids
            version &+= 1
        }
    }

    private func localEvent(for pubkey: String) async -> JSONObject? {
        let filter = JSON.string(["kinds": [Self.kind], "authors": [pubkey]])
        return JSON.array(try? await dbQueryEvents(filterJson: filter, limit: 1))
            .max { $0.int("created_at") < $1.int("created_at") }
    }

    private static func noteIds(in event: JSONObject) -> [String] {
        var seen = Set<String>()
        return event.tags().compactMap { tag in
            guard tag.count > 1, tag[0] == "e", tag[1].count == 64, seen.insert(tag[1]).inserted else { return nil }
            return tag[1]
        }
    }
}
