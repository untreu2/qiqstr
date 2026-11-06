import Foundation
import Observation
import QiqstrCore

struct FollowSet: Identifiable, Hashable, Sendable {
    var eventId: String
    var pubkey: String
    var dTag: String
    var title: String
    var description: String
    var image: String
    var pubkeys: [String]
    var createdAt: Int

    var id: String { "\(pubkey):\(dTag)" }
    var displayTitle: String { title.isEmpty ? dTag : title }
    var coordinate: String { "30000:\(pubkey):\(dTag)" }

    init(eventId: String, pubkey: String, dTag: String, title: String = "", description: String = "", image: String = "", pubkeys: [String] = [], createdAt: Int = 0) {
        self.eventId = eventId
        self.pubkey = pubkey
        self.dTag = dTag
        self.title = title
        self.description = description
        self.image = image
        self.pubkeys = pubkeys
        self.createdAt = createdAt
    }

    init(json j: JSONObject) {
        self.init(
            eventId: j.str("id") ?? "",
            pubkey: j.str("pubkey") ?? "",
            dTag: j.str("dTag") ?? "",
            title: j.str("title") ?? "",
            description: j.str("description") ?? "",
            image: j.str("image") ?? "",
            pubkeys: j.strings("pubkeys"),
            createdAt: j.int("createdAt")
        )
    }

    init?(event: JSONObject) {
        var dTag = "", title = "", description = "", image = ""
        var members: [String] = []
        for tag in event.tags() where tag.count > 1 {
            switch tag[0] {
            case "d": dTag = tag[1]
            case "title": title = tag[1]
            case "description": description = tag[1]
            case "image": image = tag[1]
            case "p" where !tag[1].isEmpty && !members.contains(tag[1]): members.append(tag[1])
            default: break
            }
        }
        guard !dTag.isEmpty, let pubkey = event.str("pubkey") else { return nil }
        self.init(eventId: event.str("id") ?? "", pubkey: pubkey, dTag: dTag, title: title, description: description, image: image, pubkeys: members, createdAt: event.int("created_at"))
    }
}

@MainActor
@Observable
final class FollowSetService {
    static let shared = FollowSetService()

    private(set) var sets: [FollowSet] = []
    private(set) var followedSets: [FollowSet] = []
    private(set) var favoriteIds: [String] = UserDefaults.standard.stringArray(forKey: FollowSetService.favoritesKey) ?? []
    private(set) var isLoaded = false
    private(set) var isSyncing = false

    private var generation = 0
    private var publishChain: Task<Void, Never>?
    private var inflightPublishes = 0

    private static let hiddenDTags = ["mute", "Chat-Friends"]
    private static let favoritesKey = "favorite_follow_set_ids"
    private static let tombstonesKey = "deleted_follow_set_ids"

    var allSets: [FollowSet] { sets + followedSets }
    var favoriteSets: [FollowSet] { favoriteIds.compactMap { set(withId: $0) } }

    func set(withId id: String) -> FollowSet? {
        if let match = allSets.first(where: { $0.id == id }) { return match }
        return sets.first { $0.dTag == id }
    }

    func isOwn(_ set: FollowSet) -> Bool { set.pubkey == Session.shared.pubkey }
    func isFavorite(_ id: String) -> Bool { favoriteIds.contains(id) }
    func sets(containing pubkey: String) -> [FollowSet] { sets.filter { $0.pubkeys.contains(pubkey) } }

    func reset() {
        generation += 1
        sets = []
        followedSets = []
        isLoaded = false
        isSyncing = false
        publishChain = nil
    }

    func load() async {
        guard let me = Session.shared.pubkey else { return }
        let current = generation
        await loadFromDatabase(me, generation: current)
        await sync(me, generation: current)
    }

    func refresh() async {
        guard let me = Session.shared.pubkey else { return }
        await sync(me, generation: generation)
    }

    func toggleFavorite(_ id: String) {
        if let index = favoriteIds.firstIndex(of: id) { favoriteIds.remove(at: index) } else { favoriteIds.append(id) }
        UserDefaults.standard.set(favoriteIds, forKey: Self.favoritesKey)
        DataBus.shared.listsChanged()
    }

    @discardableResult
    func create(title: String, description: String = "", pubkeys: [String]) async throws -> FollowSet {
        guard let me = Session.shared.pubkey else { throw CoreError("Not signed in") }
        let dTag = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        let draft = FollowSet(eventId: "", pubkey: me, dTag: dTag, title: title.trimmingCharacters(in: .whitespacesAndNewlines), description: description.trimmingCharacters(in: .whitespacesAndNewlines), pubkeys: unique(pubkeys), createdAt: TimeFormat.now)
        return try await commit(draft, previous: nil)
    }

    @discardableResult
    func update(_ id: String, title: String, description: String) async throws -> FollowSet {
        guard let existing = ownSet(id) else { throw CoreError(L("exploreListNotFound")) }
        var next = existing
        next.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        next.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await commit(next, previous: existing)
    }

    @discardableResult
    func setMembers(_ pubkeys: [String], for id: String) async throws -> FollowSet {
        guard let existing = ownSet(id) else { throw CoreError(L("exploreListNotFound")) }
        var next = existing
        next.pubkeys = unique(pubkeys)
        return try await commit(next, previous: existing)
    }

    func addMember(_ pubkey: String, to id: String) async throws {
        guard let existing = ownSet(id), !existing.pubkeys.contains(pubkey) else { return }
        try await setMembers(existing.pubkeys + [pubkey], for: id)
    }

    func removeMember(_ pubkey: String, from id: String) async throws {
        guard let existing = ownSet(id), existing.pubkeys.contains(pubkey) else { return }
        try await setMembers(existing.pubkeys.filter { $0 != pubkey }, for: id)
    }

