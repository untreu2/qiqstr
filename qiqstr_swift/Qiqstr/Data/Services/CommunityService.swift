import Foundation
import Observation
import QiqstrCore

// MARK: Models

/// A NIP-29 group. It lives on one relay, which enforces membership and moderation.
nonisolated struct RelayGroup: Identifiable, Hashable, Sendable {
    let groupId: String
    let relay: String
    var name: String = ""
    var about: String = ""
    var picture: String = ""
    var isPrivate = false
    var isClosed = false

    /// The "host'groupid" form clients use to share a group.
    var id: String { "\(relay)'\(groupId)" }
    var displayName: String { name.isEmpty ? groupId : name }
    var relayHost: String { URL(string: relay)?.host() ?? relay }

    init(groupId: String, relay: String, name: String = "") {
        self.groupId = groupId
        self.relay = CommunityService.normalizedRelay(relay) ?? relay
        self.name = name
    }

    init?(metadata json: JSONObject, relay: String) {
        guard json.int("kind") == CommunityService.groupMetadataKind,
              let groupId = json.tags().first(where: { $0.first == "d" && $0.count > 1 })?[1], !groupId.isEmpty else { return nil }
        self.init(groupId: groupId, relay: relay)
        for tag in json.tags() where !tag.isEmpty {
            switch tag[0] {
            case "name" where tag.count > 1: name = tag[1]
            case "about" where tag.count > 1: about = tag[1]
            case "picture" where tag.count > 1: picture = tag[1]
            case "private": isPrivate = true
            case "closed": isClosed = true
            default: break
            }
        }
    }

    /// Parses "wss://relay.example'groupid", "relay.example'groupid" or a "naddr"-less group link.
    init?(link: String) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "'", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty, let relay = CommunityService.normalizedRelay(parts[0]) else { return nil }
        self.init(groupId: parts[1], relay: relay)
    }
}

/// A NIP-72 moderated community (kind 34550).
nonisolated struct Community: Identifiable, Hashable, Sendable {
    let pubkey: String
    let dTag: String
    var name: String = ""
    var summary: String = ""
    var image: String = ""
    var rules: String = ""
    var moderators: [String] = []
    var relays: [String] = []
    var createdAt: Int = 0

    var coordinate: String { "\(CommunityService.communityKind):\(pubkey):\(dTag)" }
    var id: String { coordinate }
    var displayName: String { name.isEmpty ? dTag : name }
    var naddr: String? { Nip19.naddr(kind: UInt16(CommunityService.communityKind), pubkey: pubkey, identifier: dTag) }
    var team: [String] { [pubkey] + moderators.filter { $0 != pubkey } }

    init?(json: JSONObject) {
        guard json.int("kind") == CommunityService.communityKind, let pubkey = json.str("pubkey"),
              let dTag = json.tags().first(where: { $0.first == "d" && $0.count > 1 })?[1] else { return nil }
        self.pubkey = pubkey
        self.dTag = dTag
        createdAt = json.int("created_at")
        for tag in json.tags() where tag.count > 1 {
            switch tag[0] {
            case "name": name = tag[1]
            case "description": summary = tag[1]
            case "image": image = tag[1]
            case "rules": rules = tag[1]
            case "moderator" where tag[1].count == 64: if !moderators.contains(tag[1]) { moderators.append(tag[1]) }
            case "relay": if let relay = CommunityService.normalizedRelay(tag[1]), !relays.contains(relay) { relays.append(relay) }
            default: break
            }
        }
    }

    static func parse(coordinate: String) -> (pubkey: String, dTag: String)? {
        let parts = coordinate.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == String(CommunityService.communityKind), parts[1].count == 64 else { return nil }
        return (parts[1], parts[2])
    }
}

