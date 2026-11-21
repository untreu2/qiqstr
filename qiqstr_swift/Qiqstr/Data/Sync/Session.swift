import Foundation
import Observation
import QiqstrCore

enum SessionPhase: Equatable {
    case launching
    case signedOut
    case starting
    case ready
    case failed(String)
}

@MainActor
@Observable
final class Session {
    static let shared = Session()

    private(set) var phase: SessionPhase = .launching
    private(set) var account: Account?
    private(set) var accounts: [Account] = []
    private(set) var generation = 0
    var mutedPubkeys: [String] = []
    var mutedWords: [String] = []
    var isNewAccount = false

    var pubkey: String? { account?.pubkeyHex }
    var npub: String? { account?.npub }
    var isReadOnly: Bool { account?.isReadOnly ?? false }
    var canSign: Bool {
        guard let account, !account.isReadOnly else { return false }
        return (try? sessionPublicKey()) == account.pubkeyHex
    }

    func revealSigningKey() -> String? {
        account.flatMap { store.signingKey(for: $0.npub) }
    }

    func revealMnemonic() -> String? {
        account.flatMap { store.mnemonic(for: $0.npub) }
    }

    private let store = AccountStore.shared

    func launch() async {
        ServiceRegistry.register()
        clearKeychainAfterReinstall()
        refreshAccounts()
        #if DEBUG
        if store.active == nil, let input = UserDefaults.standard.string(forKey: "QIQ_LOGIN") {
            try? await login(input)
            return
        }
        #endif
        if let active = store.active {
            await start(active)
        } else {
            phase = .signedOut
        }
    }

    func refreshAccounts() { accounts = store.accounts }

    func recoverFromLaunchFailure() async {
        try? FileManager.default.removeItem(at: RelayConfig.databaseURL)
        RelayConfig.resetRelays()
        await launch()
    }

    private func clearKeychainAfterReinstall() {
        let defaults = UserDefaults.standard
        let marker = "install_marker"
        guard !defaults.bool(forKey: marker) else { return }
        let stored = Bundle.main.bundleIdentifier.flatMap(defaults.persistentDomain(forName:)) ?? [:]
        if stored.isEmpty { Keychain.wipe() }
        defaults.set(true, forKey: marker)
    }

    func login(_ input: String) async throws {
        let account: Account
        if Nip05Resolver.looksLikeAddress(input) {
            let identity = try await Nip05Resolver.resolve(input)
            account = try store.storeReadOnly(pubkeyHex: identity.pubkey)
        } else {
            account = try store.login(input: input)
        }
        isNewAccount = false
        await start(account)
    }

    func addKey(_ input: String) async throws {
        guard let current = account, current.isReadOnly else { return }
        let upgraded = try store.upgrade(npub: current.npub, input: input)
        guard let key = store.signingKey(for: upgraded.npub) else { throw AuthError.invalidKey }
        try await updateSigner(privateKeyHex: key)
        account = upgraded
        refreshAccounts()
        let generation = self.generation
        await SessionHooks.runBootstrap(upgraded.pubkeyHex)
        guard generation == self.generation else { return }
        DataBus.shared.everythingChanged()
    }

    func requireSigner() throws {
        guard canSign else {
            if account?.isReadOnly == true { ReadOnlyGate.shared.present() }
            throw ReadOnlyError.signerRequired
        }
    }

    func createAccount() async throws -> Account {
        let account = try store.createAccount()
        isNewAccount = true
        await start(account)
        return account
    }

    func switchAccount(_ npub: String) async throws {
        let account = try store.switchTo(npub: npub)
        isNewAccount = false
        await start(account)
    }

    func logout(erasingData: Bool = false) async {
        let leaving = account?.pubkeyHex
        let next = store.logoutActive()
        await teardown()
        refreshAccounts()
        if let leaving {
            if erasingData {
                account = nil
                phase = .starting
                await AccountData.erase(pubkey: leaving, isLastAccount: next == nil)
            } else {
                AccountData.removeCredentials(pubkey: leaving)
            }
        }
        if let next {
            await start(next)
        } else {
            try? await shutdownClient()
            account = nil
            phase = .signedOut
        }
    }

