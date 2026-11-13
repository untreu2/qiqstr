import Foundation
import Observation
import QiqstrCore

nonisolated struct DMFileInfo: Hashable, Sendable, Codable {
    var url: String
    var mimeType: String
    var groupId: String
    var imeta: [String]
    var originalHash: String?
    var filename: String
    var size: Int?

    var isEncrypted: Bool { originalHash != nil && imeta.contains { $0.hasPrefix("n ") } }
    var isImage: Bool { mimeType.lowercased().hasPrefix("image/") }
    var isVideo: Bool { mimeType.lowercased().hasPrefix("video/") }
    var fileExtension: String { DMMediaCrypto.fileExtension(for: mimeType) }

    init(url: String, mimeType: String, groupId: String, imeta: [String], originalHash: String?, filename: String, size: Int?) {
        self.url = url; self.mimeType = mimeType; self.groupId = groupId; self.imeta = imeta
        self.originalHash = originalHash; self.filename = filename; self.size = size
    }

    init?(imeta values: [String], groupId: String) {
        var fields: [String: String] = [:]
        for value in values {
            guard let space = value.firstIndex(of: " ") else { continue }
            let key = String(value[..<space])
            if fields[key] == nil { fields[key] = String(value[value.index(after: space)...]) }
        }
        guard let url = fields["url"], !url.isEmpty, let mime = fields["m"] else { return nil }
        self.init(url: url, mimeType: mime, groupId: groupId, imeta: values, originalHash: fields["x"]?.lowercased(), filename: fields["filename"] ?? "", size: fields["size"].flatMap(Int.init))
    }

    var imetaWithoutURL: [String] { imeta.filter { !$0.hasPrefix("url ") } }
}

nonisolated enum DMDeliveryState: Hashable, Sendable, Codable {
    case sent, sending, failed
}

nonisolated enum DMPeerStatus: Hashable, Sendable {
    case unknown, checking, ready, unavailable
}

nonisolated struct DMMessage: Identifiable, Hashable, Sendable, Codable {
    var id: String
    var sender: String
    var peer: String
    var content: String
    var createdAt: Int
    var isMine: Bool
    var kind: Int
    var file: DMFileInfo?
    var state: DMDeliveryState = .sent

    var isFile: Bool { kind == 15 }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(createdAt)) }

    init(id: String, sender: String, peer: String, content: String, createdAt: Int, isMine: Bool, kind: Int, file: DMFileInfo? = nil, state: DMDeliveryState = .sent) {
        self.id = id; self.sender = sender; self.peer = peer; self.content = content
        self.createdAt = createdAt; self.isMine = isMine; self.kind = kind; self.file = file; self.state = state
    }

    static func fromMarmot(_ j: JSONObject, me: String, peer: String) -> [DMMessage] {
        guard let id = j.str("id"), let sender = j.str("pubkey"), let groupId = j.str("groupId"), j.int("kind") == 9 else { return [] }
        let state = (j["state"] as? String) ?? ""
        guard state != "deleted", state != "epoch_invalidated" else { return [] }
        let createdAt = j.int("createdAt")
        let isMine = sender == me
        let content = (j["content"] as? String) ?? ""
        let media = j.tags().filter { $0.first == "imeta" }.compactMap { DMFileInfo(imeta: Array($0.dropFirst()), groupId: groupId) }
        let hasText = !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var messages: [DMMessage] = []
        if hasText {
            messages.append(DMMessage(id: id, sender: sender, peer: peer, content: content, createdAt: createdAt, isMine: isMine, kind: 14))
        }
        for (index, file) in media.enumerated() {
            let messageId = !hasText && index == 0 ? id : "\(id):\(index)"
            messages.append(DMMessage(id: messageId, sender: sender, peer: peer, content: file.url, createdAt: createdAt, isMine: isMine, kind: 15, file: file))
        }
        return messages
    }
}

nonisolated struct DMConversation: Identifiable, Hashable, Sendable {
    var peer: String
    var lastMessage: DMMessage
    var isUnread: Bool
    var id: String { peer }
    var timestamp: Int { lastMessage.createdAt }
}

nonisolated struct DMPreparedFile: Hashable, Sendable {
    var url: String
    var mimeType: String
    var groupId: String
    var imeta: [String]
    var originalHash: String
    var filename: String
    var size: Int

    var tag: [String] { ["imeta", "url \(url)"] + imeta }
}

@MainActor
@Observable
final class DMService {
    static let shared = DMService()

    static let maxFileSize = 50 * 1024 * 1024
    private static let messageKind: UInt16 = 9
    private static let historyLimit = 500
    private static let historyPage = 200
    private static let unprocessedLimit = 300
    private static let keyPackageRefresh = 7 * 86_400
    private static let keyRotationAge: UInt64 = 30 * 86_400
    private static let giftWrapJitter = 3 * 86_400

    private(set) var conversations: [DMConversation] = []
    private(set) var messagesByPeer: [String: [DMMessage]] = [:]
    private(set) var following: Set<String> = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var isRefreshing = false
    private(set) var peerStatus: [String: DMPeerStatus] = [:]
    private(set) var deliveryRelays: [String: [String]] = [:]
    private(set) var accepted: Set<String> = []
    private(set) var historyComplete: Set<String> = []
    private(set) var loadingOlder: Set<String> = []
    var activePeer: String? {
        didSet { if let activePeer { markRead(activePeer) } }
    }
    var isListVisible = false {
        didSet { if isListVisible { markTabSeen() } }
    }

