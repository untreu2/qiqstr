import Foundation
import Observation
import QiqstrCore

nonisolated struct NutzapInfo: Hashable, Sendable {
    var mints: [String]
    var relays: [String]
    var lockKey: String

    init?(event: JSONObject) {
        let tags = event.tags()
        mints = tags.filter { $0.count > 1 && $0[0] == "mint" && $0[1].hasPrefix("https://") && ($0.count < 3 || $0[2].lowercased() == "sat") }.map { CashuMint.normalized($0[1]) }
        relays = tags.filter { $0.count > 1 && $0[0] == "relay" && RelayConfig.isUsableRelayURL($0[1]) }.map { $0[1] }
        guard let key = tags.first(where: { $0.count > 1 && $0[0] == "pubkey" })?[1].lowercased(), key.count == 64 || key.count == 66, key.allSatisfy(\.isHexDigit), !mints.isEmpty else { return nil }
        lockKey = key
    }
}

nonisolated enum CashuMint {
    static let presets = ["https://mint.minibits.cash/Bitcoin", "https://mint.coinos.io", "https://mint.lnvoltz.com", "https://mint.macadamia.cash"]

    static func normalized(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") { value = "https://\(value)" }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    static func isValid(_ raw: String) -> Bool {
        let value = normalized(raw)
        guard let components = URLComponents(string: value), components.scheme == "https", let host = components.host, host.contains(".") else { return false }
        return !value.contains(where: \.isWhitespace)
    }

    static func displayName(_ mint: String) -> String {
        guard let url = URL(string: mint), let host = url.host else { return mint }
        return url.path.count > 1 ? host + url.path : host
    }
}

nonisolated struct SentCashuToken: Codable, Hashable, Identifiable, Sendable {
    var id: String { token }
    var token: String
    var amountSats: Int
    var mint: String
    var createdAt: Date
}

@MainActor
@Observable
final class NutzapService {
    static let shared = NutzapService()
    static let infoKind = 10019
    static let nutzapKind = 9321
    static let walletKind = 17375
    static let historyKind = 7376

    private(set) var mints: [String] = []
    private(set) var isReceiving = false
    private(set) var isLoaded = false
    private(set) var isSaving = false
    private(set) var sentTokens: [SentCashuToken] = []
    private(set) var receivedTick = 0
    @ObservationIgnored private var owner: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lockSecret: String?
    @ObservationIgnored private var redeeming = false
    @ObservationIgnored private var infoCache: [String: (Date, NutzapInfo?)] = [:]

    var sendMint: String {
        get { UserDefaults.standard.string(forKey: "cashu_send_mint").flatMap { CashuMint.isValid($0) ? $0 : nil } ?? mints.first ?? CashuMint.presets[0] }
        set { UserDefaults.standard.set(CashuMint.normalized(newValue), forKey: "cashu_send_mint") }
    }

    var mintOptions: [String] {
        var seen: Set<String> = []
        return (mints + CashuMint.presets).filter { seen.insert($0).inserted }
    }

    func reset() {
        generation += 1
        owner = nil
        mints = []
        isReceiving = false
        isLoaded = false
        lockSecret = nil
        sentTokens = []
        infoCache = [:]
    }

    func load() async {
        guard AppStorePolicy.allowsCashu, let me = Session.shared.pubkey else { return }
        let generation = self.generation
        if owner != me {
            owner = me
            mints = UserDefaults.standard.stringArray(forKey: Self.mintsKey(me)) ?? []
            isReceiving = UserDefaults.standard.bool(forKey: Self.receivingKey(me))
            sentTokens = Self.storedTokens(me)
        }
        await publishOutbox()
        guard Session.shared.canSign else {
            isLoaded = true
            return
        }
        async let infoEvents = SyncService.shared.fetchReplaceable(kind: Self.infoKind, author: me)
        async let walletEvents = SyncService.shared.fetchReplaceable(kind: Self.walletKind, author: me)
        let info = (await infoEvents).max { $0.int("created_at") < $1.int("created_at") }.flatMap(NutzapInfo.init(event:))
        let wallet = (await walletEvents).max { $0.int("created_at") < $1.int("created_at") }
        guard generation == self.generation else { return }
        if let wallet, let secret = walletSecret(wallet, me: me) { lockSecret = secret }
        if let info {
            let ours = (try? lockKey()).map { Self.sameKey(info.lockKey, $0) } ?? false
            isReceiving = ours
            if ours { mints = info.mints }
        }
        persist()
        isLoaded = true
        if isReceiving { await redeemPending() }
    }

