import Foundation
import QiqstrCore

nonisolated struct LiveStream: Identifiable, Hashable, Sendable {
    enum Status: String, Sendable { case planned, live, ended }

    static let kind: UInt16 = 30311
    static let chatKind: UInt16 = 1311

    var id: String { coordinate }
    let eventId: String
    let pubkey: String
    let identifier: String
    let title: String
    let summary: String
    let image: String?
    let streamingURL: URL?
    let recordingURL: URL?
    let status: Status
    let starts: Int?
    let ends: Int?
    let participants: Int?
    let hosts: [String]
    let relays: [String]
    let hashtags: [String]
    let createdAt: Int
    let hasContentWarning: Bool

    var coordinate: String { "\(Self.kind):\(pubkey):\(identifier)" }
    var host: String { hosts.first ?? pubkey }
    @MainActor var naddr: String? { Nip19.naddr(kind: Self.kind, pubkey: pubkey, identifier: identifier) }
    var startedAt: Int { starts ?? createdAt }
    var playbackURL: URL? { isLive ? streamingURL : recordingURL ?? streamingURL }
    var canReplay: Bool { status == .ended && recordingURL != nil }

    var isLive: Bool {
        guard status == .live, streamingURL != nil else { return false }
        let now = Int(Date().timeIntervalSince1970)
        return now - createdAt < 2 * 3600 || now - startedAt < 8 * 3600
    }

    init?(json: JSONObject) {
        guard json.int("kind") == Int(Self.kind), let pubkey = json.str("pubkey"), let eventId = json.str("id") else { return nil }
        let tags = json.tags()
        func value(_ name: String) -> String? {
            tags.first { $0.count > 1 && $0[0] == name }.map { $0[1].trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        self.pubkey = pubkey
        self.eventId = eventId
        identifier = value("d") ?? ""
        title = value("title") ?? ""
        summary = value("summary") ?? ""
        image = value("image").flatMap { $0.hasPrefix("http") ? $0 : nil }
        streamingURL = Self.playableURL(tags.filter { $0.count > 1 && $0[0] == "streaming" }.map { $0[1] })
        recordingURL = Self.playableURL(tags.filter { $0.count > 1 && $0[0] == "recording" }.map { $0[1] })
        status = value("status").flatMap { Status(rawValue: $0.lowercased()) } ?? .ended
        starts = value("starts").flatMap(Int.init)
        ends = value("ends").flatMap(Int.init)
        participants = value("current_participants").flatMap(Int.init)
        let people = tags.filter { $0.count > 1 && $0[0] == "p" && $0[1].count == 64 }
        let hostTags = people.filter { $0.count > 3 && $0[3].lowercased() == "host" }.map { $0[1].lowercased() }
        hosts = hostTags.isEmpty ? [pubkey] : hostTags
        relays = tags.filter { $0.first == "relays" }.flatMap { $0.dropFirst() }.filter { $0.hasPrefix("wss://") }
        hashtags = tags.filter { $0.count > 1 && $0[0] == "t" }.map { $0[1].lowercased() }
        createdAt = json.int("created_at")
        hasContentWarning = tags.contains { $0.first == "content-warning" } || hashtags.contains("nsfw")
    }

    private static func playableURL(_ values: [String]) -> URL? {
        let urls = values.compactMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }.filter { $0.scheme == "https" || $0.scheme == "http" }
        return urls.first { $0.pathExtension.lowercased() == "m3u8" } ?? urls.first
    }
}

nonisolated struct LiveChatMessage: Identifiable, Hashable, Sendable {
    let id: String
    let pubkey: String
    let content: String
    let createdAt: Int

    init?(json: JSONObject) {
        guard json.int("kind") == Int(LiveStream.chatKind), let id = json.str("id"), let pubkey = json.str("pubkey") else { return nil }
        let content = (json["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        self.id = id
        self.pubkey = pubkey
        self.content = content
        createdAt = json.int("created_at")
    }
}

nonisolated struct LiveSnapshot: Sendable {
    var following: [LiveStream] = []
    var popular: [LiveStream] = []
    var recordings: [LiveStream] = []

    var live: [LiveStream] { following + popular }
    var isEmpty: Bool { following.isEmpty && popular.isEmpty && recordings.isEmpty }
}

@MainActor
@Observable
final class LiveService {
    static let shared = LiveService()
    static let ttl: TimeInterval = 90
    static let streamRelays = [
        "wss://relay.damus.io", "wss://nos.lol", "wss://relay.primal.net",
        "wss://relay.zap.stream", "wss://relay.snort.social", "wss://relay.fountain.fm", "wss://nostr.wine",
    ]

    private(set) var snapshot = LiveSnapshot()
    private(set) var isLoading = false
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored private var inflight: Task<LiveSnapshot, Never>?
    @ObservationIgnored private var streams: [String: LiveStream] = [:]

    func reset() {
        snapshot = LiveSnapshot()
        loadedAt = nil
        streams.removeAll()
    }

    func cached(_ coordinate: String) -> LiveStream? { streams[coordinate] }

    func load(force: Bool = false) async -> LiveSnapshot {
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < Self.ttl { return snapshot }
        if let inflight { return await inflight.value }
        let me = Session.shared.pubkey
        let follows = me == nil ? [] : await SyncService.shared.followingList(me ?? "")
        let muted = Set(Session.shared.mutedPubkeys)
        let relays = await Self.relays()
        let task = Task.detached { await Self.fetchSnapshot(relays: relays, follows: Set(follows), muted: muted) }
        inflight = task
        isLoading = true
        let result = await task.value
        inflight = nil
        isLoading = false
        if !result.isEmpty || snapshot.isEmpty {
            snapshot = result
            loadedAt = Date()
            for stream in result.live + result.recordings { streams[stream.coordinate] = stream }
            SyncService.shared.fetchMissingProfiles(Array(Set((result.live + result.recordings).map(\.host))))
        }
        return snapshot
    }

    func stream(coordinate: String) async -> LiveStream? {
        let parts = coordinate.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return streams[coordinate] }
        let filter: JSONObject = ["kinds": [Int(LiveStream.kind)], "authors": [parts[1]], "#d": [parts[2]], "limit": 5]
        let relays = await Self.relays(extra: streams[coordinate]?.relays ?? [])
        let events = await Self.fetch(filter, relays: relays, timeout: 6)
        if let latest = Self.latest(events.compactMap(LiveStream.init(json:))).first {
            streams[coordinate] = latest
            return latest
        }
        return streams[coordinate]
    }

    func chatHistory(_ stream: LiveStream, limit: Int = 150) async -> [LiveChatMessage] {
        let filter: JSONObject = ["kinds": [Int(LiveStream.chatKind)], "#a": [stream.coordinate], "limit": limit]
        let events = await Self.fetch(filter, relays: await Self.relays(extra: stream.relays), timeout: 6)
        return Self.messages(events)
    }

    func chatSince(_ stream: LiveStream, since: Int) async -> [LiveChatMessage] {
        let filter: JSONObject = ["kinds": [Int(LiveStream.chatKind)], "#a": [stream.coordinate], "since": since, "limit": 100]
        let events = await Self.fetch(filter, relays: await Self.relays(extra: stream.relays), timeout: 5)
        return Self.messages(events)
    }

    func chatStream(_ stream: LiveStream) -> AsyncThrowingStream<LiveChatMessage, Error> {
        let filter = JSON.string(["kinds": [Int(LiveStream.chatKind)], "#a": [stream.coordinate], "since": TimeFormat.now - 10] as JSONObject)
        let source = EventStream.make { sink in try await subscribeToEvents(filterJson: filter, sink: sink) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await raw in source {
                        if let message = JSON.object(raw).flatMap(LiveChatMessage.init(json:)) { continuation.yield(message) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func sendChat(_ text: String, to stream: LiveStream) async throws -> LiveChatMessage {
        let key = try Session.shared.requireSigner()
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw CoreError(L("liveChatEmptyMessage")) }
        let tags: [[String]] = [["a", stream.coordinate, stream.relays.first ?? "", "root"]]
        let json = try createSignedEvent(kind: LiveStream.chatKind, content: content, tags: tags, privateKeyHex: key)
        let event = try await SyncService.shared.publish(json)
        let extra = Array(Set(stream.relays + Self.streamRelays.prefix(3)))
        Task.detached { _ = try? await sendEventTo(eventJson: json, relayUrls: extra) }
        guard let message = LiveChatMessage(json: event) else { throw CoreError(L("liveSendFailed")) }
        return message
    }

    private static func relays(extra: [String] = []) async -> [String] {
        let mine = (try? await getRelayList()) ?? RelayConfig.mainRelays
        var seen = Set<String>()
        return (mine + streamRelays + extra.prefix(6)).filter { $0.hasPrefix("wss://") && seen.insert($0).inserted }
    }

    nonisolated private static func fetch(_ filter: JSONObject, relays: [String], timeout: UInt32) async -> [JSONObject] {
        let raw = try? await fetchEventsFromRelays(filterJson: JSON.string(filter), relayUrls: relays, timeoutSecs: timeout)
        return JSON.array(raw)
    }

    nonisolated private static func messages(_ events: [JSONObject]) -> [LiveChatMessage] {
        var seen = Set<String>()
        return events.compactMap(LiveChatMessage.init(json:))
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
    }

    nonisolated private static func latest(_ streams: [LiveStream]) -> [LiveStream] {
        var byCoordinate: [String: LiveStream] = [:]
        for stream in streams where byCoordinate[stream.coordinate].map({ $0.createdAt < stream.createdAt }) ?? true {
            byCoordinate[stream.coordinate] = stream
        }
        return byCoordinate.values.sorted { $0.createdAt > $1.createdAt }
    }

    nonisolated private static func fetchSnapshot(relays: [String], follows: Set<String>, muted: Set<String>) async -> LiveSnapshot {
        let now = TimeFormat.now
        let general: JSONObject = ["kinds": [Int(LiveStream.kind)], "since": now - 86400 * 3, "limit": 300]
        async let generalEvents = fetch(general, relays: relays, timeout: 8)
        async let followedEvents: [JSONObject] = follows.isEmpty ? [] : fetch(["kinds": [Int(LiveStream.kind)], "#p": Array(follows.prefix(500)), "since": now - 86400 * 7, "limit": 200], relays: relays, timeout: 8)
        let all = latest((await generalEvents + followedEvents).compactMap(LiveStream.init(json:)))
            .filter { !$0.hasContentWarning && !$0.hosts.contains(where: muted.contains) && !muted.contains($0.pubkey) }
        let live = all.filter(\.isLive)
        func followed(_ stream: LiveStream) -> Bool { follows.contains(stream.pubkey) || stream.hosts.contains(where: follows.contains) }
        func popularity(_ a: LiveStream, _ b: LiveStream) -> Bool {
            let pa = a.participants ?? 0, pb = b.participants ?? 0
            return pa == pb ? a.startedAt > b.startedAt : pa > pb
        }
        let recordings = all.filter { $0.canReplay && now - $0.startedAt < 86400 * 7 }
            .sorted { followed($0) != followed($1) ? followed($0) : $0.startedAt > $1.startedAt }
        return LiveSnapshot(
            following: live.filter(followed).sorted(by: popularity),
            popular: live.filter { !followed($0) }.sorted(by: popularity),
            recordings: Array(recordings.prefix(30))
        )
    }
}