    func delete(_ id: String) async throws {
        guard let existing = ownSet(id), let sk = Session.shared.privateKey else { return }
        let current = generation
        let wasFavorite = isFavorite(existing.id)
        sets.removeAll { $0.id == existing.id }
        if wasFavorite { toggleFavorite(existing.id) }
        setTombstone(existing.id, at: max(existing.createdAt, TimeFormat.now))
        DataBus.shared.listsChanged()
        do {
            var tags: [[String]] = [["a", existing.coordinate], ["k", "30000"]]
            if !existing.eventId.isEmpty { tags.insert(["e", existing.eventId], at: 0) }
            let json = try createSignedEvent(kind: 5, content: "User deleted list", tags: tags, privateKeyHex: sk)
            try await SyncService.shared.publish(json)
            if !existing.eventId.isEmpty { _ = try? await dbDeleteEventsByIds(eventIds: [existing.eventId]) }
        } catch {
            guard current == generation else { return }
            setTombstone(existing.id, at: nil)
            upsert(existing)
            if wasFavorite { toggleFavorite(existing.id) }
            DataBus.shared.listsChanged()
            throw error
        }
    }

    private func ownSet(_ id: String) -> FollowSet? {
        guard let match = set(withId: id), isOwn(match) else { return nil }
        return match
    }

    private func commit(_ set: FollowSet, previous: FollowSet?) async throws -> FollowSet {
        let current = generation
        upsert(set)
        DataBus.shared.listsChanged()
        do {
            let published = try await enqueuePublish(set)
            guard current == generation else { return published }
            upsert(published)
            DataBus.shared.listsChanged()
            return published
        } catch {
            guard current == generation else { throw error }
            if let previous { upsert(previous) } else { sets.removeAll { $0.id == set.id } }
            DataBus.shared.listsChanged()
            throw error
        }
    }

    private func enqueuePublish(_ set: FollowSet) async throws -> FollowSet {
        inflightPublishes += 1
        defer { inflightPublishes -= 1 }
        let previous = publishChain
        let task = Task<Result<FollowSet, Error>, Never> {
            await previous?.value
            do { return .success(try await self.publish(set)) } catch { return .failure(error) }
        }
        publishChain = Task { _ = await task.value }
        return try await task.value.get()
    }

    private func publish(_ set: FollowSet) async throws -> FollowSet {
        guard let sk = Session.shared.privateKey else { throw CoreError("Not signed in") }
        var tags: [[String]] = [["d", set.dTag]]
        if !set.title.isEmpty { tags.append(["title", set.title]) }
        if !set.description.isEmpty { tags.append(["description", set.description]) }
        if !set.image.isEmpty { tags.append(["image", set.image]) }
        tags.append(contentsOf: set.pubkeys.map { ["p", $0] })
        let json = try createSignedEvent(kind: 30000, content: "", tags: tags, privateKeyHex: sk)
        let event = try await SyncService.shared.publish(json)
        setTombstone(set.id, at: nil)
        return FollowSet(event: event) ?? set
    }

    private func upsert(_ set: FollowSet) {
        if let index = sets.firstIndex(where: { $0.id == set.id }) {
            sets[index] = set
        } else {
            sets.insert(set, at: 0)
        }
    }

    private func sync(_ me: String, generation current: Int) async {
        isSyncing = true
        defer { if current == generation { isSyncing = false } }
        let follows = await SyncService.shared.followingList(me).filter { $0 != me }
        let events = await SyncService.shared.fetchEvents(["kinds": [30000], "authors": [me] + follows, "limit": 500], timeout: 10)
        if !events.isEmpty { _ = try? await dbSaveEvents(eventsJson: JSON.string(events)) }
        guard current == generation else { return }
        await loadFromDatabase(me, generation: current)
        guard current == generation else { return }
        let people = Set(sets.flatMap(\.pubkeys) + followedSets.map(\.pubkey))
        if !people.isEmpty { await ProfileCache.shared.load(Array(people)) }
    }

    private func loadFromDatabase(_ me: String, generation current: Int) async {
        let follows = await SyncService.shared.followingList(me).filter { $0 != me }
        let own = await fetchSets([me], limit: 100)
        let others = follows.isEmpty ? [] : await fetchSets(follows, limit: 500)
        guard current == generation else { return }
        if inflightPublishes == 0 { sets = filterDeleted(own) }
        followedSets = filterDeleted(others)
        isLoaded = true
        DataBus.shared.listsChanged()
    }

    private func fetchSets(_ authors: [String], limit: UInt32) async -> [FollowSet] {
        guard !authors.isEmpty else { return [] }
        let raw = try? await dbGetFollowSets(authorsHex: authors, limit: limit, hiddenDTags: Self.hiddenDTags)
        return JSON.array(raw).map(FollowSet.init(json:)).filter { !$0.dTag.isEmpty }
    }

    private var tombstones: [String: Int] {
        (UserDefaults.standard.dictionary(forKey: Self.tombstonesKey) as? [String: Int]) ?? [:]
    }

    private func setTombstone(_ id: String, at timestamp: Int?) {
        var map = tombstones
        map[id] = timestamp
        UserDefaults.standard.set(map, forKey: Self.tombstonesKey)
    }

    private func filterDeleted(_ list: [FollowSet]) -> [FollowSet] {
        let map = tombstones
        guard !map.isEmpty else { return list }
        return list.filter { set in
            guard let deletedAt = map[set.id] else { return true }
            return set.createdAt > deletedAt
        }
    }

    private func unique(_ pubkeys: [String]) -> [String] {
        var seen = Set<String>()
        return pubkeys.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
