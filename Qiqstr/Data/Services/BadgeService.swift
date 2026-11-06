import Foundation
import QiqstrCore

struct ProfileBadge: Identifiable, Hashable, Sendable {
    var issuer: String
    var dTag: String
    var name: String
    var description: String
    var image: String
    var thumb: String

    var id: String { "\(issuer):\(dTag)" }
    var displayName: String { name.isEmpty ? dTag : name }
    var thumbURL: String? { thumb.nilIfEmpty ?? image.nilIfEmpty }
    var imageURL: String? { image.nilIfEmpty ?? thumb.nilIfEmpty }

    init?(definition event: JSONObject) {
        guard event.int("kind") == 30009, let issuer = event.str("pubkey") else { return nil }
        var dTag = "", name = "", description = "", image = "", thumb = ""
        var thumbWidth = Int.max
        for tag in event.tags() where tag.count > 1 {
            switch tag[0] {
            case "d": dTag = tag[1]
            case "name": name = tag[1]
            case "description": description = tag[1]
            case "image": image = tag[1]
            case "thumb":
                let width = tag.count > 2 ? Int(tag[2].split(separator: "x").first ?? "") ?? Int.max : Int.max
                if thumb.isEmpty || (width >= 64 && width < thumbWidth) {
                    thumb = tag[1]
                    thumbWidth = width
                }
            default: break
            }
        }
        guard !dTag.isEmpty else { return nil }
        self.issuer = issuer
        self.dTag = dTag
        self.name = name
        self.description = description
        self.image = image
        self.thumb = thumb
    }
}

@MainActor
final class BadgeService {
    static let shared = BadgeService()

    private var cache: [String: [ProfileBadge]] = [:]
    private static let listKinds = [10008, 30008]
    private static let maxBadges = 40

    func cached(for pubkey: String) -> [ProfileBadge]? { cache[pubkey] }

    func local(for pubkey: String) async -> [ProfileBadge] {
        guard let list = newestList(await queryLocal(["kinds": Self.listKinds, "authors": [pubkey]], limit: 10), pubkey: pubkey) else { return [] }
        let refs = Self.references(in: list)
        guard !refs.isEmpty else { return [] }
        let definitions = await queryLocal(Self.definitionFilter(refs), limit: UInt32(refs.count * 2 + 4))
        let badges = Self.resolve(refs, definitions: definitions)
        if !badges.isEmpty { cache[pubkey] = badges }
        return badges
    }

    func refresh(for pubkey: String) async -> [ProfileBadge] {
        let local = newestList(await queryLocal(["kinds": Self.listKinds, "authors": [pubkey]], limit: 10), pubkey: pubkey)
        let remoteLists = await SyncService.shared.fetchEvents(["kinds": Self.listKinds, "authors": [pubkey], "limit": 4], timeout: 8)
        let remote = newestList(remoteLists, pubkey: pubkey)
        if let remote, remote.int("created_at") > (local?.int("created_at") ?? -1) {
            _ = try? await dbSaveEvents(eventsJson: JSON.string([remote]))
        }
        guard let list = [local, remote].compactMap({ $0 }).max(by: { $0.int("created_at") < $1.int("created_at") }) else {
            cache[pubkey] = []
            return []
        }
        let refs = Self.references(in: list)
        guard !refs.isEmpty else { cache[pubkey] = []; return [] }
        var definitions = await queryLocal(Self.definitionFilter(refs), limit: UInt32(refs.count * 2 + 4))
        let known = Set(definitions.compactMap { ProfileBadge(definition: $0)?.id })
        let missing = refs.filter { !known.contains($0.id) }
        if !missing.isEmpty {
            var filter = Self.definitionFilter(missing)
            filter["limit"] = missing.count * 2 + 4
            let fetched = await SyncService.shared.fetchEvents(filter, timeout: 8).filter { $0.int("kind") == 30009 }
            if !fetched.isEmpty {
                _ = try? await dbSaveEvents(eventsJson: JSON.string(fetched))
                definitions += fetched
            }
        }
        let badges = Self.resolve(refs, definitions: definitions)
        cache[pubkey] = badges
        return badges
    }

    private func queryLocal(_ filter: JSONObject, limit: UInt32) async -> [JSONObject] {
        JSON.array(try? await dbQueryEvents(filterJson: JSON.string(filter), limit: limit))
    }

    private func newestList(_ events: [JSONObject], pubkey: String) -> JSONObject? {
        events
            .filter { event in
                guard event.str("pubkey") == pubkey else { return false }
                switch event.int("kind") {
                case 10008: return true
                case 30008: return event.tags().contains { $0.count > 1 && $0[0] == "d" && $0[1] == "profile_badges" }
                default: return false
                }
            }
            .max { $0.int("created_at") < $1.int("created_at") }
    }

    private struct Reference: Hashable {
        var issuer: String
        var dTag: String
        var id: String { "\(issuer):\(dTag)" }
    }

    private static func references(in event: JSONObject) -> [Reference] {
        var seen = Set<String>()
        var result: [Reference] = []
        for tag in event.tags() where tag.count > 1 && tag[0] == "a" {
            let parts = tag[1].split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, parts[0] == "30009", parts[1].count == 64, !parts[2].isEmpty else { continue }
            let ref = Reference(issuer: parts[1], dTag: parts[2])
            if seen.insert(ref.id).inserted { result.append(ref) }
            if result.count >= maxBadges { break }
        }
        return result
    }

    private static func definitionFilter(_ refs: [Reference]) -> JSONObject {
        ["kinds": [30009], "authors": Array(Set(refs.map(\.issuer))), "#d": Array(Set(refs.map(\.dTag)))]
    }

    private static func resolve(_ refs: [Reference], definitions: [JSONObject]) -> [ProfileBadge] {
        var byId: [String: (ProfileBadge, Int)] = [:]
        for event in definitions {
            guard let badge = ProfileBadge(definition: event) else { continue }
            let created = event.int("created_at")
            if let existing = byId[badge.id], existing.1 >= created { continue }
            byId[badge.id] = (badge, created)
        }
        return refs.compactMap { byId[$0.id]?.0 }
    }
}
