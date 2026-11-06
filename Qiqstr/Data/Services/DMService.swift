import Foundation
import Observation
import QiqstrCore

nonisolated struct DMFileInfo: Hashable, Sendable {
    var mimeType: String
    var key: String?
    var nonce: String?
    var encryptedHash: String?
    var originalHash: String?
    var size: Int?

    var isEncrypted: Bool { key != nil && nonce != nil && originalHash != nil }
    var isImage: Bool { mimeType.lowercased().hasPrefix("image/") }
    var isVideo: Bool { mimeType.lowercased().hasPrefix("video/") }
    var fileExtension: String { DMMediaCrypto.fileExtension(for: mimeType) }
}

nonisolated enum DMDeliveryState: Hashable, Sendable {
    case sent, sending, failed
}

nonisolated struct DMMessage: Identifiable, Hashable, Sendable {
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

    init?(json j: [String: Any]) {
        guard let id = j["id"] as? String, !id.isEmpty,
              let sender = j["senderPubkeyHex"] as? String,
              let peer = j["recipientPubkeyHex"] as? String, !peer.isEmpty else { return nil }
        let kind = (j["kind"] as? NSNumber)?.intValue ?? 14
        self.init(
            id: id,
            sender: sender,
            peer: peer,
            content: (j["content"] as? String) ?? "",
            createdAt: (j["createdAt"] as? NSNumber)?.intValue ?? 0,
            isMine: (j["isFromCurrentUser"] as? Bool) ?? false,
            kind: kind
        )
        if kind == 15 {
            file = DMFileInfo(
                mimeType: (j["mimeType"] as? String) ?? "application/octet-stream",
                key: j["encryptionKey"] as? String,
                nonce: j["encryptionNonce"] as? String,
                encryptedHash: j["encryptedHash"] as? String,
                originalHash: j["originalHash"] as? String,
                size: (j["fileSize"] as? NSNumber)?.intValue
            )
        }
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
    var key: String
    var nonce: String
    var encryptedHash: String
    var originalHash: String
    var size: Int
}

@MainActor
@Observable
final class DMService {
    static let shared = DMService()

    static let maxFileSize = 50 * 1024 * 1024

    private(set) var conversations: [DMConversation] = []
    private(set) var messagesByPeer: [String: [DMMessage]] = [:]
    private(set) var following: Set<String> = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var isRefreshing = false
    var activePeer: String? {
        didSet { if let activePeer { markRead(activePeer) } }
    }
    var isListVisible = false {
        didSet { if isListVisible { markTabSeen() } }
    }

    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var me: String?
    @ObservationIgnored private var privateKey: String?
    @ObservationIgnored private var unwrapCache: [String: DMMessage?] = [:]
    @ObservationIgnored private var realtimeTask: Task<Void, Never>?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var dmRelayFetchedAt: [String: Date] = [:]
    @ObservationIgnored private var dmRelayCache: [String: [String]] = [:]
    @ObservationIgnored private var readMarks: [String: Int] = [:]
    @ObservationIgnored private var readBaseline = 0
    @ObservationIgnored private var tabSeenAt = 0
    @ObservationIgnored private var verifiedMedia: Set<String> = []
    @ObservationIgnored private var mediaTasks: [String: Task<URL, Error>] = [:]

    private var defaults: UserDefaults { .standard }

    func reset() {
        generation += 1
        realtimeTask?.cancel()
        realtimeTask = nil
        startTask?.cancel()
        startTask = nil
        dmRelayFetchedAt.removeAll()
        me = nil
        privateKey = nil
        unwrapCache.removeAll()
        dmRelayCache.removeAll()
        readMarks.removeAll()
        readBaseline = 0
        tabSeenAt = 0
        verifiedMedia.removeAll()
        mediaTasks.values.forEach { $0.cancel() }
        mediaTasks.removeAll()
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
        guard let me = Session.shared.pubkey, let key = Session.shared.privateKey else { return }
        if self.me == me, let startTask {
            await startTask.value
            return
        }
        if self.me != nil, self.me != me { reset() }
        self.me = me
        privateKey = key
        let generation = self.generation
        loadReadState(me)
        isLoading = true
        let task = Task { await self.performStart(me, generation: generation) }
        startTask = task
        await task.value
    }

    private func performStart(_ me: String, generation: Int) async {
        await reloadFollowing()
        await loadLocal(generation: generation)
        guard generation == self.generation else { return }
        startRealtime(generation: generation)
        await fetchFromRelays(limit: 500, timeout: 10, generation: generation)
        guard generation == self.generation else { return }
        isLoading = false
        hasLoaded = true
        _ = await dmRelays(for: me)
    }

    func refresh() async {
        guard me != nil else { await start(); return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let generation = self.generation
        await fetchFromRelays(limit: 200, timeout: 8, generation: generation)
        guard generation == self.generation else { return }
        if realtimeTask == nil { startRealtime(generation: generation) }
    }

    func reloadFollowing() async {
        guard let me = me ?? Session.shared.pubkey else { return }
        let list = Set(await SyncService.shared.followingList(me))
        if list != following { following = list }
    }

    func messages(with peer: String) -> [DMMessage] { messagesByPeer[peer] ?? [] }

    func conversation(with peer: String) -> DMConversation? { conversations.first { $0.peer == peer } }

    func isFollowing(_ pubkey: String) -> Bool { following.contains(pubkey) }

    var unreadCount: Int { conversations.filter(\.isUnread).count }

    func errorMessage(_ error: Error) -> String { coreErrorMessage(error) }

    private func loadLocal(generation: Int) async {
        guard let me else { return }
        let filter = Self.jsonString(["kinds": [1059], "#p": [me], "limit": 1000])
        guard let raw = try? await dbQueryEvents(filterJson: filter, limit: 1000) else { return }
        guard generation == self.generation else { return }
        await ingest(arrayJSON: raw, generation: generation)
    }

    private func fetchFromRelays(limit: Int, timeout: UInt32, generation: Int) async {
        guard let me else { return }
        let filter = Self.jsonString(["kinds": [1059], "#p": [me], "limit": limit])
        guard let raw = try? await fetchEvents(filterJson: filter, timeoutSecs: timeout) else { return }
        guard generation == self.generation else { return }
        await ingest(arrayJSON: raw, generation: generation)
    }

    private func startRealtime(generation: Int) {
        realtimeTask?.cancel()
        realtimeTask = Task { await self.runRealtime(generation: generation) }
    }

    private func runRealtime(generation: Int) async {
        while !Task.isCancelled, generation == self.generation, let me {
            let filter = Self.jsonString(["kinds": [1059], "#p": [me], "since": TimeFormat.now - 259_200])
            let stream = EventStream.make { sink in try await subscribeToEvents(filterJson: filter, sink: sink) }
            do {
                for try await raw in stream {
                    guard generation == self.generation, !Task.isCancelled else { break }
                    await ingest(raws: [raw], generation: generation)
                }
            } catch {}
            guard !Task.isCancelled, generation == self.generation else { break }
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func ingest(arrayJSON: String, generation: Int) async {
        let known = Set(unwrapCache.keys)
        guard let key = privateKey, let me else { return }
        let results = await Task.detached(priority: .userInitiated) {
            Self.unwrap(events: Self.parseArray(arrayJSON), skipping: known, privateKey: key, me: me)
        }.value
        guard generation == self.generation else { return }
        apply(results)
    }

    private func ingest(raws: [String], generation: Int) async {
        let known = Set(unwrapCache.keys)
        guard let key = privateKey, let me else { return }
        let results = await Task.detached(priority: .userInitiated) {
            Self.unwrap(events: raws.compactMap(Self.parseObject), skipping: known, privateKey: key, me: me)
        }.value
        guard generation == self.generation else { return }
        apply(results)
    }

    private func apply(_ results: [UnwrapResult]) {
        guard !results.isEmpty else { return }
        var changedPeers: Set<String> = []
        for result in results {
            unwrapCache[result.wrapId] = result.message
            guard let message = result.message else { continue }
            if insert(message) { changedPeers.insert(message.peer) }
        }
        guard !changedPeers.isEmpty else { return }
        if let activePeer, changedPeers.contains(activePeer) { markReadSilently(activePeer) }
        rebuildConversations()
        let missing = changedPeers.filter { ProfileCache.shared.profile($0) == nil }
        if !missing.isEmpty { Task { await ProfileCache.shared.load(Array(missing)) } }
        DataBus.shared.dmChanged()
    }

    @discardableResult
    private func insert(_ message: DMMessage) -> Bool {
        var list = messagesByPeer[message.peer] ?? []
        if list.contains(where: { $0.id == message.id }) { return false }
        let index = list.lastIndex { $0.createdAt <= message.createdAt }.map { $0 + 1 } ?? 0
        list.insert(message, at: index)
        messagesByPeer[message.peer] = list
        return true
    }

    private func rebuildConversations() {
        conversations = messagesByPeer.compactMap { peer, list in
            guard let last = list.last(where: { $0.state == .sent }) ?? list.last else { return nil }
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
            guard conversation.isUnread, let incoming = lastIncoming(messagesByPeer[conversation.peer] ?? []) else { return false }
            return incoming.createdAt > tabSeenAt
        }
        if isListVisible, unseen { markTabSeen(); return }
        NotificationBadge.shared.hasUnreadMessages = unseen
    }

    private func readKey(_ name: String, _ me: String) -> String { "dm_\(name)_\(me)" }

    private func loadReadState(_ me: String) {
        readMarks = (defaults.dictionary(forKey: readKey("read_marks", me)) as? [String: Int]) ?? [:]
        let baseline = defaults.integer(forKey: readKey("read_baseline", me))
        if baseline > 0 {
            readBaseline = baseline
        } else {
            readBaseline = TimeFormat.now
            defaults.set(readBaseline, forKey: readKey("read_baseline", me))
        }
        let seen = defaults.integer(forKey: readKey("tab_seen", me))
        tabSeenAt = seen > 0 ? seen : readBaseline
    }

    private func persistReadMarks() {
        guard let me else { return }
        defaults.set(readMarks, forKey: readKey("read_marks", me))
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
        defaults.set(tabSeenAt, forKey: readKey("tab_seen", me))
        NotificationBadge.shared.hasUnreadMessages = false
    }

    func send(_ text: String, to peer: String) async throws {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard let me, let key = privateKey else { throw CoreError(L("dmNotSignedIn")) }
        let pending = DMMessage(id: "pending-\(UUID().uuidString)", sender: me, peer: peer, content: content, createdAt: TimeFormat.now, isMine: true, kind: 14, state: .sending)
        addPending(pending)
        do {
            let pair = try await Task.detached {
                try createGiftWrapDmPair(senderPrivateKeyHex: key, receiverPubkeyHex: peer, message: content)
            }.value
            try await deliver(pair, to: peer, replacing: pending.id)
        } catch {
            markFailed(pending.id, peer: peer)
            throw error
        }
    }

    func sendFile(_ data: Data, mimeType: String, to peer: String) async throws {
        let prepared = try await prepareFile(data, mimeType: mimeType)
        try await sendPrepared(prepared, to: peer)
    }

    func prepareFile(_ data: Data, mimeType: String) async throws -> DMPreparedFile {
        guard data.count <= Self.maxFileSize else { throw CoreError(L("fileTooLarge")) }
        guard let key = privateKey else { throw CoreError(L("dmNotSignedIn")) }
        let encrypted: DMMediaCrypto.Encrypted
        do {
            encrypted = try await Task.detached(priority: .userInitiated) { try DMMediaCrypto.encrypt(data) }.value
        } catch {
            throw CoreError("\(L("encryptionFailed")): \(coreErrorMessage(error))")
        }
        let ext = DMMediaCrypto.fileExtension(for: mimeType)
        if let url = DMMediaCrypto.cacheURL(hash: encrypted.originalHash, ext: ext) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
            verifiedMedia.insert(url.lastPathComponent)
        }
        let url: String
        do {
            url = try await DMMediaCrypto.upload(encrypted.data, sha256: encrypted.encryptedHash, privateKey: key, server: RelayConfig.blossomServer)
        } catch {
            throw CoreError(L("failedToUploadEncryptedMedia"))
        }
        return DMPreparedFile(url: url, mimeType: mimeType, key: encrypted.key, nonce: encrypted.nonce, encryptedHash: encrypted.encryptedHash, originalHash: encrypted.originalHash, size: encrypted.data.count)
    }

    func sendPrepared(_ file: DMPreparedFile, to peer: String) async throws {
        guard let me, let key = privateKey else { throw CoreError(L("dmNotSignedIn")) }
        let info = DMFileInfo(mimeType: file.mimeType, key: file.key, nonce: file.nonce, encryptedHash: file.encryptedHash, originalHash: file.originalHash, size: file.size)
        let pending = DMMessage(id: "pending-\(UUID().uuidString)", sender: me, peer: peer, content: file.url, createdAt: TimeFormat.now, isMine: true, kind: 15, file: info, state: .sending)
        addPending(pending)
        do {
            let pair = try await Task.detached {
                try createGiftWrapFileMessagePair(
                    senderPrivateKeyHex: key, receiverPubkeyHex: peer, fileUrl: file.url, mimeType: file.mimeType,
                    encryptionKeyHex: file.key, encryptionNonceHex: file.nonce, encryptedHash: file.encryptedHash,
                    originalHash: file.originalHash, fileSize: UInt64(file.size)
                )
            }.value
            try await deliver(pair, to: peer, replacing: pending.id)
        } catch {
            markFailed(pending.id, peer: peer)
            throw error
        }
    }

    func retry(_ message: DMMessage) async throws {
        discard(message)
        if message.isFile, let file = message.file, let key = file.key, let nonce = file.nonce, let original = file.originalHash {
            let prepared = DMPreparedFile(url: message.content, mimeType: file.mimeType, key: key, nonce: nonce, encryptedHash: file.encryptedHash ?? "", originalHash: original, size: file.size ?? 0)
            try await sendPrepared(prepared, to: message.peer)
        } else {
            try await send(message.content, to: message.peer)
        }
    }

    func discard(_ message: DMMessage) {
        guard message.state != .sent else { return }
        messagesByPeer[message.peer]?.removeAll { $0.id == message.id }
        if messagesByPeer[message.peer]?.isEmpty == true { messagesByPeer[message.peer] = nil }
        rebuildConversations()
    }

    private func addPending(_ message: DMMessage) {
        insert(message)
        rebuildConversations()
    }

    private func markFailed(_ id: String, peer: String) {
        guard let index = messagesByPeer[peer]?.firstIndex(where: { $0.id == id }) else { return }
        messagesByPeer[peer]?[index].state = .failed
        rebuildConversations()
    }

    private func deliver(_ pairJSON: String, to peer: String, replacing pendingId: String) async throws {
        guard let me else { throw CoreError(L("dmNotSignedIn")) }
        let generation = self.generation
        guard let pair = Self.parseObject(pairJSON),
              let recipientWrap = pair["recipientWrap"] as? [String: Any],
              let senderWrap = pair["senderWrap"] as? [String: Any] else { throw CoreError(L("dmSendFailed")) }
        let recipientJSON = Self.jsonString(recipientWrap)
        let senderJSON = Self.jsonString(senderWrap)
        async let peerRelays = dmRelays(for: peer)
        async let ownRelays = dmRelays(for: me)
        let (recipientTargets, ownTargets) = await (peerRelays, ownRelays)
        async let recipientSent = Self.publish(recipientJSON, relays: recipientTargets)
        async let senderSent = Self.publish(senderJSON, relays: ownTargets)
        let (recipientOK, _) = await (recipientSent, senderSent)
        guard generation == self.generation else { return }
        guard recipientOK else { throw CoreError(L("dmSendFailed")) }
        _ = try? await dbSaveEvents(eventsJson: "[\(senderJSON)]")
        guard generation == self.generation else { return }
        await ingest(raws: [senderJSON], generation: generation)
        guard generation == self.generation else { return }
        let senderWrapId = (senderWrap["id"] as? String) ?? ""
        if case .some(.some) = unwrapCache[senderWrapId] {
            messagesByPeer[peer]?.removeAll { $0.id == pendingId }
        } else if let index = messagesByPeer[peer]?.firstIndex(where: { $0.id == pendingId }) {
            messagesByPeer[peer]?[index].state = .sent
        }
        markReadSilently(peer)
        rebuildConversations()
    }

    private nonisolated static func publish(_ json: String, relays: [String]) async -> Bool {
        if !relays.isEmpty, (try? await sendEventTo(eventJson: json, relayUrls: relays)) != nil { return true }
        return (try? await sendEvent(eventJson: json)) != nil
    }

    func dmRelays(for pubkey: String) async -> [String] {
        if let cached = dmRelayCache[pubkey] {
            let fresh = Date().timeIntervalSince(dmRelayFetchedAt[pubkey] ?? .distantPast) < 300
            if !cached.isEmpty || fresh { return cached }
        }
        let filter = Self.jsonString(["kinds": [10050], "authors": [pubkey], "limit": 1])
        var relays = Self.relayURLs(fromArrayJSON: try? await dbQueryEvents(filterJson: filter, limit: 1))
        if relays.isEmpty {
            relays = Self.relayURLs(fromArrayJSON: try? await fetchEvents(filterJson: filter, timeoutSecs: 5))
        }
        dmRelayCache[pubkey] = relays
        dmRelayFetchedAt[pubkey] = Date()
        return relays
    }

    func decryptedFileURL(for message: DMMessage) async throws -> URL {
        guard let file = message.file, let key = file.key, let nonce = file.nonce, let hash = file.originalHash?.lowercased() else {
            throw CoreError(L("failedToDecryptMedia"))
        }
        let ext = file.fileExtension
        guard let target = DMMediaCrypto.cacheURL(hash: hash, ext: ext) else { throw CoreError(L("failedToDecryptMedia")) }
        let name = target.lastPathComponent
        if verifiedMedia.contains(name), FileManager.default.fileExists(atPath: target.path) { return target }
        if let task = mediaTasks[name] { return try await task.value }
        let source = message.content
        let task = Task.detached(priority: .userInitiated) { () throws -> URL in
            try await DMMediaCrypto.loadDecrypted(from: source, key: key, nonce: nonce, originalHash: hash, target: target)
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

    nonisolated struct UnwrapResult: Sendable {
        var wrapId: String
        var message: DMMessage?
    }

    private nonisolated static func unwrap(events: [[String: Any]], skipping known: Set<String>, privateKey: String, me: String) -> [UnwrapResult] {
        var seen = known
        var results: [UnwrapResult] = []
        for event in events {
            guard (event["kind"] as? NSNumber)?.intValue == 1059, let id = event["id"] as? String, !seen.contains(id) else { continue }
            seen.insert(id)
            let message = (try? unwrapGiftWrapDm(receiverPrivateKeyHex: privateKey, giftWrapJson: jsonString(event), currentUserPubkeyHex: me))
                .flatMap(parseObject)
                .flatMap(DMMessage.init(json:))
            results.append(UnwrapResult(wrapId: id, message: message))
        }
        return results
    }

    private nonisolated static func relayURLs(fromArrayJSON raw: String?) -> [String] {
        guard let raw else { return [] }
        let latest = parseArray(raw).max { ($0["created_at"] as? NSNumber)?.intValue ?? 0 < ($1["created_at"] as? NSNumber)?.intValue ?? 0 }
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
    struct Encrypted: Sendable {
        var data: Data
        var key: String
        var nonce: String
        var originalHash: String
        var encryptedHash: String
    }

    static func encrypt(_ data: Data) throws -> Encrypted {
        let originalHash = sha256Hash(data: data)
        let key = generateAesKey()
        let nonce = generateAesNonce()
        let encryptedBase64 = try aesGcmEncrypt(data: data, keyHex: key, nonceHex: nonce)
        guard let encrypted = Data(base64Encoded: encryptedBase64) else { throw CoreError(L("encryptionFailed")) }
        return Encrypted(data: encrypted, key: key, nonce: nonce, originalHash: originalHash, encryptedHash: sha256Hash(data: encrypted))
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
        if let link = json?["url"] as? String, !link.isEmpty { return link }
        if let hash = json?["sha256"] as? String, !hash.isEmpty { return "\(base)/\(hash)" }
        return "\(base)/\(sha256)"
    }

    static func loadDecrypted(from source: String, key: String, nonce: String, originalHash: String, target: URL) async throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: target.path), let cached = try? Data(contentsOf: target) {
            if sha256Hash(data: cached).lowercased() == originalHash { return target }
            try? fm.removeItem(at: target)
        }
        guard let url = URL(string: source), url.scheme?.hasPrefix("http") == true else { throw CoreError(L("failedToDecryptMedia")) }
        let (encrypted, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw CoreError(L("failedToDecryptMedia")) }
        guard let keyHex = normalizeToHex(key, lengths: [32]), let nonceHex = normalizeToHex(nonce, lengths: [12, 16]) else {
            throw CoreError(L("decryptionFailed"))
        }
        let decrypted = try aesGcmDecrypt(encryptedBase64: encrypted.base64EncodedString(), keyHex: keyHex, nonceHex: nonceHex)
        guard sha256Hash(data: decrypted).lowercased() == originalHash.lowercased() else { throw CoreError(L("decryptionError")) }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try decrypted.write(to: target, options: .atomic)
        return target
    }

    static func cacheURL(hash: String, ext: String) -> URL? {
        let hash = hash.lowercased()
        guard hash.count == 64, hash.allSatisfy(\.isHexDigit),
              (1...10).contains(ext.count), ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("decrypted_media", isDirectory: true)
            .appendingPathComponent("decrypted_\(hash).\(ext.lowercased())")
    }

    static func normalizeToHex(_ input: String, lengths: [Int]) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count % 2 == 0, lengths.contains(value.count / 2), value.allSatisfy(\.isHexDigit) { return value.lowercased() }
        var padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded.append("=") }
        if let data = Data(base64Encoded: padded), lengths.contains(data.count) {
            return data.map { String(format: "%02x", $0) }.joined()
        }
        return nil
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
