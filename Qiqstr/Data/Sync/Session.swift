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
    private(set) var account: StoredAccount?
    private(set) var accounts: [StoredAccount] = []
    private(set) var generation = 0
    var mutedPubkeys: [String] = []
    var mutedWords: [String] = []
    var isNewAccount = false

    var pubkey: String? { account?.pubkeyHex }
    var privateKey: String? { account?.privateKeyHex }
    var npub: String? { account?.npub }

    private let store = AccountStore.shared

    func launch() async {
        ServiceRegistry.register()
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

    func login(_ input: String) async throws {
        let account = try store.login(input: input)
        isNewAccount = false
        await start(account)
    }

    func createAccount() async throws -> StoredAccount {
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

    func logout() async {
        let next = store.logoutActive()
        await teardown()
        refreshAccounts()
        if let next {
            await start(next)
        } else {
            account = nil
            phase = .signedOut
        }
    }

    func removeAccount(_ npub: String) async {
        if npub == account?.npub {
            await logout()
        } else {
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

    private func start(_ account: StoredAccount) async {
        await teardown()
        let generation = self.generation
        self.account = account
        refreshAccounts()
        phase = .starting
        do {
            try FileManager.default.createDirectory(at: RelayConfig.databaseURL, withIntermediateDirectories: true)
            try await initClient(relayUrls: RelayConfig.mainRelays, privateKeyHex: account.privateKeyHex, dbPath: RelayConfig.databaseURL.path, discoveryRelays: RelayConfig.discoveryRelays)
            await applyRelayFlags()
            Task.detached { try? await connectRelays() }
            _ = try? await waitForReady(timeoutSecs: 3)
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
        let sync = SyncService.shared
        async let following: Void = sync.syncFollowingList(me, force: true)
        async let profile: Void = sync.syncProfile(me, force: true)
        _ = await (following, profile)
        guard generation == self.generation else { return }
        await SessionHooks.runBootstrap(me)
        guard generation == self.generation else { return }
        let follows = await sync.followingList(me)
        let mode = RelayConfig.gossipMode
        Task.detached {
            _ = try? await discoverAndConnectOutboxRelays(pubkeysHex: follows + [me], maxOutboxRelays: UInt32(mode.maxOutboxRelays), minRelayFrequency: UInt32(mode.minRelayFrequency))
        }
        await sync.syncFeed(force: true)
        guard generation == self.generation else { return }
        sync.startRealtime()
        await sync.syncNotifications(force: true)
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

    func markUnread() { hasUnreadNotifications = true }
    func markRead() { hasUnreadNotifications = false }
    func reset() { hasUnreadNotifications = false; hasUnreadMessages = false }
}

@MainActor
@Observable
final class ProfileCache {
    static let shared = ProfileCache()
    private(set) var profiles: [String: Profile] = [:]
    private var inflight: Set<String> = []

    func clear() { profiles.removeAll() }

    func profile(_ pubkey: String) -> Profile? { profiles[pubkey] }

    func set(_ profile: Profile) { profiles[profile.pubkey] = profile }

    func load(_ pubkeys: [String], fetchMissing: Bool = true) async {
        let wanted = Array(Set(pubkeys.filter { !$0.isEmpty && !inflight.contains($0) }))
        guard !wanted.isEmpty else { return }
        inflight.formUnion(wanted)
        defer { inflight.subtract(wanted) }
        let map = (JSON.any(try? await dbGetProfiles(pubkeysHex: wanted)) as? [String: Any]) ?? [:]
        var missing: [String] = []
        for pk in wanted {
            if let obj = map[pk] as? JSONObject {
                profiles[pk] = Profile(json: obj, fallbackPubkey: pk)
            } else if let s = map[pk] as? String, let obj = JSON.object(s) {
                profiles[pk] = Profile(json: obj, fallbackPubkey: pk)
            } else {
                missing.append(pk)
            }
        }
        if fetchMissing, !missing.isEmpty { SyncService.shared.fetchMissingProfiles(missing) }
    }

    func refresh(_ pubkey: String) async {
        if let raw = try? await dbGetProfile(pubkeyHex: pubkey), let obj = JSON.object(raw) {
            profiles[pubkey] = Profile(json: obj, fallbackPubkey: pubkey)
        }
    }
}