    func removeAccount(_ npub: String) async {
        if npub == account?.npub {
            await logout()
        } else {
            if let removed = accounts.first(where: { $0.npub == npub }) { AccountData.removeCredentials(pubkey: removed.pubkeyHex) }
            store.remove(npub: npub)
            refreshAccounts()
        }
    }

    func wipeEverything() async {
        await teardown()
        Keychain.wipe()
        _ = try? await dbWipeDirectory()
        try? FileManager.default.removeItem(at: RelayConfig.databaseURL)
        if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }
        account = nil
        refreshAccounts()
        phase = .signedOut
    }

    private func teardown() async {
        generation += 1
        SyncService.shared.reset()
        SessionHooks.runTeardown()
        mutedPubkeys = []
        mutedWords = []
        ProfileCache.shared.clear()
        NotificationBadge.shared.reset()
    }

    private func start(_ account: Account) async {
        await teardown()
        let generation = self.generation
        self.account = account
        refreshAccounts()
        phase = .starting
        do {
            try FileManager.default.createDirectory(at: RelayConfig.databaseURL, withIntermediateDirectories: true)
            try await initClient(relayUrls: RelayConfig.mainRelays, privateKeyHex: store.signingKey(for: account.npub), dbPath: RelayConfig.databaseURL.path, discoveryRelays: RelayConfig.discoveryRelays)
            await applyRelayFlags()
            Task.detached { try? await connectRelays() }
        } catch {
            phase = .failed(coreErrorMessage(error))
            return
        }
        guard generation == self.generation else { return }
        phase = .ready
        DataBus.shared.everythingChanged()
        Task { await self.bootstrap(account.pubkeyHex, generation: generation) }
    }

    private func bootstrap(_ me: String, generation: Int) async {
        _ = try? await waitForReady(timeoutSecs: 2)
        guard generation == self.generation else { return }
        let sync = SyncService.shared
        let cachedFollows = await sync.followingList(me)
        if !cachedFollows.isEmpty {
            sync.startRealtime()
        }
        async let following: Void = sync.syncFollowingList(me, force: true)
        async let profile: Void = sync.syncProfile(me, force: true)
        async let hooks: Void = SessionHooks.runBootstrap(me)
        _ = await (following, profile, hooks)
        guard generation == self.generation else { return }
        let follows = await sync.followingList(me)
        let mode = RelayConfig.gossipMode
        Task.detached {
            _ = try? await discoverAndConnectOutboxRelays(pubkeysHex: follows + [me], maxOutboxRelays: UInt32(mode.maxOutboxRelays), minRelayFrequency: UInt32(mode.minRelayFrequency))
        }
        async let feed: Void = sync.syncFeed(force: true)
        async let notifications: Void = sync.syncNotifications(force: true)
        if cachedFollows.isEmpty || follows != cachedFollows {
            sync.startRealtime()
        }
        _ = await (feed, notifications)
    }

    private func applyRelayFlags() async {
        struct Flags: Decodable { var read: Bool; var write: Bool }
        guard let raw = UserDefaults.standard.string(forKey: "relay_flags"), let data = raw.data(using: .utf8),
              let flags = try? JSONDecoder().decode([String: Flags].self, from: data) else { return }
        for relay in RelayConfig.mainRelays {
            guard let f = flags[relay], !(f.read && f.write) else { continue }
            _ = try? await addRelayWithFlags(url: relay, read: f.read, write: f.write)
        }
    }

    func isCurrent(_ generation: Int) -> Bool { generation == self.generation }
}

@MainActor
enum SessionHooks {
    private static var bootstrapHooks: [(String) async -> Void] = []
    private static var teardownHooks: [() -> Void] = []

    static func onBootstrap(_ hook: @escaping (String) async -> Void) { bootstrapHooks.append(hook) }
    static func onTeardown(_ hook: @escaping () -> Void) { teardownHooks.append(hook) }

    static func runBootstrap(_ pubkey: String) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in bootstrapHooks { group.addTask { await hook(pubkey) } }
        }
    }

    static func runTeardown() { teardownHooks.forEach { $0() } }
}

@MainActor
@Observable
final class NotificationBadge {
    static let shared = NotificationBadge()
    private(set) var hasUnreadNotifications = false
    var hasUnreadMessages = false

    private var unreadCount = 0

    func markUnread(from name: String? = nil) {
        hasUnreadNotifications = true
        unreadCount += 1
        WidgetBridge.update(unread: unreadCount, latestName: name)
    }