    @ObservationIgnored private let engine = MarmotEngine.shared
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var me: String?
    @ObservationIgnored private var privateKey: String?
    @ObservationIgnored private var groups: [String: MarmotGroup] = [:]
    @ObservationIgnored private var seenEvents: Set<String> = []
    @ObservationIgnored private var hiddenIds: Set<String> = []
    @ObservationIgnored private var clearedAt: [String: Int] = [:]
    @ObservationIgnored private var welcomeTask: Task<Void, Never>?
    @ObservationIgnored private var groupTask: Task<Void, Never>?
    @ObservationIgnored private var subscribedGroups: Set<String> = []
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var chatCreation: [String: Task<String, Error>] = [:]
    @ObservationIgnored private var keyPackages: [String: (event: String?, fetchedAt: Date)] = [:]
    @ObservationIgnored private var inboxRelayCache: [String: [String]] = [:]
    @ObservationIgnored private var remoteRelaysFetchedAt = Date.distantPast
    @ObservationIgnored private var readMarks: [String: Int] = [:]
    @ObservationIgnored private var readBaseline = 0
    @ObservationIgnored private var tabSeenAt = 0
    @ObservationIgnored private var verifiedMedia: Set<String> = []
    @ObservationIgnored private var mediaTasks: [String: Task<URL, Error>] = [:]
    @ObservationIgnored private var unprocessed: [String: String] = [:]
    @ObservationIgnored private var unprocessedOrder: [String] = []
    @ObservationIgnored private var historyLoaded: [String: Int] = [:]
    @ObservationIgnored private var outboxReady = false

    private var defaults: UserDefaults { .standard }

    func reset() {
        generation += 1
        welcomeTask?.cancel()
        welcomeTask = nil
        groupTask?.cancel()
        groupTask = nil
        subscribedGroups = []
        startTask?.cancel()
        startTask = nil
        chatCreation.values.forEach { $0.cancel() }
        chatCreation.removeAll()
        me = nil
        privateKey = nil
        groups.removeAll()
        seenEvents.removeAll()
        hiddenIds.removeAll()
        clearedAt.removeAll()
        keyPackages.removeAll()
        inboxRelayCache.removeAll()
        remoteRelaysFetchedAt = .distantPast
        readMarks.removeAll()
        readBaseline = 0
        tabSeenAt = 0
        verifiedMedia.removeAll()
        mediaTasks.values.forEach { $0.cancel() }
        mediaTasks.removeAll()
        deliveryRelays = [:]
        accepted = []
        historyComplete = []
        loadingOlder = []
        unprocessed = [:]
        unprocessedOrder = []
        historyLoaded = [:]
        outboxReady = false
        peerStatus = [:]
        conversations = []
        messagesByPeer = [:]
        following = []
        isLoading = false
        hasLoaded = false
        isRefreshing = false
        activePeer = nil
        isListVisible = false
        NotificationBadge.shared.hasUnreadMessages = false
    }

    func start() async {
        guard Session.shared.pubkey != nil else { return }
        guard let me = Session.shared.pubkey, let key = Session.shared.privateKey else {
            isLoading = false
            hasLoaded = true
            return
        }
        if self.me == me, let startTask {
            await startTask.value
            return
        }
        if self.me != nil, self.me != me { reset() }
        self.me = me
        privateKey = key
        let generation = self.generation
        loadReadState(me)
        hiddenIds = Set(defaults.stringArray(forKey: storeKey("marmot_hidden", me)) ?? [])
        clearedAt = (defaults.dictionary(forKey: storeKey("cleared", me)) as? [String: Int]) ?? [:]
        accepted = Set(defaults.stringArray(forKey: storeKey("accepted", me)) ?? [])
        isLoading = true
        let task = Task { await self.performStart(me, key: key, generation: generation) }
        startTask = task
        await task.value
    }

    private func performStart(_ me: String, key: String, generation: Int) async {
        async let followingLoaded: Void = reloadFollowing()
        let opened = (try? await engine.open(privateKey: key)) == me
        await followingLoaded
        guard generation == self.generation else { return }
        guard opened else {
            isLoading = false
            hasLoaded = true
            return
        }
        await reloadGroups(loadingAll: true, generation: generation)
        guard generation == self.generation else { return }
        loadOutbox(me)
        startRealtime(generation: generation)
        await fetchFromRelays(initial: true, generation: generation)
        guard generation == self.generation else { return }
        isLoading = false
        hasLoaded = true
        await publishKeyPackageIfNeeded(me, generation: generation)
        await retryPendingWelcomes(generation: generation)
        await rotateKeys(generation: generation)
    }