    private func walletSecret(_ event: JSONObject, me: String) -> String? {
        guard let key = Session.shared.privateKey, let content = event["content"] as? String, !content.isEmpty,
              let plain = try? nip44Decrypt(payload: content, receiverSkHex: key, senderPkHex: me),
              let tags = JSON.any(plain) as? [[Any]] else { return nil }
        return tags.map { $0.compactMap { $0 as? String } }.first { $0.count > 1 && $0[0] == "privkey" && $0[1].count == 64 }?[1].lowercased()
    }

    private func secret() throws -> String {
        if let lockSecret { return lockSecret }
        let key = try Session.shared.requireSigner()
        let derived = sha256Hash(data: Data("qiqstr-nutzap-p2pk:\(key)".utf8))
        lockSecret = derived
        return derived
    }

    private func lockKey() throws -> String {
        try getPublicKey(privateKeyHex: try secret())
    }

    private static func sameKey(_ a: String, _ b: String) -> Bool {
        String(a.suffix(64)).lowercased() == String(b.suffix(64)).lowercased()
    }

    func setReceiving(_ enabled: Bool, mints next: [String]? = nil) async throws {
        guard let me = Session.shared.pubkey else { return }
        let key = try Session.shared.requireSigner()
        let list = (next ?? (mints.isEmpty ? Array(CashuMint.presets.prefix(2)) : mints)).map(CashuMint.normalized).filter(CashuMint.isValid)
        guard !enabled || !list.isEmpty else { throw CoreError(L("nutzapNeedsMint")) }
        isSaving = true
        defer { isSaving = false }
        let lock = try lockKey()
        if enabled { try await publishWalletIfMissing(me: me, key: key, mints: list) }
        let base = try await SyncService.shared.latestEditableEvent(kind: Self.infoKind, author: me, allowingNew: true)
        let kept = (base?.tags() ?? []).filter { !["mint", "relay", "pubkey"].contains($0.first ?? "") }
        var tags: [[String]] = []
        if enabled {
            let relays = ((try? await getRelayList()) ?? RelayConfig.mainRelays).filter { $0.hasPrefix("wss://") }.prefix(4)
            tags = relays.map { ["relay", $0] } + list.map { ["mint", $0, "sat"] } + [["pubkey", lock]]
        }
        let event = try createSignedEvent(kind: UInt16(Self.infoKind), content: "", tags: tags + kept, privateKeyHex: key)
        try await SyncService.shared.publish(event)
        guard me == Session.shared.pubkey else { return }
        mints = list
        isReceiving = enabled
        infoCache[me] = nil
        persist()
        if enabled { Task { await redeemPending() } }
    }

    private func publishWalletIfMissing(me: String, key: String, mints: [String]) async throws {
        let existing = await SyncService.shared.fetchReplaceable(kind: Self.walletKind, author: me)
        if let newest = existing.max(by: { $0.int("created_at") < $1.int("created_at") }) {
            if let found = walletSecret(newest, me: me) { lockSecret = found }
            return
        }
        let payload: [[String]] = [["privkey", try secret()]] + mints.map { ["mint", $0] }
        let content = try nip44Encrypt(content: JSON.string(payload), senderSkHex: key, receiverPkHex: me)
        let event = try createSignedEvent(kind: UInt16(Self.walletKind), content: content, tags: [], privateKeyHex: key)
        try await SyncService.shared.publish(event)
    }

    func lookup(_ mint: String) async throws -> String {
        try WalletService.shared.prepareCashu()
        let info = JSON.object(try await cashuMintInfo(mintUrl: CashuMint.normalized(mint))) ?? [:]
        return info.str("name") ?? CashuMint.displayName(mint)
    }

    func info(for pubkey: String) async -> NutzapInfo? {
        if let cached = infoCache[pubkey], Date().timeIntervalSince(cached.0) < 600 { return cached.1 }
        let events = await SyncService.shared.fetchReplaceable(kind: Self.infoKind, author: pubkey)
        let info = events.max { $0.int("created_at") < $1.int("created_at") }.flatMap(NutzapInfo.init(event:))
        infoCache[pubkey] = (Date(), info)
        return info
    }