    func markRead() {
        hasUnreadNotifications = false
        unreadCount = 0
        WidgetBridge.markRead()
    }

    func reset() {
        hasUnreadNotifications = false
        hasUnreadMessages = false
        unreadCount = 0
        WidgetBridge.clear()
    }
}

@MainActor
@Observable
final class ProfileSlot {
    var profile: Profile?
}

@MainActor
final class ProfileCache {
    static let shared = ProfileCache()
    private var slots: [String: ProfileSlot] = [:]
    private var inflight: Set<String> = []
    private var queued: Set<String> = []
    private var queuedFetchMissing = false
    private var batchTask: Task<Void, Never>?

    private func slot(for pubkey: String) -> ProfileSlot {
        if let existing = slots[pubkey] { return existing }
        let created = ProfileSlot()
        slots[pubkey] = created
        return created
    }

    func clear() {
        batchTask?.cancel()
        batchTask = nil
        queued.removeAll()
        inflight.removeAll()
        for slot in slots.values { slot.profile = nil }
        slots.removeAll()
    }

    func profile(_ pubkey: String) -> Profile? {
        guard !pubkey.isEmpty else { return nil }
        return slot(for: pubkey).profile
    }

    func set(_ profile: Profile) {
        guard !profile.pubkey.isEmpty else { return }
        let target = slot(for: profile.pubkey)
        if target.profile != profile { target.profile = profile }
    }

    func load(_ pubkeys: [String], fetchMissing: Bool = true) async {
        let wanted = pubkeys.filter { !$0.isEmpty && slots[$0]?.profile == nil && !inflight.contains($0) }
        guard !wanted.isEmpty else { return }
        if wanted.count == 1 {
            queued.insert(wanted[0])
            if fetchMissing { queuedFetchMissing = true }
            await scheduleBatch().value
            return
        }
        await fetchBatch(Array(Set(wanted)), fetchMissing: fetchMissing, refreshing: false)
    }

    func reload(_ pubkeys: [String]) async {
        let wanted = Array(Set(pubkeys.filter { !$0.isEmpty }))
        guard !wanted.isEmpty else { return }
        await fetchBatch(wanted, fetchMissing: false, refreshing: true)
    }

    private func scheduleBatch() -> Task<Void, Never> {
        if let batchTask { return batchTask }
        let task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard let self else { return }
            self.batchTask = nil
            let batch = Array(self.queued)
            let fetchMissing = self.queuedFetchMissing
            self.queued.removeAll()
            self.queuedFetchMissing = false
            guard !batch.isEmpty else { return }
            await self.fetchBatch(batch, fetchMissing: fetchMissing, refreshing: false)
        }
        batchTask = task
        return task
    }

    private func fetchBatch(_ batch: [String], fetchMissing: Bool, refreshing: Bool) async {
        let wanted = batch.filter { !$0.isEmpty && (refreshing || slots[$0]?.profile == nil) && !inflight.contains($0) }
        guard !wanted.isEmpty else { return }
        inflight.formUnion(wanted)
        defer { inflight.subtract(wanted) }
        let raw = try? await dbGetProfiles(pubkeysHex: wanted)
        let parsed: ([String: Profile], [String]) = await Task.detached(priority: .userInitiated) {
            let map = (JSON.any(raw) as? [String: Any]) ?? [:]
            var loaded: [String: Profile] = [:]
            var missing: [String] = []
            for pk in wanted {
                if let obj = map[pk] as? JSONObject {
                    loaded[pk] = Profile(json: obj, fallbackPubkey: pk)
                } else if let s = map[pk] as? String, let obj = JSON.object(s) {
                    loaded[pk] = Profile(json: obj, fallbackPubkey: pk)
                } else {
                    missing.append(pk)
                }
            }
            return (loaded, missing)
        }.value
        for (pk, profile) in parsed.0 {
            let target = slot(for: pk)
            if target.profile != profile { target.profile = profile }
        }
        if fetchMissing, !parsed.1.isEmpty { SyncService.shared.fetchMissingProfiles(parsed.1) }
    }

    func refresh(_ pubkey: String) async {
        if let raw = try? await dbGetProfile(pubkeyHex: pubkey), let obj = JSON.object(raw) {
            set(Profile(json: obj, fallbackPubkey: pubkey))
        }
    }
}