/// A NIP-28 public chat channel, created by a kind 40 event and updated by its creator with kind 41.
nonisolated struct PublicChannel: Identifiable, Hashable, Sendable {
    let id: String
    let creator: String
    var name: String = ""
    var about: String = ""
    var picture: String = ""
    var relays: [String] = []
    var createdAt: Int = 0
    var updatedAt: Int = 0

    var displayName: String { name.isEmpty ? L("channelUntitled") : name }

    init?(creation json: JSONObject) {
        guard json.int("kind") == CommunityService.channelCreateKind, let id = json.str("id"), let creator = json.str("pubkey") else { return nil }
        self.id = id
        self.creator = creator
        createdAt = json.int("created_at")
        apply(content: json["content"] as? String)
    }

    mutating func apply(metadata json: JSONObject) {
        guard json.int("kind") == CommunityService.channelMetadataKind, json.str("pubkey") == creator, json.int("created_at") > updatedAt else { return }
        updatedAt = json.int("created_at")
        apply(content: json["content"] as? String)
    }

    private mutating func apply(content: String?) {
        guard let meta = JSON.object(content) else { return }
        if let value = meta.str("name") { name = value }
        if let value = meta.str("about") { about = value }
        if let value = meta.str("picture") { picture = value }
        if let list = meta["relays"] as? [String] { relays = list.compactMap(CommunityService.normalizedRelay) }
    }
}