    func send(to pubkey: String, note: Note?, amountSats: Int, comment: String) async throws {
        guard AppStorePolicy.allowsCashu else { throw ZapError.zapsNotSupported }
        guard let me = Session.shared.pubkey, amountSats > 0 else { throw ZapError.invalidAmount }
        let key = try Session.shared.requireSigner()
        guard let info = await info(for: pubkey), let mint = info.mints.first else { throw CoreError(L("nutzapNotSupported")) }
        try WalletService.shared.prepareCashu()
        try await fund(mint: mint, amountSats: amountSats)
        let created = JSON.object(try await cashuCreateToken(mintUrl: mint, amountSats: UInt64(amountSats), p2pkPubkeyHex: info.lockKey)) ?? [:]
        let proofs = created.strings("proofs")
        guard !proofs.isEmpty else { throw CoreError(L("nutzapFailed")) }
        var tags: [[String]] = proofs.map { ["proof", $0] }
        tags.append(["u", mint])
        tags.append(["unit", "sat"])
        if let note {
            tags.append(["e", note.id, "", note.pubkey])
            tags.append(["k", String(note.kind)])
        }
        tags.append(["p", pubkey])
        let event = try createSignedEvent(kind: UInt16(Self.nutzapKind), content: comment.trimmingCharacters(in: .whitespacesAndNewlines), tags: tags, privateKeyHex: key)
        var relays = info.relays
        for relay in RelayConfig.mainRelays where !relays.contains(relay) { relays.append(relay) }
        var outbox = Self.outbox(me)
        outbox.append(JSON.string(["event": event, "relays": relays] as JSONObject))
        Self.setOutbox(outbox, me)
        await publishOutbox()
        await WalletService.shared.refresh()
    }

    func createToken(mint: String, amountSats: Int) async throws -> SentCashuToken {
        guard AppStorePolicy.allowsCashu, let me = Session.shared.pubkey, amountSats > 0 else { throw ZapError.invalidAmount }
        let url = CashuMint.normalized(mint)
        try WalletService.shared.prepareCashu()
        try await fund(mint: url, amountSats: amountSats)
        let created = JSON.object(try await cashuCreateToken(mintUrl: url, amountSats: UInt64(amountSats), p2pkPubkeyHex: nil)) ?? [:]
        guard let token = created.str("token") else { throw CoreError(L("cashuSendFailed")) }
        let sent = SentCashuToken(token: token, amountSats: amountSats, mint: url, createdAt: Date())
        sentTokens.insert(sent, at: 0)
        if sentTokens.count > 30 { sentTokens.removeLast(sentTokens.count - 30) }
        if let data = try? JSONEncoder().encode(sentTokens) { UserDefaults.standard.set(data, forKey: Self.tokensKey(me)) }
        await WalletService.shared.refresh()
        return sent
    }

    func forget(_ token: SentCashuToken) {
        guard let owner else { return }
        sentTokens.removeAll { $0.id == token.id }
        if let data = try? JSONEncoder().encode(sentTokens) { UserDefaults.standard.set(data, forKey: Self.tokensKey(owner)) }
    }

    private func fund(mint: String, amountSats: Int) async throws {
        let quote = JSON.object(try await cashuFundQuote(mintUrl: mint, amountSats: UInt64(amountSats))) ?? [:]
        guard quote.bool("needs_payment") else { return }
        guard let invoice = quote.str("invoice"), let quoteId = quote.str("quote_id") else { throw CoreError(L("cashuSendFailed")) }
        guard WalletService.shared.isConnected else { throw ZapError.noWallet }
        try await WalletService.shared.payBolt11(invoice)
        var lastError: Error = CoreError(L("cashuSendFailed"))
        for attempt in 0..<12 {
            do {
                _ = try await cashuFundComplete(mintUrl: mint, quoteId: quoteId)
                return
            } catch {
                lastError = error
                try? await Task.sleep(for: .milliseconds(attempt < 4 ? 800 : 2000))
            }
        }
        throw lastError
    }

    private func publishOutbox() async {
        guard let me = Session.shared.pubkey else { return }
        var remaining: [String] = []
        for entry in Self.outbox(me) {
            guard let object = JSON.object(entry), let event = object.str("event") else { continue }
            let relays = object.strings("relays")
            let targeted = (try? await SyncService.shared.publish(event, to: relays)) != nil
            let general = (try? await SyncService.shared.publish(event)) != nil
            if !targeted && !general { remaining.append(entry) }
        }
        Self.setOutbox(remaining, me)
    }