    func refresh() async {
        guard me != nil else { await start(); return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let generation = self.generation
        await fetchFromRelays(initial: false, generation: generation)
        guard generation == self.generation else { return }
        if welcomeTask == nil { startRealtime(generation: generation) }
        await retryPendingWelcomes(generation: generation)
    }

    func incomingMessages(since: Int) async -> [DMMessage] {
        if hasLoaded, me == Session.shared.pubkey { await refresh() } else { await start() }
        let blocked = Set(Session.shared.mutedPubkeys)
        return messagesByPeer.values.flatMap { $0 }.filter { !$0.isMine && $0.state == .sent && $0.createdAt > since && !blocked.contains($0.peer) && isKnown($0.peer) }
    }

    func deleteConversation(with peer: String) {
        guard let me else { return }
        let latest = messagesByPeer[peer]?.map(\.createdAt).max() ?? 0
        clearedAt[peer] = max(latest, Int(Date().timeIntervalSince1970), clearedAt[peer] ?? 0)
        defaults.set(clearedAt, forKey: storeKey("cleared", me))
        messagesByPeer[peer] = nil
        saveOutbox()
        rebuildConversations()
        DataBus.shared.dmChanged()
    }

    func accept(_ peer: String) {
        guard let me, accepted.insert(peer).inserted else { return }
        defaults.set(Array(accepted), forKey: storeKey("accepted", me))
        rebuildConversations()
        DataBus.shared.dmChanged()
    }

    func isRequest(_ peer: String) -> Bool {
        !isKnown(peer) && (messagesByPeer[peer]?.contains { !$0.isMine } ?? false)
    }

    func canLoadOlder(_ peer: String) -> Bool {
        guard let me else { return false }
        return groups.values.contains { group in
            group.peer(for: me) == peer && (historyLoaded[group.id] ?? 0) >= Self.historyLimit && !historyComplete.contains(group.id)
        }
    }

    func loadOlder(_ peer: String) async {
        guard let me, !loadingOlder.contains(peer) else { return }
        loadingOlder.insert(peer)
        defer { loadingOlder.remove(peer) }
        let generation = self.generation
        var loaded: [DMMessage] = []
        for group in groups.values where group.peer(for: me) == peer && !historyComplete.contains(group.id) {
            let offset = historyLoaded[group.id] ?? 0
            guard let raw = try? await engine.messages(groupId: group.id, limit: Self.historyPage, offset: offset) else { continue }
            guard generation == self.generation else { return }
            let page = JSON.array(raw)
            historyLoaded[group.id] = offset + page.count
            if page.count < Self.historyPage { historyComplete.insert(group.id) }
            loaded += page.reversed().flatMap { DMMessage.fromMarmot($0, me: me, peer: peer) }
        }
        apply(loaded.sorted { $0.createdAt < $1.createdAt })
    }

    func mutesChanged() {
        guard me != nil else { return }
        rebuildConversations()
        DataBus.shared.dmChanged()
    }

    func reloadFollowing() async {
        guard let me = me ?? Session.shared.pubkey else { return }
        let list = Set(await SyncService.shared.followingList(me))
        if list != following { following = list }
    }

    func messages(with peer: String) -> [DMMessage] { messagesByPeer[peer] ?? [] }

    func conversation(with peer: String) -> DMConversation? { conversations.first { $0.peer == peer } }

    func isFollowing(_ pubkey: String) -> Bool { following.contains(pubkey) }

    func isKnown(_ peer: String) -> Bool {
        following.contains(peer) || accepted.contains(peer) || (messagesByPeer[peer]?.contains(where: \.isMine) ?? false)
    }

    var unreadCount: Int { conversations.filter(\.isUnread).count }

    var currentPubkey: String? { me }

    func errorMessage(_ error: Error) -> String { coreErrorMessage(error) }

    func status(for peer: String) -> DMPeerStatus {
        if preferredGroup(for: peer) != nil { return .ready }
        return peerStatus[peer] ?? .unknown
    }

    func chatRelays(for peer: String) -> [String] {
        var relays: [String] = []
        for group in groups.values where group.peer(for: me ?? "") == peer {
            for relay in group.relays where !relays.contains(relay) { relays.append(relay) }
        }
        return relays
    }

    func checkPeer(_ peer: String) async {
        guard preferredGroup(for: peer) == nil, peerStatus[peer] != .checking else { return }
        peerStatus[peer] = .checking
        let found = await keyPackage(for: peer, fresh: false) != nil
        guard me != nil else { return }
        peerStatus[peer] = preferredGroup(for: peer) != nil || found ? .ready : .unavailable
    }

    private func storeKey(_ name: String, _ me: String) -> String { "dm_\(name)_\(me)" }

    private func reloadGroups(loadingAll: Bool, generation: Int) async {
        guard let me, let list = try? await engine.groups() else { return }
        guard generation == self.generation else { return }
        var active: [String: MarmotGroup] = [:]
        for group in list where group.isActive && group.peer(for: me) != nil { active[group.id] = group }
        let previous = Set(groups.keys)
        groups = active
        let targets = loadingAll ? Array(active.keys) : active.keys.filter { !previous.contains($0) }
        var loaded: [DMMessage] = []
        for id in targets {
            guard let group = active[id], let peer = group.peer(for: me),
                  let raw = try? await engine.messages(groupId: id, limit: Self.historyLimit) else { continue }
            let page = JSON.array(raw)
            historyLoaded[id] = page.count
            if page.count < Self.historyLimit { historyComplete.insert(id) } else { historyComplete.remove(id) }
            loaded += page.reversed().flatMap { DMMessage.fromMarmot($0, me: me, peer: peer) }
        }
        guard generation == self.generation else { return }
        let ordered = loaded.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.createdAt != rhs.element.createdAt { return lhs.element.createdAt < rhs.element.createdAt }
                if lhs.element.isMine != rhs.element.isMine { return lhs.element.isMine }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        apply(ordered)
        for group in active.values {
            if let peer = group.peer(for: me), peerStatus[peer] != .ready { peerStatus[peer] = .ready }
        }
        if Set(active.values.map(\.nostrGroupId)) != subscribedGroups { startGroupRealtime(generation: generation) }
    }

    private func fetchFromRelays(initial: Bool, generation: Int) async {
        guard let me else { return }
        let cursor = defaults.integer(forKey: storeKey("marmot_cursor", me))
        let startedAt = TimeFormat.now
        let reachable = ((try? await getConnectedRelayCount()) ?? 0) > 0
        var wrapFilter: JSONObject = ["kinds": [1059], "#p": [me], "limit": initial ? 500 : 200]
        if cursor > 0 { wrapFilter["since"] = cursor - Self.giftWrapJitter }
        let wraps = Self.parseArray((try? await fetchEvents(filterJson: Self.jsonString(wrapFilter), timeoutSecs: initial ? 10 : 8)) ?? "[]")
        guard generation == self.generation else { return }
        await ingest(wraps.map { Self.jsonString($0) }, generation: generation)
        guard generation == self.generation else { return }
        await fetchGroupMessages(since: cursor > 0 ? cursor - 600 : nil, generation: generation)
        guard generation == self.generation, reachable else { return }
        defaults.set(startedAt, forKey: storeKey("marmot_cursor", me))
    }

    private func fetchGroupMessages(since: Int?, generation: Int) async {
        let list = Array(groups.values)
        guard !list.isEmpty else { return }
        var filter: JSONObject = ["kinds": [445], "#h": list.map(\.nostrGroupId), "limit": 1000]
        if let since { filter["since"] = since }
        let json = Self.jsonString(filter)
        let main = Set(RelayConfig.mainRelays)
        let remote = Array(Set(list.flatMap(\.relays)).subtracting(main))
        let fetchRemote = !remote.isEmpty && Date().timeIntervalSince(remoteRelaysFetchedAt) > 45
        if fetchRemote { remoteRelaysFetchedAt = Date() }
        async let pooled = fetchEvents(filterJson: json, timeoutSecs: 8)
        async let extra = fetchRemote ? fetchEventsFromRelays(filterJson: json, relayUrls: remote, timeoutSecs: 8) : "[]"
        let merged = Self.parseArray((try? await pooled) ?? "[]") + Self.parseArray((try? await extra) ?? "[]")
        guard generation == self.generation else { return }
        await ingest(merged.map { Self.jsonString($0) }, generation: generation)
    }

    private func startRealtime(generation: Int) {
        welcomeTask?.cancel()
        welcomeTask = Task { [weak self] in
            guard let me = self?.me else { return }
            let filter = Self.jsonString(["kinds": [1059], "#p": [me], "since": TimeFormat.now - Self.giftWrapJitter])
            await self?.listen(filter: filter, generation: generation)
        }
        startGroupRealtime(generation: generation)
    }

    private func startGroupRealtime(generation: Int) {
        groupTask?.cancel()
        let ids = Set(groups.values.map(\.nostrGroupId))
        subscribedGroups = ids
        guard !ids.isEmpty else { groupTask = nil; return }
        let filter = Self.jsonString(["kinds": [445], "#h": Array(ids), "since": TimeFormat.now - 60])
        groupTask = Task { [weak self] in await self?.listen(filter: filter, generation: generation) }
    }

    private func listen(filter: String, generation: Int) async {
        while !Task.isCancelled, generation == self.generation {
            let stream = EventStream.make { sink in try await subscribeToEvents(filterJson: filter, sink: sink) }
            do {
                for try await raw in stream {
                    guard generation == self.generation, !Task.isCancelled else { break }
                    await ingest([raw], generation: generation)
                }
            } catch {}
            guard !Task.isCancelled, generation == self.generation else { break }
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func ingest(_ raws: [String], generation: Int, depth: Int = 0) async {
        if seenEvents.count > 20_000 { seenEvents.removeAll() }
        var groupEvents: [String: String] = [:]
        let fresh = raws.filter { raw in
            guard let event = JSON.object(raw), let id = event.str("id"), !seenEvents.contains(id) else { return false }
            seenEvents.insert(id)
            if event.int("kind") == 445 { groupEvents[id] = raw }
            return true
        }
        guard !fresh.isEmpty else { return }
        let outcomes = await engine.process(fresh)
        guard generation == self.generation, let me else { return }
        var groupsChanged = false
        var joined = false
        var incoming: [DMMessage] = []
        var retry: [String] = []
        for outcome in outcomes {
            if let raw = groupEvents[outcome.eventId] {
                if outcome.type == "ignored" || outcome.type == "error" { holdUnprocessed(outcome.eventId, raw) } else { unprocessed[outcome.eventId] = nil }
            }
            switch outcome.type {
            case "message":
                guard let groupId = outcome.groupId, let group = groups[groupId], let peer = group.peer(for: me) else {
                    groupsChanged = true
                    continue
                }
                if let message = JSON.object(outcome.messageJSON) { incoming += DMMessage.fromMarmot(message, me: me, peer: peer) }
            case "welcome":
                groupsChanged = true
                if outcome.isNewWelcome { joined = true }
            case "proposal":
                groupsChanged = true
                if let groupId = outcome.groupId, let commit = outcome.evolutionEvent {
                    let relays = relays(forGroup: groupId)
                    await engine.finishCommit(groupId: groupId, eventJSON: commit) { event in
                        !(await Self.publish(event, relays: relays) ?? []).isEmpty
                    }
                }
            case "commit":
                groupsChanged = true
                retry += outcome.retry
            default:
                break
            }
        }
        apply(incoming)
        if groupsChanged { await reloadGroups(loadingAll: false, generation: generation) }
        if !retry.isEmpty, depth < 4 { await reprocess(Set(retry), generation: generation, depth: depth + 1) }
        if joined {
            defaults.removeObject(forKey: storeKey("marmot_kp_at", me))
            await fetchGroupMessages(since: nil, generation: generation)
            await rotateKeys(generation: generation)
            await publishKeyPackageIfNeeded(me, generation: generation)
        }
    }

    private func holdUnprocessed(_ id: String, _ raw: String) {
        guard unprocessed[id] == nil else { return }
        unprocessed[id] = raw
        unprocessedOrder.append(id)
        while unprocessedOrder.count > Self.unprocessedLimit { unprocessed[unprocessedOrder.removeFirst()] = nil }
    }

    private func reprocess(_ ids: Set<String>, generation: Int, depth: Int) async {
        var raws = ids.compactMap { unprocessed[$0] }
        let missing = Array(ids.subtracting(unprocessed.keys))
        if !missing.isEmpty {
            let filter = Self.jsonString(["ids": missing, "limit": missing.count])
            let relays = Array(Set(groups.values.flatMap(\.relays)))
            async let pooled = fetchEvents(filterJson: filter, timeoutSecs: 6)
            async let extra = relays.isEmpty ? "[]" : fetchEventsFromRelays(filterJson: filter, relayUrls: relays, timeoutSecs: 6)
            let fetched = Self.parseArray((try? await pooled) ?? "[]") + Self.parseArray((try? await extra) ?? "[]")
            raws += fetched.filter { ($0["id"] as? String).map(ids.contains) ?? false }.map { Self.jsonString($0) }
        }
        guard generation == self.generation, !raws.isEmpty else { return }
        for id in ids {
            seenEvents.remove(id)
            unprocessed[id] = nil
        }
        unprocessedOrder.removeAll { ids.contains($0) }
        await ingest(raws, generation: generation, depth: depth)
    }

    private func apply(_ messages: [DMMessage]) {
        let visible = messages.filter { !hiddenIds.contains($0.id) }
        guard !visible.isEmpty else { return }
        var changedPeers: Set<String> = []
        for message in visible where insert(message) { changedPeers.insert(message.peer) }
        guard !changedPeers.isEmpty else { return }
        if let activePeer, changedPeers.contains(activePeer) { markReadSilently(activePeer) }
        rebuildConversations()
        let missing = changedPeers.filter { ProfileCache.shared.profile($0) == nil }
        if !missing.isEmpty { Task { await ProfileCache.shared.load(Array(missing)) } }
        DataBus.shared.dmChanged()
    }

    @discardableResult
    private func insert(_ message: DMMessage) -> Bool {
        if let cutoff = clearedAt[message.peer], message.createdAt <= cutoff { return false }
        var list = messagesByPeer[message.peer] ?? []
        if let index = list.firstIndex(where: { $0.id == message.id }) {
            guard list[index].state != .sent else { return false }
            list[index] = message
            messagesByPeer[message.peer] = list
            return true
        }
        let index = list.lastIndex { $0.createdAt <= message.createdAt }.map { $0 + 1 } ?? 0
        list.insert(message, at: index)
        messagesByPeer[message.peer] = list
        return true
    }

    private func preferredGroup(for peer: String) -> MarmotGroup? {
        guard let me else { return nil }
        return groups.values
            .filter { $0.peer(for: me) == peer }
            .max { ($0.lastMessageAt, $0.id) < ($1.lastMessageAt, $1.id) }
    }

    private func rebuildConversations() {
        let blocked = Set(Session.shared.mutedPubkeys)
        conversations = messagesByPeer.compactMap { peer, list in
            guard !blocked.contains(peer), let last = list.last(where: { $0.state == .sent }) ?? list.last else { return nil }
            return DMConversation(peer: peer, lastMessage: last, isUnread: isUnread(peer: peer, list: list))
        }
        .sorted { $0.timestamp > $1.timestamp }
        updateBadge()
    }

    private func lastIncoming(_ list: [DMMessage]) -> DMMessage? { list.last { !$0.isMine } }

    private func isUnread(peer: String, list: [DMMessage]) -> Bool {
        guard let incoming = lastIncoming(list) else { return false }
        if let last = list.last, last.isMine, last.createdAt >= incoming.createdAt, last.state == .sent { return false }
        return incoming.createdAt > max(readMarks[peer] ?? 0, readBaseline)
    }

    private func updateBadge() {
        let unseen = conversations.contains { conversation in
            guard conversation.isUnread, isKnown(conversation.peer), let incoming = lastIncoming(messagesByPeer[conversation.peer] ?? []) else { return false }
            return incoming.createdAt > tabSeenAt
        }
        if isListVisible, unseen { markTabSeen(); return }
        NotificationBadge.shared.hasUnreadMessages = unseen
    }

    private func loadReadState(_ me: String) {
        readMarks = (defaults.dictionary(forKey: storeKey("read_marks", me)) as? [String: Int]) ?? [:]
        let baseline = defaults.integer(forKey: storeKey("read_baseline", me))
        if baseline > 0 {
            readBaseline = baseline
        } else {
            readBaseline = TimeFormat.now
            defaults.set(readBaseline, forKey: storeKey("read_baseline", me))
        }
        let seen = defaults.integer(forKey: storeKey("tab_seen", me))
        tabSeenAt = seen > 0 ? seen : readBaseline
    }

    private func persistReadMarks() {
        guard let me else { return }
        defaults.set(readMarks, forKey: storeKey("read_marks", me))
    }

    private func markReadSilently(_ peer: String) {
        let latest = messagesByPeer[peer]?.last?.createdAt ?? 0
        readMarks[peer] = max(latest, TimeFormat.now, readMarks[peer] ?? 0)
        persistReadMarks()
    }

    func markRead(_ peer: String) {
        markReadSilently(peer)
        rebuildConversations()
    }

    func markUnread(_ peer: String) {
        guard let incoming = lastIncoming(messagesByPeer[peer] ?? []) else { return }
        readMarks[peer] = incoming.createdAt - 1
        persistReadMarks()
        rebuildConversations()
    }

    func markAllRead() {
        for peer in messagesByPeer.keys { readMarks[peer] = max(messagesByPeer[peer]?.last?.createdAt ?? 0, TimeFormat.now) }
        persistReadMarks()
        rebuildConversations()
    }

    func markTabSeen() {
        guard let me else { return }
        tabSeenAt = TimeFormat.now
        defaults.set(tabSeenAt, forKey: storeKey("tab_seen", me))
        NotificationBadge.shared.hasUnreadMessages = false
    }

    func send(_ text: String, to peer: String) async throws {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard let me else { throw CoreError(L("dmNotSignedIn")) }
        let pending = DMMessage(id: "pending-\(UUID().uuidString)", sender: me, peer: peer, content: content, createdAt: TimeFormat.now, isMine: true, kind: 14, state: .sending)
        addPending(pending)
        do {
            let groupId = try await ensureChat(with: peer)
            let sent = try await engine.send(groupId: groupId, kind: Self.messageKind, content: content, tags: [])
            try await deliver(sent, groupId: groupId, peer: peer, replacing: pending.id)
        } catch {
            markFailed(pending.id, peer: peer)
            throw error
        }
    }

    func sendFile(_ data: Data, mimeType: String, to peer: String) async throws {
        let prepared = try await prepareFile(data, mimeType: mimeType, for: peer)
        try await sendPrepared(prepared, to: peer)
    }

    func prepareFile(_ data: Data, mimeType: String, for peer: String) async throws -> DMPreparedFile {
        guard data.count <= Self.maxFileSize else { throw CoreError(L("fileTooLarge")) }
        guard let key = privateKey else { throw CoreError(L("dmNotSignedIn")) }
        let groupId = try await ensureChat(with: peer)
        let ext = DMMediaCrypto.fileExtension(for: mimeType)
        let filename = "\(UUID().uuidString.prefix(8).lowercased()).\(ext)"
        let encrypted: MarmotEncryptedMedia
        do {
            encrypted = try await engine.encryptMedia(groupId: groupId, data: data, mimeType: mimeType, filename: filename)
        } catch {
            throw CoreError("\(L("encryptionFailed")): \(coreErrorMessage(error))")
        }
        defer { try? FileManager.default.removeItem(at: encrypted.fileURL) }
        let body = try Data(contentsOf: encrypted.fileURL)
        if let url = DMMediaCrypto.cacheURL(hash: encrypted.originalHash, ext: ext) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
            verifiedMedia.insert(url.lastPathComponent)
        }
        let url: String
        do {
            url = try await DMMediaCrypto.upload(body, sha256: encrypted.encryptedHash, privateKey: key, servers: RelayConfig.encryptedMediaServers)
        } catch {
            throw CoreError(L("failedToUploadEncryptedMedia"))
        }
        return DMPreparedFile(url: url, mimeType: encrypted.mimeType, groupId: groupId, imeta: encrypted.imeta, originalHash: encrypted.originalHash, filename: encrypted.filename, size: encrypted.size)
    }

    func sendPrepared(_ file: DMPreparedFile, to peer: String) async throws {
        guard let me else { throw CoreError(L("dmNotSignedIn")) }
        let tag = file.tag
        let info = DMFileInfo(url: file.url, mimeType: file.mimeType, groupId: file.groupId, imeta: Array(tag.dropFirst()), originalHash: file.originalHash, filename: file.filename, size: file.size)
        let pending = DMMessage(id: "pending-\(UUID().uuidString)", sender: me, peer: peer, content: file.url, createdAt: TimeFormat.now, isMine: true, kind: 15, file: info, state: .sending)
        addPending(pending)
        do {
            guard groups[file.groupId] != nil else { throw CoreError(L("dmSendFailed")) }
            let sent = try await engine.send(groupId: file.groupId, kind: Self.messageKind, content: "", tags: [tag])
            try await deliver(sent, groupId: file.groupId, peer: peer, replacing: pending.id)
        } catch {
            markFailed(pending.id, peer: peer)
            throw error
        }
    }

    func retry(_ message: DMMessage) async throws {
        discard(message)
        if message.isFile, let file = message.file, let hash = file.originalHash {
            let prepared = DMPreparedFile(url: file.url, mimeType: file.mimeType, groupId: file.groupId, imeta: file.imetaWithoutURL, originalHash: hash, filename: file.filename, size: file.size ?? 0)
            try await sendPrepared(prepared, to: message.peer)
        } else {
            try await send(message.content, to: message.peer)
        }
    }

    func discard(_ message: DMMessage) {
        guard message.state != .sent else { return }
        messagesByPeer[message.peer]?.removeAll { $0.id == message.id }
        if messagesByPeer[message.peer]?.isEmpty == true { messagesByPeer[message.peer] = nil }
        saveOutbox()
        rebuildConversations()
    }

    private func addPending(_ message: DMMessage) {
        insert(message)
        saveOutbox()
        rebuildConversations()
    }

    private func markFailed(_ id: String, peer: String) {
        guard let index = messagesByPeer[peer]?.firstIndex(where: { $0.id == id }) else { return }
        messagesByPeer[peer]?[index].state = .failed
        saveOutbox()
        rebuildConversations()
    }

    private func outboxURL(_ me: String) -> URL {
        MarmotEngine.storageDirectory
            .appendingPathComponent(me.lowercased(), isDirectory: true)
            .appendingPathComponent("outbox.json")
    }

    private func loadOutbox(_ me: String) {
        let url = outboxURL(me)
        guard FileManager.default.fileExists(atPath: url.path) else {
            outboxReady = true
            return
        }
        guard let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([DMMessage].self, from: data) else { return }
        outboxReady = true
        for var message in saved where message.isMine && message.sender == me && !wasDelivered(message) {
            message.state = .failed
            insert(message)
        }
        saveOutbox()
        rebuildConversations()
    }

    private func wasDelivered(_ message: DMMessage) -> Bool {
        (messagesByPeer[message.peer] ?? []).contains { sent in
            sent.isMine && sent.state == .sent && sent.kind == message.kind && sent.content == message.content && abs(sent.createdAt - message.createdAt) < 300
        }
    }

    private func saveOutbox() {
        guard let me, outboxReady else { return }
        let unsent = messagesByPeer.values.flatMap { $0 }.filter { $0.isMine && $0.state != .sent }.sorted { $0.createdAt < $1.createdAt }
        let url = outboxURL(me)
        guard !unsent.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Array(unsent.suffix(100))) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func hide(_ ids: [String]) {
        guard let me, !ids.isEmpty else { return }
        hiddenIds.formUnion(ids)
        defaults.set(Array(hiddenIds.suffix(500)), forKey: storeKey("marmot_hidden", me))
    }

    private func deliver(_ sent: MarmotSent, groupId: String, peer: String, replacing pendingId: String) async throws {
        guard let me else { throw CoreError(L("dmNotSignedIn")) }
        let generation = self.generation
        let messages = JSON.object(sent.messageJSON).map { DMMessage.fromMarmot($0, me: me, peer: peer) } ?? []
        if let id = JSON.object(sent.eventJSON)?.str("id") { seenEvents.insert(id) }
        let accepted = await Self.publish(sent.eventJSON, relays: relays(forGroup: groupId))
        guard generation == self.generation else { return }
        guard let accepted, !accepted.isEmpty else {
            hide(messages.map(\.id))
            throw CoreError(L("dmSendFailed"))
        }
        let visible = messages.filter { !hiddenIds.contains($0.id) }
        if var list = messagesByPeer[peer], let index = list.firstIndex(where: { $0.id == pendingId }) {
            if visible.isEmpty {
                list[index].state = .sent
            } else {
                list.removeAll { message in visible.contains { $0.id == message.id } }
                let slot = list.firstIndex(where: { $0.id == pendingId }) ?? index
                list.replaceSubrange(slot...slot, with: visible)
            }
            messagesByPeer[peer] = list
        }
        for message in messages { deliveryRelays[message.id] = accepted.sorted() }
        if let index = groups.index(forKey: groupId) { groups.values[index].lastMessageAt = TimeFormat.now }
        apply(messages)
        markReadSilently(peer)
        saveOutbox()
        rebuildConversations()
    }

    private func relays(forGroup groupId: String) -> [String] {
        let relays = groups[groupId]?.relays ?? []
        return relays.isEmpty ? RelayConfig.mainRelays : relays
    }

    private func ensureChat(with peer: String) async throws -> String {
        if let group = preferredGroup(for: peer) { return group.id }
        if let task = chatCreation[peer] { return try await task.value }
        let task = Task { try await self.createChat(with: peer) }
        chatCreation[peer] = task
        defer { chatCreation[peer] = nil }
        return try await task.value
    }

    private func createChat(with peer: String) async throws -> String {
        guard me != nil else { throw CoreError(L("dmNotSignedIn")) }
        let generation = self.generation
        guard let keyPackage = await keyPackage(for: peer, fresh: true) else {
            peerStatus[peer] = .unavailable
            let name = ProfileCache.shared.profile(peer)?.bestName ?? Profile.shortNpub(peer)
            throw CoreError(L("dmPeerNotOnMarmot", ["name": name]))
        }
        guard generation == self.generation, !Task.isCancelled else { throw CancellationError() }
        let chat = try await engine.createChat(keyPackage: keyPackage, relays: RelayConfig.mainRelays)
        guard generation == self.generation, let group = MarmotGroup(json: JSON.object(chat.groupJSON) ?? [:]) else {
            throw CoreError(L("dmSendFailed"))
        }
        groups[group.id] = group
        peerStatus[peer] = .ready
        startGroupRealtime(generation: generation)
        let inbox = await inboxRelays(for: peer)
        var targets = chat.welcomeRelays
        for relay in inbox + RelayConfig.discoveryRelays where !targets.contains(relay) { targets.append(relay) }
        for welcome in chat.welcomes {
            let accepted = await Self.publish(welcome, relays: targets) ?? []
            if accepted.isEmpty { savePendingWelcome(welcome, relays: targets) }
        }
        return group.id
    }

    private func keyPackage(for peer: String, fresh: Bool) async -> String? {
        if let cached = keyPackages[peer] {
            let age = Date().timeIntervalSince(cached.fetchedAt)
            if cached.event != nil, !fresh || age < 600 { return cached.event }
            if cached.event == nil, age < 60 { return nil }
        }
        let listFilter = Self.jsonString(["kinds": [10051], "authors": [peer], "limit": 1])
        async let pooledList = fetchEvents(filterJson: listFilter, timeoutSecs: 5)
        async let discoveredList = fetchEventsFromRelays(filterJson: listFilter, relayUrls: RelayConfig.discoveryRelays, timeoutSecs: 5)
        let lists = Self.parseArray((try? await pooledList) ?? "[]") + Self.parseArray((try? await discoveredList) ?? "[]")
        var relays = Self.relayURLs(from: lists)
        for relay in RelayConfig.discoveryRelays where !relays.contains(relay) { relays.append(relay) }
        let packageRelays = relays
        let filter = Self.jsonString(["kinds": [30443, 443], "authors": [peer], "limit": 20])
        async let pooled = fetchEvents(filterJson: filter, timeoutSecs: 6)
        async let remote = fetchEventsFromRelays(filterJson: filter, relayUrls: packageRelays, timeoutSecs: 6)
        let events = Self.parseArray((try? await pooled) ?? "[]") + Self.parseArray((try? await remote) ?? "[]")
        let picked = events.isEmpty ? nil : (try? await engine.pickKeyPackage(eventsJSON: Self.jsonString(events), owner: peer)) ?? nil
        keyPackages[peer] = (picked, Date())
        return picked
    }

    private func inboxRelays(for pubkey: String) async -> [String] {
        if let cached = inboxRelayCache[pubkey] { return cached }
        let filter = Self.jsonString(["kinds": [10050], "authors": [pubkey], "limit": 1])
        var relays = Self.relayURLs(from: Self.parseArray((try? await dbQueryEvents(filterJson: filter, limit: 1)) ?? "[]"))
        if relays.isEmpty { relays = Self.relayURLs(from: Self.parseArray((try? await fetchEvents(filterJson: filter, timeoutSecs: 5)) ?? "[]")) }
        inboxRelayCache[pubkey] = relays
        return relays
    }

    private func publishKeyPackageIfNeeded(_ me: String, generation: Int) async {
        let stampKey = storeKey("marmot_kp_at", me)
        guard TimeFormat.now - defaults.integer(forKey: stampKey) > Self.keyPackageRefresh else { return }
        let listFilter = Self.jsonString(["kinds": [10051], "authors": [me], "limit": 1])
        let existing = Self.relayURLs(from: Self.parseArray((try? await fetchEvents(filterJson: listFilter, timeoutSecs: 5)) ?? "[]"))
        let main = RelayConfig.mainRelays
        let relays = existing.isEmpty ? main : existing
        var targets = relays
        for relay in main + RelayConfig.discoveryRelays where !targets.contains(relay) { targets.append(relay) }
        guard generation == self.generation else { return }
        if existing.isEmpty, let list = try? await engine.keyPackageRelaysEvent(relays: relays) {
            _ = await Self.publish(list, relays: targets)
        }
        guard generation == self.generation, let event = try? await engine.keyPackageEvent(relays: relays) else { return }
        let accepted = await Self.publish(event, relays: targets) ?? []
        guard generation == self.generation, !accepted.isEmpty else { return }
        defaults.set(TimeFormat.now, forKey: stampKey)
    }

    private func rotateKeys(generation: Int) async {
        guard generation == self.generation else { return }
        let targets = Dictionary(uniqueKeysWithValues: groups.keys.map { ($0, relays(forGroup: $0)) })
        let fallback = RelayConfig.mainRelays
        await engine.rotateKeys(olderThan: Self.keyRotationAge) { groupId, commit in
            let accepted = await Self.publish(commit, relays: targets[groupId] ?? fallback) ?? []
            return !accepted.isEmpty
        }
        guard generation == self.generation else { return }
        await reloadGroups(loadingAll: false, generation: generation)
    }

    private func savePendingWelcome(_ event: String, relays: [String]) {
        guard let me else { return }
        let key = storeKey("marmot_pending_welcomes", me)
        var list = (defaults.array(forKey: key) as? [[String: Any]]) ?? []
        list.append(["event": event, "relays": relays])
        defaults.set(Array(list.suffix(50)), forKey: key)
    }

    private func retryPendingWelcomes(generation: Int) async {
        guard let me else { return }
        let key = storeKey("marmot_pending_welcomes", me)
        let list = (defaults.array(forKey: key) as? [[String: Any]]) ?? []
        guard !list.isEmpty else { return }
        var remaining: [[String: Any]] = []
        for item in list {
            guard let event = item["event"] as? String else { continue }
            let relays = (item["relays"] as? [String]) ?? RelayConfig.mainRelays
            let accepted = await Self.publish(event, relays: relays) ?? []
            if accepted.isEmpty { remaining.append(item) }
        }
        guard generation == self.generation else { return }
        defaults.set(remaining, forKey: key)
    }

    private nonisolated static func publish(_ json: String, relays: [String]) async -> [String]? {
        if !relays.isEmpty, let raw = try? await sendEventTo(eventJson: json, relayUrls: relays) {
            let accepted = acceptedRelays(raw)
            if !accepted.isEmpty { return accepted }
        }
        guard let raw = try? await sendEvent(eventJson: json) else { return nil }
        return acceptedRelays(raw)
    }

    private nonisolated static func acceptedRelays(_ raw: String) -> [String] {
        (parseObject(raw)?["success"] as? [String]) ?? []
    }

    func decryptedFileURL(for message: DMMessage) async throws -> URL {
        guard let file = message.file, let hash = file.originalHash else { throw CoreError(L("failedToDecryptMedia")) }
        guard let target = DMMediaCrypto.cacheURL(hash: hash, ext: file.fileExtension) else { throw CoreError(L("failedToDecryptMedia")) }
        let name = target.lastPathComponent
        if verifiedMedia.contains(name), FileManager.default.fileExists(atPath: target.path) { return target }
        if let task = mediaTasks[name] { return try await task.value }
        let engine = self.engine
        let task = Task.detached(priority: .userInitiated) { () throws -> URL in
            if let cached = try? Data(contentsOf: target), sha256Hash(data: cached).lowercased() == hash { return target }
            let encrypted = try await DMMediaCrypto.download(file.url)
            let decrypted: Data
            do {
                decrypted = try await engine.decryptMedia(groupId: file.groupId, imeta: file.imeta, data: encrypted)
            } catch {
                throw CoreError(L("decryptionFailed"))
            }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try decrypted.write(to: target, options: .atomic)
            return target
        }
        mediaTasks[name] = task
        defer { mediaTasks[name] = nil }
        let url = try await task.value
        verifiedMedia.insert(name)
        return url
    }

    func searchProfiles(_ query: String, limit: Int = 40) async -> [Profile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let raw = try? await dbSearchProfiles(query: trimmed, limit: UInt32(limit)) else { return [] }
        let profiles = Self.parseArray(raw).map { dict -> Profile in
            Profile(
                pubkey: (dict["pubkeyHex"] as? String) ?? (dict["pubkey"] as? String) ?? "",
                name: (dict["name"] as? String) ?? "",
                displayName: (dict["display_name"] as? String) ?? "",
                about: (dict["about"] as? String) ?? "",
                picture: (dict["picture"] as? String) ?? "",
                nip05: (dict["nip05"] as? String) ?? ""
            )
        }
        .filter { !$0.pubkey.isEmpty }
        profiles.forEach { ProfileCache.shared.set($0) }
        return profiles
    }

    func followingPubkeys() async -> [String] {
        guard let me = me ?? Session.shared.pubkey else { return [] }
        return await SyncService.shared.followingList(me)
    }

    private nonisolated static func relayURLs(from events: [[String: Any]]) -> [String] {
        let latest = events.max { ($0["created_at"] as? NSNumber)?.intValue ?? 0 < ($1["created_at"] as? NSNumber)?.intValue ?? 0 }
        let tags = (latest?["tags"] as? [[String]]) ?? []
        var urls: [String] = []
        for tag in tags where tag.count > 1 && tag[0] == "relay" {
            let url = tag[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if url.hasPrefix("wss://") || url.hasPrefix("ws://"), !urls.contains(url) { urls.append(url) }
        }
        return urls
    }

    nonisolated static func parseArray(_ raw: String) -> [[String: Any]] {
        guard let data = raw.data(using: .utf8) else { return [] }
        return ((try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]) ?? []
    }

    nonisolated static func parseObject(_ raw: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    nonisolated static func jsonString(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

nonisolated enum DMMediaCrypto {
    static func upload(_ data: Data, sha256: String, privateKey: String, servers: [String]) async throws -> String {
        var lastError: Error = CoreError(L("failedToUploadEncryptedMedia"))
        for server in servers {
            do {
                return try await upload(data, sha256: sha256, privateKey: privateKey, server: server)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func upload(_ data: Data, sha256: String, privateKey: String, server: String) async throws -> String {
        let expiration = Int64(Date().timeIntervalSince1970) + 600
        let auth = try createBlossomAuthEvent(content: "Upload \(sha256)", sha256Hash: sha256, expiration: expiration, privateKeyHex: privateKey)
        let token = Data(auth.utf8).base64EncodedString()
        var base = server
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: "\(base)/upload") else { throw CoreError(L("failedToUploadEncryptedMedia")) }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 120
        request.setValue("Nostr \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (body, response) = try await URLSession.shared.upload(for: request, from: data)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw CoreError(L("uploadFailed", ["message": "\(status) \(String(decoding: body.prefix(200), as: UTF8.self))"]))
        }
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        if var link = json?["url"] as? String, !link.isEmpty {
            while link.hasSuffix(".") { link.removeLast() }
            return link
        }
        if let hash = json?["sha256"] as? String, !hash.isEmpty { return "\(base)/\(hash)" }
        return "\(base)/\(sha256)"
    }

    static func download(_ source: String) async throws -> Data {
        guard let url = URL(string: source), url.scheme?.lowercased() == "https" else { throw CoreError(L("failedToDecryptMedia")) }
        let limit = 50 * 1024 * 1024 + 1024
        let (file, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: file) }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw CoreError(L("failedToDecryptMedia")) }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= limit else { throw CoreError(L("fileTooLarge")) }
        return try Data(contentsOf: file)
    }

    static func cacheURL(hash: String, ext: String) -> URL? {
        let hash = hash.lowercased()
        guard hash.count == 64, hash.allSatisfy(\.isHexDigit),
              (1...10).contains(ext.count), ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("decrypted_media", isDirectory: true)
            .appendingPathComponent("decrypted_\(hash).\(ext.lowercased())")
    }

    static func fileExtension(for mimeType: String) -> String {
        let normalized = mimeType.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        let map = [
            "image/jpeg": "jpg", "image/png": "png", "image/gif": "gif", "image/webp": "webp", "image/heic": "heic",
            "video/mp4": "mp4", "video/quicktime": "mov", "video/x-msvideo": "avi", "video/webm": "webm",
            "audio/mpeg": "mp3", "audio/wav": "wav", "audio/ogg": "ogg", "audio/mp4": "m4a",
        ]
        return map[normalized] ?? "bin"
    }
}