nonisolated struct CommunityChatMessage: Identifiable, Hashable, Sendable {
    let id: String
    let pubkey: String
    let content: String
    let createdAt: Int

    init?(json: JSONObject, kind: Int) {
        guard json.int("kind") == kind, let id = json.str("id"), let pubkey = json.str("pubkey") else { return nil }
        let content = (json["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        self.id = id
        self.pubkey = pubkey
        self.content = content
        createdAt = json.int("created_at")
    }

    static func list(_ events: [JSONObject], kind: Int) -> [CommunityChatMessage] {
        var seen = Set<String>()
        return events.compactMap { CommunityChatMessage(json: $0, kind: kind) }
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }
}

// MARK: Safety

/// Keeps discovery lists free of abusive rooms. Anything that sexualises minors is always hidden;
/// adult rooms are hidden unless the account shows sensitive content.
enum CommunitySafety {
    private static let minorTerms = ["under 18", "under18", "underage", "under age", "minor", "minors", "teen", "teens", "preteen", "kid", "kids", "child", "children", "loli", "lolis", "shota", "jailbait", "young girl", "young boy", "little girl", "little boy", "little kids", "schoolgirl", "schoolboy", "cp"]
    private static let adultTerms = ["sex", "sexy", "nude", "nudes", "naked", "porn", "nsfw", "xxx", "horny", "hot pics", "pics", "fetish", "slave", "onlyfans", "erotic", "cum", "dick", "pussy", "boobs", "hentai", "kink", "18+", "video call", "sexting"]

    static func allows(_ fields: String...) -> Bool {
        let text = " " + fields.joined(separator: " ").lowercased().map { $0.isLetter || $0.isNumber || $0 == "+" ? $0 : " " }.reduce(into: "") { $0.append($1) } + " "
        func has(_ terms: [String]) -> Bool { terms.contains { text.contains(" \($0) ") } }
        let adult = has(adultTerms)
        if adult && has(minorTerms) { return false }
        if adult && !WebOfTrustService.showsSensitiveContent { return false }
        return true
    }

    /// Strict trust for discovery: someone you follow, or trusted by a web of trust that has finished building.
    @MainActor
    static func isTrusted(_ pubkey: String) -> Bool {
        if pubkey == Session.shared.pubkey || FollowService.shared.isFollowing(pubkey) { return true }
        let trust = WebOfTrustService.shared
        return trust.isReady && trust.isTrusted(pubkey)
    }
}

// MARK: Service

@MainActor
@Observable
final class CommunityService {
    static let shared = CommunityService()

    static let groupMessageKind = 9
    static let groupJoinKind = 9021
    static let groupLeaveKind = 9022
    static let groupMetadataKind = 39000
    static let groupAdminsKind = 39001
    static let groupMembersKind = 39002
    static let groupListKind = 10009
    static let communityKind = 34550
    static let communityListKind = 10004
    static let communityPostKind = 1111
    static let channelCreateKind = 40
    static let channelMetadataKind = 41
    static let channelMessageKind = 42
    static let channelListKind = 10005

    /// Public NIP-29 relays that list their groups.
    static let groupRelays = ["wss://chat.wisp.talk", "wss://relay.highlighter.com", "wss://groups.hzrd149.com", "wss://spatia-arcana.com", "wss://groups.0xchat.com"]

    private(set) var groups: [RelayGroup] = []
    private(set) var communities: [Community] = []
    private(set) var channels: [PublicChannel] = []
    private(set) var hasLoaded = false
    @ObservationIgnored private var owner: String?
    @ObservationIgnored private var groupCache: [String: RelayGroup] = [:]
    @ObservationIgnored private var communityCache: [String: Community] = [:]
    @ObservationIgnored private var channelCache: [String: PublicChannel] = [:]

    func reset() {
        owner = nil
        groups = []
        communities = []
        channels = []
        hasLoaded = false
    }

    nonisolated static func normalizedRelay(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") { value = "wss://\(value)" }
        while value.hasSuffix("/") { value.removeLast() }
        guard let url = URL(string: value), ["wss", "ws"].contains(url.scheme?.lowercased() ?? ""), let host = url.host(), host.contains(".") else { return nil }
        return value
    }

    // MARK: Joined lists

    func load() async {
        guard let me = Session.shared.pubkey else { return }
        if owner != me { reset(); owner = me }
        async let groupList = SyncService.shared.fetchReplaceable(kind: Self.groupListKind, author: me)
        async let communityList = SyncService.shared.fetchReplaceable(kind: Self.communityListKind, author: me)
        async let channelList = SyncService.shared.fetchReplaceable(kind: Self.channelListKind, author: me)
        let (g, c, ch) = await (groupList, communityList, channelList)
        guard me == Session.shared.pubkey else { return }
        func newest(_ events: [JSONObject]) -> [[String]] { events.max { $0.int("created_at") < $1.int("created_at") }?.tags() ?? [] }
        let groupRefs = newest(g).filter { $0.first == "group" && $0.count > 2 }.map { RelayGroup(groupId: $0[1], relay: $0[2], name: $0.count > 3 ? $0[3] : "") }
        let coordinates = newest(c).filter { $0.first == "a" && $0.count > 1 }.map { $0[1] }
        let channelIds = newest(ch).filter { $0.first == "e" && $0.count > 1 }.map { $0[1] }
        groups = groupRefs.map { groupCache[$0.id] ?? $0 }
        hasLoaded = true
        async let resolvedGroups = resolve(groups: groupRefs)
        async let resolvedCommunities = resolve(coordinates: coordinates)
        async let resolvedChannels = resolve(channelIds: channelIds)
        let (rg, rc, rch) = await (resolvedGroups, resolvedCommunities, resolvedChannels)
        guard me == Session.shared.pubkey else { return }
        groups = rg
        communities = rc
        channels = rch
    }

    func isJoined(_ group: RelayGroup) -> Bool { groups.contains { $0.id == group.id } }
    func isJoined(_ community: Community) -> Bool { communities.contains { $0.id == community.id } }
    func isJoined(_ channel: PublicChannel) -> Bool { channels.contains { $0.id == channel.id } }

    private func editList(kind: Int, _ mutate: ([[String]]) -> [[String]]) async throws {
        guard let me = Session.shared.pubkey else { return }
        let key = try Session.shared.requireSigner()
        let base = try await SyncService.shared.latestEditableEvent(kind: kind, author: me, allowingNew: true)
        let tags = mutate(base?.tags() ?? [])
        let event = try createSignedEvent(kind: UInt16(kind), content: (base?["content"] as? String) ?? "", tags: tags, privateKeyHex: key)
        try await SyncService.shared.publish(event)
    }

    // MARK: Resolving

    private func resolve(groups refs: [RelayGroup]) async -> [RelayGroup] {
        let byRelay = Dictionary(grouping: refs, by: \.relay)
        var found: [String: RelayGroup] = [:]
        await withTaskGroup(of: [RelayGroup].self) { tasks in
            for (relay, list) in byRelay {
                tasks.addTask {
                    let events = await Self.fetch(["kinds": [Self.groupMetadataKind], "#d": list.map(\.groupId)], relays: [relay], timeout: 6)
                    return events.compactMap { RelayGroup(metadata: $0, relay: relay) }
                }
            }
            for await list in tasks { for group in list { found[group.id] = group } }
        }
        for group in found.values { groupCache[group.id] = group }
        return refs.map { found[$0.id] ?? groupCache[$0.id] ?? $0 }
    }

    private func resolve(coordinates: [String]) async -> [Community] {
        let parsed = coordinates.compactMap(Community.parse(coordinate:))
        guard !parsed.isEmpty else { return [] }
        let missing = parsed.filter { communityCache["\(Self.communityKind):\($0.pubkey):\($0.dTag)"] == nil }
        if !missing.isEmpty {
            let events = await SyncService.shared.fetchEvents(["kinds": [Self.communityKind], "authors": Array(Set(missing.map(\.pubkey))), "#d": Array(Set(missing.map(\.dTag)))], timeout: 8)
            for community in Self.latestCommunities(events) { communityCache[community.id] = community }
        }
        return coordinates.compactMap { communityCache[$0] }
    }

    private func resolve(channelIds ids: [String]) async -> [PublicChannel] {
        let missing = ids.filter { channelCache[$0] == nil }
        if !missing.isEmpty {
            let relays = await Self.readRelays()
            async let creations = Self.fetch(["kinds": [Self.channelCreateKind], "ids": missing], relays: relays, timeout: 8)
            async let metadata = Self.fetch(["kinds": [Self.channelMetadataKind], "#e": missing, "limit": 200], relays: relays, timeout: 8)
            let (created, meta) = await (creations, metadata)
            for channel in Self.channels(created: created, metadata: meta) { channelCache[channel.id] = channel }
        }
        return ids.compactMap { channelCache[$0] }
    }

    func community(coordinate: String) async -> Community? {
        if let cached = communityCache[coordinate] { return cached }
        return await resolve(coordinates: [coordinate]).first
    }

    func channel(id: String) async -> PublicChannel? {
        if let cached = channelCache[id] { return cached }
        return await resolve(channelIds: [id]).first
    }

    func group(_ ref: RelayGroup) async -> RelayGroup {
        await resolve(groups: [ref]).first ?? ref
    }

    func cachedGroup(_ id: String) -> RelayGroup? { groupCache[id] ?? groups.first { $0.id == id } }

    // MARK: Discovery

    func discoverGroups(relay: String) async -> [RelayGroup] {
        guard let relay = Self.normalizedRelay(relay) else { return [] }
        let events = await Self.fetch(["kinds": [Self.groupMetadataKind], "limit": 300], relays: [relay], timeout: 8)
        var seen = Set<String>()
        let found = events.sorted { $0.int("created_at") > $1.int("created_at") }
            .compactMap { RelayGroup(metadata: $0, relay: relay) }
            .filter { !$0.isPrivate && CommunitySafety.allows($0.name, $0.about) && seen.insert($0.id).inserted }
        for group in found { groupCache[group.id] = group }
        return found.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Communities that people you follow have joined or run, most popular first.
    func discoverCommunities() async -> [Community] {
        let follows = Array(FollowService.shared.following.prefix(500))
        var counts: [String: Int] = [:]
        if !follows.isEmpty {
            let lists = await SyncService.shared.fetchEvents(["kinds": [Self.communityListKind], "authors": follows, "limit": 500], timeout: 8)
            for list in lists {
                for tag in Set(list.tags().filter { $0.first == "a" && $0.count > 1 }.map { $0[1] }) where tag.hasPrefix("\(Self.communityKind):") {
                    counts[tag, default: 0] += 1
                }
            }
            let created = await SyncService.shared.fetchEvents(["kinds": [Self.communityKind], "authors": follows, "limit": 100], timeout: 8)
            for community in Self.latestCommunities(created) {
                communityCache[community.id] = community
                counts[community.id, default: 0] += 1
            }
        }
        // Communities with recent posts, but only those run by people you trust.
        let posts = await SyncService.shared.fetchEvents(["kinds": [Self.communityPostKind], "#K": [String(Self.communityKind)], "limit": 300], timeout: 8)
        for post in posts {
            guard let coordinate = post.tags().first(where: { $0.first == "A" && $0.count > 1 })?[1],
                  let owner = Community.parse(coordinate: coordinate)?.pubkey, CommunitySafety.isTrusted(owner) else { continue }
            counts[coordinate, default: 0] += 1
        }
        let ranked = counts.sorted { $0.value > $1.value }.map(\.key).prefix(60)
        let muted = Set(Session.shared.mutedPubkeys)
        return await resolve(coordinates: Array(ranked)).filter { !muted.contains($0.pubkey) && CommunitySafety.allows($0.name, $0.summary, $0.rules) }
    }

    /// Public channels with recent activity and channels your follows joined.
    func discoverChannels() async -> [PublicChannel] {
        let relays = await Self.readRelays()
        var counts: [String: Int] = [:]
        let follows = Array(FollowService.shared.following.prefix(500))
        if !follows.isEmpty {
            let lists = await Self.fetch(["kinds": [Self.channelListKind], "authors": follows, "limit": 500], relays: relays, timeout: 8)
            for list in lists {
                for id in Set(list.tags().filter { $0.first == "e" && $0.count > 1 }.map { $0[1] }) { counts[id, default: 0] += 3 }
            }
        }
        // Recently active channels count only when a trusted person is talking in them.
        let recent = await Self.fetch(["kinds": [Self.channelMessageKind], "since": TimeFormat.now - 14 * 86400, "limit": 500], relays: relays, timeout: 8)
        for message in recent {
            guard let author = message.str("pubkey"), CommunitySafety.isTrusted(author), let root = Self.channelRoot(of: message) else { continue }
            counts[root, default: 0] += 1
        }
        let ranked = Array(counts.sorted { $0.value > $1.value }.map(\.key).prefix(60))
        let muted = Set(Session.shared.mutedPubkeys)
        return await resolve(channelIds: ranked).filter { !muted.contains($0.creator) && CommunitySafety.allows($0.name, $0.about) }
    }

    nonisolated static func channelRoot(of message: JSONObject) -> String? {
        let tags = message.tags().filter { $0.first == "e" && $0.count > 1 }
        return (tags.first { $0.count > 3 && $0[3] == "root" } ?? tags.first)?[1]
    }

    // MARK: NIP-29 groups

    func groupHistory(_ group: RelayGroup, limit: Int = 150) async -> [CommunityChatMessage] {
        let events = await Self.fetch(["kinds": [Self.groupMessageKind], "#h": [group.groupId], "limit": limit], relays: [group.relay], timeout: 8)
        return CommunityChatMessage.list(events, kind: Self.groupMessageKind)
    }

    func groupMemberCount(_ group: RelayGroup) async -> Int? {
        let events = await Self.fetch(["kinds": [Self.groupMembersKind], "#d": [group.groupId], "limit": 1], relays: [group.relay], timeout: 6)
        guard let latest = events.max(by: { $0.int("created_at") < $1.int("created_at") }) else { return nil }
        return Set(latest.tags().filter { $0.first == "p" && $0.count > 1 }.map { $0[1] }).count
    }

    func groupStream(_ group: RelayGroup) -> AsyncThrowingStream<CommunityChatMessage, Error> {
        let filter = JSON.string(["kinds": [Self.groupMessageKind], "#h": [group.groupId], "since": TimeFormat.now - 5] as JSONObject)
        let relay = group.relay
        return Self.messages(EventStream.make { sink in try await subscribeToEventsOnRelays(filterJson: filter, relayUrls: [relay], sink: sink) }, kind: Self.groupMessageKind)
    }

    func send(_ text: String, to group: RelayGroup) async throws -> CommunityChatMessage {
        let event = try Self.sign(kind: Self.groupMessageKind, content: text, tags: [["h", group.groupId]])
        try await Self.sendToRelays(event, relays: [group.relay])
        guard let message = JSON.object(event).flatMap({ CommunityChatMessage(json: $0, kind: Self.groupMessageKind) }) else { throw CoreError(L("liveSendFailed")) }
        return message
    }

    func join(_ group: RelayGroup) async throws {
        let event = try Self.sign(kind: Self.groupJoinKind, content: "", tags: [["h", group.groupId]])
        // A closed group may reject the request until an admin approves it; the group is still saved to your list.
        try? await Self.sendToRelays(event, relays: [group.relay])
        try await editList(kind: Self.groupListKind) { tags in
            tags.filter { !($0.first == "group" && $0.count > 2 && $0[1] == group.groupId && Self.normalizedRelay($0[2]) == group.relay) }
                + [["group", group.groupId, group.relay, group.name].filter { !$0.isEmpty }]
        }
        groupCache[group.id] = group
        groups.removeAll { $0.id == group.id }
        groups.append(group)
    }

    func leave(_ group: RelayGroup) async throws {
        if let event = try? Self.sign(kind: Self.groupLeaveKind, content: "", tags: [["h", group.groupId]]) {
            try? await Self.sendToRelays(event, relays: [group.relay])
        }
        try await editList(kind: Self.groupListKind) { tags in
            tags.filter { !($0.first == "group" && $0.count > 2 && $0[1] == group.groupId && Self.normalizedRelay($0[2]) == group.relay) }
        }
        groups.removeAll { $0.id == group.id }
    }

    // MARK: NIP-28 channels

    func channelHistory(_ channel: PublicChannel, limit: Int = 150) async -> [CommunityChatMessage] {
        let relays = await Self.readRelays(extra: channel.relays)
        let events = await Self.fetch(["kinds": [Self.channelMessageKind], "#e": [channel.id], "limit": limit], relays: relays, timeout: 8)
        return CommunityChatMessage.list(events.filter { Self.channelRoot(of: $0) == channel.id }, kind: Self.channelMessageKind)
    }

    func channelStream(_ channel: PublicChannel) -> AsyncThrowingStream<CommunityChatMessage, Error> {
        let filter = JSON.string(["kinds": [Self.channelMessageKind], "#e": [channel.id], "since": TimeFormat.now - 5] as JSONObject)
        return Self.messages(EventStream.make { sink in try await subscribeToEvents(filterJson: filter, sink: sink) }, kind: Self.channelMessageKind)
    }

    func send(_ text: String, to channel: PublicChannel) async throws -> CommunityChatMessage {
        let relay = channel.relays.first ?? ""
        let event = try Self.sign(kind: Self.channelMessageKind, content: text, tags: [["e", channel.id, relay, "root"]])
        let published = try await SyncService.shared.publish(event)
        if !channel.relays.isEmpty {
            let extra = channel.relays
            Task.detached { _ = try? await sendEventTo(eventJson: event, relayUrls: extra) }
        }
        guard let message = CommunityChatMessage(json: published, kind: Self.channelMessageKind) else { throw CoreError(L("liveSendFailed")) }
        return message
    }

    func join(_ channel: PublicChannel) async throws {
        try await editList(kind: Self.channelListKind) { tags in
            tags.filter { !($0.first == "e" && $0.count > 1 && $0[1] == channel.id) } + [["e", channel.id]]
        }
        channelCache[channel.id] = channel
        channels.removeAll { $0.id == channel.id }
        channels.append(channel)
    }

    func leave(_ channel: PublicChannel) async throws {
        try await editList(kind: Self.channelListKind) { tags in
            tags.filter { !($0.first == "e" && $0.count > 1 && $0[1] == channel.id) }
        }
        channels.removeAll { $0.id == channel.id }
    }

    // MARK: NIP-72 communities

    /// Top-level posts in the community, newest first.
    func posts(in community: Community, limit: Int = 60) async -> [Note] {
        let relays = await Self.readRelays(extra: community.relays)
        async let modern = Self.fetch(["kinds": [Self.communityPostKind], "#A": [community.coordinate], "limit": limit], relays: relays, timeout: 8)
        async let legacy = Self.fetch(["kinds": [1], "#a": [community.coordinate], "limit": limit], relays: relays, timeout: 8)
        let events = await (modern + legacy).filter { event in
            let tags = event.tags()
            if event.int("kind") == Self.communityPostKind {
                return tags.contains { $0.first == "k" && $0.count > 1 && $0[1] == String(Self.communityKind) }
            }
            return !tags.contains { $0.first == "e" }
        }
        guard !events.isEmpty else { return [] }
        _ = try? await dbSaveEvents(eventsJson: JSON.string(events))
        let ids = events.sorted { $0.int("created_at") > $1.int("created_at") }.compactMap { $0.str("id") }
        let session = Session.shared
        let notes = Note.list(try? await dbGetHydratedNotesByIds(eventIds: Array(ids.prefix(limit)), mutedPubkeys: session.mutedPubkeys, mutedWords: session.mutedWords, currentUserPubkeyHex: session.pubkey))
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        await ProfileCache.shared.load(Array(Set(notes.map(\.pubkey))))
        return notes.sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
    }

    func post(_ text: String, imageURLs: [String], to community: Community) async throws {
        let relay = community.relays.first ?? ""
        let body = ([text.trimmingCharacters(in: .whitespacesAndNewlines)] + imageURLs).filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !body.isEmpty else { throw CoreError(L("liveChatEmptyMessage")) }
        var tags: [[String]] = [
            ["A", community.coordinate, relay],
            ["a", community.coordinate, relay],
            ["K", String(Self.communityKind)],
            ["k", String(Self.communityKind)],
            ["P", community.pubkey],
            ["p", community.pubkey],
        ]
        tags += imageURLs.map { ["imeta", "url \($0)"] }
        let event = try Self.sign(kind: Self.communityPostKind, content: body, tags: tags)
        try await SyncService.shared.publish(event)
        if !community.relays.isEmpty {
            let extra = community.relays
            Task.detached { _ = try? await sendEventTo(eventJson: event, relayUrls: extra) }
        }
        DataBus.shared.feedChanged()
    }

    func join(_ community: Community) async throws {
        try await editList(kind: Self.communityListKind) { tags in
            tags.filter { !($0.first == "a" && $0.count > 1 && $0[1] == community.coordinate) } + [["a", community.coordinate]]
        }
        communityCache[community.id] = community
        communities.removeAll { $0.id == community.id }
        communities.append(community)
    }

    func leave(_ community: Community) async throws {
        try await editList(kind: Self.communityListKind) { tags in
            tags.filter { !($0.first == "a" && $0.count > 1 && $0[1] == community.coordinate) }
        }
        communities.removeAll { $0.id == community.id }
    }

    // MARK: Helpers

    nonisolated static func latestCommunities(_ events: [JSONObject]) -> [Community] {
        var latest: [String: Community] = [:]
        for community in events.compactMap(Community.init(json:)) where (latest[community.id]?.createdAt ?? -1) < community.createdAt {
            latest[community.id] = community
        }
        return Array(latest.values)
    }

    nonisolated static func channels(created: [JSONObject], metadata: [JSONObject]) -> [PublicChannel] {
        var channels: [String: PublicChannel] = [:]
        for channel in created.compactMap(PublicChannel.init(creation:)) { channels[channel.id] = channel }
        for meta in metadata {
            guard let root = channelRoot(of: meta), var channel = channels[root] else { continue }
            channel.apply(metadata: meta)
            channels[root] = channel
        }
        return Array(channels.values)
    }

    private static func sign(kind: Int, content: String, tags: [[String]]) throws -> String {
        let key = try Session.shared.requireSigner()
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return try createSignedEvent(kind: UInt16(kind), content: text, tags: tags, privateKeyHex: key)
    }

    private static func sendToRelays(_ event: String, relays: [String]) async throws {
        let raw = try await sendEventTo(eventJson: event, relayUrls: relays)
        let result = JSON.object(raw) ?? [:]
        guard !((result["success"] as? [Any]) ?? []).isEmpty else {
            let reason = ((result["failed"] as? JSONObject)?.values.compactMap { $0 as? String }.first).flatMap { $0.isEmpty ? nil : $0 }
            throw CoreError(reason ?? L("publishNoRelayAccepted"))
        }
    }

    private static func readRelays(extra: [String] = []) async -> [String] {
        let mine = (try? await getRelayList()) ?? RelayConfig.mainRelays
        var seen = Set<String>()
        return (mine + extra.prefix(4)).filter { $0.hasPrefix("wss://") && seen.insert($0).inserted }
    }

    nonisolated private static func fetch(_ filter: JSONObject, relays: [String], timeout: UInt32) async -> [JSONObject] {
        let raw = try? await fetchEventsFromRelays(filterJson: JSON.string(filter), relayUrls: relays, timeoutSecs: timeout)
        return JSON.array(raw)
    }

    nonisolated private static func messages(_ source: AsyncThrowingStream<String, Error>, kind: Int) -> AsyncThrowingStream<CommunityChatMessage, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await raw in source {
                        if let message = JSON.object(raw).flatMap({ CommunityChatMessage(json: $0, kind: kind) }) { continuation.yield(message) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
