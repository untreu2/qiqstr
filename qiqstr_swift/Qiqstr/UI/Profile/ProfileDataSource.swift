import Foundation
import QiqstrCore

struct FollowScore: Equatable {
    var count: Int
    var avatarUrls: [String]
}

@MainActor
enum ProfileDataSource {
    static let pageSize = 30

    private static var session: Session { Session.shared }

    static func profile(_ pubkey: String) async -> Profile? {
        guard let raw = try? await dbGetProfile(pubkeyHex: pubkey), let obj = JSON.object(raw) else { return nil }
        return Profile(json: obj, fallbackPubkey: pubkey)
    }

    static func rawMetadata(_ pubkey: String) async -> JSONObject {
        let filter = JSON.string(["kinds": [0], "authors": [pubkey]])
        let events = JSON.array(try? await dbQueryEvents(filterJson: filter, limit: 1))
        if let newest = events.max(by: { $0.int("created_at") < $1.int("created_at") }),
           let content = JSON.object(newest["content"] as? String) {
            return content
        }
        if let raw = try? await dbGetProfile(pubkeyHex: pubkey), let obj = JSON.object(raw) { return obj }
        return [:]
    }

    static func notes(_ pubkey: String, limit: Int, until: Int? = nil) async -> [Note] {
        await Note.parsed(try? await dbGetHydratedProfileNotes(
            pubkeyHex: pubkey,
            limit: UInt32(limit),
            mutedPubkeys: mutedPubkeys(excluding: pubkey),
            mutedWords: session.mutedWords,
            filterReplies: true,
            currentUserPubkeyHex: session.pubkey,
            untilTimestamp: until.map(Int64.init)
        ))
    }

    static func replies(_ pubkey: String, limit: Int, until: Int? = nil) async -> [Note] {
        await Note.parsed(try? await dbGetHydratedProfileReplies(
            pubkeyHex: pubkey,
            limit: UInt32(limit),
            mutedPubkeys: mutedPubkeys(excluding: pubkey),
            mutedWords: session.mutedWords,
            currentUserPubkeyHex: session.pubkey,
            untilTimestamp: until.map(Int64.init)
        ))
    }

    static func likes(_ pubkey: String, reactionLimit: Int) async -> [Note] {
        await Note.parsed(try? await dbGetHydratedReactionNotes(
            pubkeyHex: pubkey,
            limit: UInt32(reactionLimit),
            mutedPubkeys: session.mutedPubkeys,
            mutedWords: session.mutedWords,
            currentUserPubkeyHex: session.pubkey
        ))
    }

    static func notes(ids: [String], owner: String? = nil) async -> [Note] {
        guard !ids.isEmpty else { return [] }
        return await Note.parsed(try? await dbGetHydratedNotesByIds(
            eventIds: ids,
            mutedPubkeys: session.mutedPubkeys.filter { $0 != owner },
            mutedWords: session.mutedWords,
            currentUserPubkeyHex: session.pubkey
        ))
    }

    static func fetchMissingNotes(_ ids: [String]) async -> Bool {
        let wanted = Array(Set(ids)).prefix(100)
        guard !wanted.isEmpty else { return false }
        let events = await SyncService.shared.fetchEvents(["ids": Array(wanted)], timeout: 8)
        guard !events.isEmpty else { return false }
        _ = try? await dbSaveEvents(eventsJson: JSON.string(events))
        SyncService.shared.fetchMissingProfiles(Array(Set(events.compactMap { $0.str("pubkey") })))
        return true
    }

    static func likedNoteIds(_ pubkey: String, reactionLimit: Int) async -> [String] {
        let filter = JSON.string(["kinds": [7], "authors": [pubkey]])
        let reactions = JSON.array(try? await dbQueryEvents(filterJson: filter, limit: UInt32(reactionLimit)))
        var seen = Set<String>()
        return reactions.compactMap { event in
            guard let tag = event.tags().first(where: { $0.first == "e" && $0.count > 1 }), seen.insert(tag[1]).inserted else { return nil }
            return tag[1]
        }
    }

    static func syncOlderReactions(_ pubkey: String, before: Int?) async -> Int {
        var filter: JSONObject = ["kinds": [7], "authors": [pubkey], "limit": 100]
        if let before { filter["until"] = before - 1 }
        let events = await SyncService.shared.fetchEvents(filter, timeout: 8)
        if !events.isEmpty { _ = try? await dbSaveEvents(eventsJson: JSON.string(events)) }
        return events.count
    }

    static func oldestReactionTimestamp(_ pubkey: String, reactionLimit: Int) async -> Int? {
        let filter = JSON.string(["kinds": [7], "authors": [pubkey]])
        return JSON.array(try? await dbQueryEvents(filterJson: filter, limit: UInt32(reactionLimit)))
            .map { $0.int("created_at") }
            .filter { $0 > 0 }
            .min()
    }

    static func following(_ pubkey: String) async -> [String] {
        (try? await dbGetFollowingList(pubkeyHex: pubkey)) ?? []
    }

    static func followerCount(_ pubkey: String) async -> Int? {
        guard let raw = try? await fetchFollowerCounts(pubkeyHexes: [pubkey]), let map = JSON.object(raw) else { return nil }
        return (map[pubkey] as? NSNumber)?.intValue
    }

    static func followScore(target: String) async -> FollowScore? {
        guard let me = session.pubkey, me != target,
              let raw = try? await dbCalculateFollowScore(currentUserHex: me, targetHex: target),
              let obj = JSON.object(raw) else { return nil }
        let count = obj.int("count")
        guard count > 0 else { return nil }
        return FollowScore(count: count, avatarUrls: obj.strings("avatarUrls"))
    }

    static func mutualFollowers(target: String) async -> [String] {
        guard let me = session.pubkey, me != target else { return [] }
        let mine = await following(me).filter { $0 != me && $0 != target }
        guard !mine.isEmpty else { return [] }
        var matched = Set<String>()
        for start in stride(from: 0, to: mine.count, by: 500) {
            let chunk = Array(mine[start..<min(start + 500, mine.count)])
            let filter = JSON.string(["kinds": [3], "authors": chunk, "#p": [target]])
            for event in JSON.array(try? await dbQueryEvents(filterJson: filter, limit: UInt32(chunk.count))) {
                if let author = event.str("pubkey") { matched.insert(author) }
            }
        }
        if matched.isEmpty {
            for pubkey in mine where await following(pubkey).contains(target) { matched.insert(pubkey) }
        }
        return mine.filter { matched.contains($0) }
    }

    static func followers(_ pubkey: String) async -> [String] {
        let events = await SyncService.shared.fetchEvents(["kinds": [3], "#p": [pubkey], "limit": 500], timeout: 12)
        var newestByAuthor: [String: Int] = [:]
        for event in events {
            guard let author = event.str("pubkey"), author != pubkey else { continue }
            let listsTarget = event.tags().contains { $0.count > 1 && $0[0] == "p" && $0[1] == pubkey }
            guard listsTarget else { continue }
            newestByAuthor[author] = max(newestByAuthor[author] ?? 0, event.int("created_at"))
        }
        return newestByAuthor.sorted { $0.value > $1.value }.map(\.key)
    }

    static func publishMetadata(_ metadata: JSONObject) async throws {
        guard let key = session.privateKey else { throw CoreError("Not signed in") }
        let eventJson = try createProfileEvent(profileJson: JSON.string(metadata), privateKeyHex: key)
        try await SyncService.shared.publish(eventJson)
    }

    private static func mutedPubkeys(excluding pubkey: String) -> [String] {
        session.mutedPubkeys.filter { $0 != pubkey }
    }
}