    func redeemPending() async {
        guard AppStorePolicy.allowsCashu, isReceiving, !redeeming, let me = Session.shared.pubkey, let key = Session.shared.privateKey, let unlock = try? secret() else { return }
        redeeming = true
        defer { redeeming = false }
        let generation = self.generation
        var done = Set(UserDefaults.standard.stringArray(forKey: Self.redeemedKey(me)) ?? [])
        let since = max(0, UserDefaults.standard.integer(forKey: Self.checkedKey(me)) - 172_800)
        var filter: JSONObject = ["kinds": [Self.nutzapKind], "#p": [me], "limit": 200]
        if since > 0 { filter["since"] = since }
        let events = await SyncService.shared.fetchEvents(filter, timeout: 8)
        guard generation == self.generation, (try? WalletService.shared.prepareCashu()) != nil else { return }
        let muted = Set(Session.shared.mutedPubkeys)
        var received = 0
        for event in events.sorted(by: { $0.int("created_at") < $1.int("created_at") }) {
            guard let id = event.str("id"), !done.contains(id), let sender = event.str("pubkey"), !muted.contains(sender) else { continue }
            let tags = event.tags()
            let proofs = tags.filter { $0.count > 1 && $0[0] == "proof" }.map { $0[1] }
            guard let mint = tags.first(where: { $0.count > 1 && $0[0] == "u" }).map({ CashuMint.normalized($0[1]) }), mints.contains(mint), !proofs.isEmpty else {
                done.insert(id)
                continue
            }
            do {
                let result = JSON.object(try await cashuRedeemProofs(mintUrl: mint, proofsJson: proofs, p2pkPrivateKeyHex: unlock, lightningTarget: WalletService.shared.lightningAddress ?? "")) ?? [:]
                let amount = result.int("received_sats")
                received += amount
                done.insert(id)
                await publishHistory(nutzapId: id, sender: sender, amount: amount, me: me, key: key)
            } catch {
                let message = coreErrorMessage(error).lowercased()
                if message.contains("spent") || message.contains("invalid") || message.contains("unlock") { done.insert(id) }
            }
        }
        guard generation == self.generation else { return }
        UserDefaults.standard.set(Array(done.suffix(2000)), forKey: Self.redeemedKey(me))
        UserDefaults.standard.set(TimeFormat.now, forKey: Self.checkedKey(me))
        if received > 0 {
            receivedTick += 1
            ToastCenter.shared.show(L("nutzapReceived", ["sats": Sats.format(received)]), style: .success)
            await WalletService.shared.refresh()
        }
    }

    private func publishHistory(nutzapId: String, sender: String, amount: Int, me: String, key: String) async {
        let payload: [[String]] = [["direction", "in"], ["amount", String(amount)], ["unit", "sat"]]
        guard let content = try? nip44Encrypt(content: JSON.string(payload), senderSkHex: key, receiverPkHex: me),
              let event = try? createSignedEvent(kind: UInt16(Self.historyKind), content: content, tags: [["e", nutzapId, "", "redeemed"], ["p", sender]], privateKeyHex: key) else { return }
        _ = try? await SyncService.shared.publish(event)
    }

    private func persist() {
        guard let owner else { return }
        UserDefaults.standard.set(mints, forKey: Self.mintsKey(owner))
        UserDefaults.standard.set(isReceiving, forKey: Self.receivingKey(owner))
    }

    private static func storedTokens(_ pubkey: String) -> [SentCashuToken] {
        guard let data = UserDefaults.standard.data(forKey: tokensKey(pubkey)) else { return [] }
        return (try? JSONDecoder().decode([SentCashuToken].self, from: data)) ?? []
    }

    private static func outbox(_ pubkey: String) -> [String] { UserDefaults.standard.stringArray(forKey: "nutzap_outbox_\(pubkey)") ?? [] }
    private static func setOutbox(_ entries: [String], _ pubkey: String) { UserDefaults.standard.set(entries, forKey: "nutzap_outbox_\(pubkey)") }
    private static func mintsKey(_ pubkey: String) -> String { "nutzap_mints_\(pubkey)" }
    private static func receivingKey(_ pubkey: String) -> String { "nutzap_receiving_\(pubkey)" }
    private static func redeemedKey(_ pubkey: String) -> String { "nutzap_redeemed_\(pubkey)" }
    private static func checkedKey(_ pubkey: String) -> String { "nutzap_checked_\(pubkey)" }
    private static func tokensKey(_ pubkey: String) -> String { "cashu_sent_tokens_\(pubkey)" }
}
