import Foundation
import QiqstrCore

enum ZapError: LocalizedError {
    case noWallet
    case noAccount
    case noLightningAddress
    case zapsNotSupported
    case invalidAmount
    case inProgress

    var errorDescription: String? {
        switch self {
        case .inProgress: L("zapInProgress")
        case .noWallet: L("pleaseConnectWalletFirst")
        case .noAccount: L("walletNoAccount")
        case .noLightningAddress: L("userNoLightningAddress")
        case .zapsNotSupported: L("zapNotSupported")
        case .invalidAmount: L("enterValidAmount")
        }
    }
}

enum QuickZapResult: Equatable, Sendable {
    case zapped(sats: Int)
    case needsSheet
    case failed(String)
}

struct ZapFailure: Identifiable, Equatable {
    let id = UUID()
    var note: Note
    var amountSats: Int
    var message: String
    var mayHaveSettled = false
}

struct ZapSplit: Hashable, Sendable {
    var pubkey: String
    var weight: Double

    static func parse(_ tags: [[String]]) -> [ZapSplit] {
        let entries = tags.filter { $0.count > 1 && $0[0] == "zap" && $0[1].count == 64 }
        guard !entries.isEmpty else { return [] }
        let weighted = entries.contains { $0.count > 3 && Double($0[3]) != nil }
        var result: [ZapSplit] = []
        for tag in entries {
            let weight = weighted ? (tag.count > 3 ? Double(tag[3]) ?? 0 : 0) : 1
            guard weight > 0, weight.isFinite, !result.contains(where: { $0.pubkey == tag[1] }) else { continue }
            result.append(ZapSplit(pubkey: tag[1], weight: weight))
        }
        return result
    }

    static func shares(_ amountSats: Int, splits: [ZapSplit]) -> [(pubkey: String, sats: Int)] {
        let total = splits.reduce(0) { $0 + $1.weight }
        guard total > 0, amountSats > 0 else { return [] }
        var shares = splits.map { (pubkey: $0.pubkey, sats: Int((Double(amountSats) * $0.weight / total).rounded(.down))) }
        var remainder = amountSats - shares.reduce(0) { $0 + $1.sats }
        for index in shares.indices.sorted(by: { splits[$0].weight > splits[$1].weight }) where remainder > 0 {
            shares[index].sats += 1
            remainder -= 1
        }
        return shares.filter { $0.sats > 0 }
    }

    static func percent(_ split: ZapSplit, of splits: [ZapSplit]) -> Int {
        let total = splits.reduce(0) { $0 + $1.weight }
        return total > 0 ? Int((split.weight / total * 100).rounded()) : 0
    }
}

extension Note {
    var zapSplits: [ZapSplit] { ZapSplit.parse(tags) }
}

struct ZapRecipient: Hashable, Sendable {
    var pubkey: String
    var name: String
    var lightningAddress: String?
    var lnurl: URL?
}

@MainActor
@Observable
final class ZapService {
    static let shared = ZapService()

    static let presetAmounts = [21, 100, 500, 1000, 5000, 10000]
    static let oneTapKey = "one_tap_zap"
    static let defaultAmountKey = "default_zap_amount"
    static let quickZapLimit = 5_000
    static let lastAmountKey = "last_zap_amount"

    static var defaultAmount: Int {
        let stored = UserDefaults.standard.integer(forKey: defaultAmountKey)
        return stored > 0 ? stored : 21
    }

    static var lastAmount: Int? {
        get {
            let stored = UserDefaults.standard.integer(forKey: lastAmountKey)
            return stored > 0 ? stored : nil
        }
        set { UserDefaults.standard.set(newValue, forKey: lastAmountKey) }
    }

    static var isOneTapEnabled: Bool { UserDefaults.standard.bool(forKey: oneTapKey) }

    private(set) var pendingSats: [String: Int] = [:]
    private(set) var zappedSats: [String: Int] = [:]
    private(set) var zappedNoteIds: Set<String> = []
    private(set) var failure: ZapFailure?
    private(set) var successTick = 0
    private(set) var failureTick = 0
    @ObservationIgnored private var failureHosts = 0

    var canZap: Bool { WalletService.shared.isConnected }
    var prefersQuickZap: Bool { canZap && Self.isOneTapEnabled }

    func isPending(_ noteId: String) -> Bool { pendingSats[noteId] != nil }
    func optimisticSats(for noteId: String) -> Int { zappedSats[noteId] ?? 0 }
    func hasZapped(_ noteId: String) -> Bool { zappedNoteIds.contains(noteId) }

    func reset() {
        pendingSats = [:]
        zappedSats = [:]
        zappedNoteIds = []
        failure = nil
    }

    @discardableResult
    func quickZap(note: Note) async -> QuickZapResult {
        guard prefersQuickZap else { return .needsSheet }
        return await quickZap(note: note, amountSats: Self.defaultAmount)
    }

    @discardableResult
    func retry(_ failure: ZapFailure) async -> QuickZapResult {
        if self.failure?.id == failure.id { self.failure = nil }
        guard canZap, !failure.mayHaveSettled else { return .needsSheet }
        return await quickZap(note: failure.note, amountSats: failure.amountSats)
    }

    func dismissFailure() { failure = nil }

    func registerFailureHost() { failureHosts += 1 }
    func unregisterFailureHost() { failureHosts = max(0, failureHosts - 1) }

    private func quickZap(note: Note, amountSats: Int) async -> QuickZapResult {
        guard !isPending(note.id) else { return .needsSheet }
        do {
            try await zap(note: note, pubkey: note.pubkey, amountSats: amountSats, comment: "")
            successTick += 1
            return .zapped(sats: amountSats)
        } catch {
            let message = coreMessage(error)
            failureTick += 1
            failure = ZapFailure(note: note, amountSats: amountSats, message: message, mayHaveSettled: (error as? WalletError) == .paymentPending)
            if failureHosts == 0 { ToastCenter.shared.show("\(L("failedToZap")): \(message)", style: .error) }
            return .failed(message)
        }
    }

    func recipient(_ pubkey: String) async -> ZapRecipient {
        let cache = ProfileCache.shared
        if cache.profile(pubkey) == nil { await cache.refresh(pubkey) }
        var raw = JSON.object(try? await dbGetProfile(pubkeyHex: pubkey))
        if (cache.profile(pubkey)?.lud16 ?? "").isEmpty && raw?.str("lud06") == nil {
            await SyncService.shared.syncProfile(pubkey, force: true)
            await cache.refresh(pubkey)
            raw = JSON.object(try? await dbGetProfile(pubkeyHex: pubkey))
        }
        let profile = cache.profile(pubkey)
        let address = (profile?.lud16 ?? raw?.str("lud16"))?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let lud06 = raw?.str("lud06") ?? address.flatMap { $0.lowercased().hasPrefix("lnurl1") ? $0 : nil }
        return ZapRecipient(
            pubkey: pubkey,
            name: profile?.bestName ?? Profile.shortNpub(pubkey),
            lightningAddress: address.flatMap { Lnurl.isLightningAddress($0) ? $0.lowercased() : nil },
            lnurl: lud06.flatMap { Lnurl.decode($0.lowercased()) }
        )
    }

    func zap(note: Note?, pubkey: String, amountSats: Int, comment: String) async throws {
        guard canZap else { throw ZapError.noWallet }
        guard SatsAmount.msat(amountSats) != nil else { throw ZapError.invalidAmount }
        if let note {
            guard pendingSats[note.id] == nil else { throw ZapError.inProgress }
            pendingSats[note.id] = amountSats
        }
        defer { if let note { pendingSats[note.id] = nil } }
        try Session.shared.requireSigner()
        let splits = note?.zapSplits ?? []
        var targets = ZapSplit.shares(amountSats, splits: splits)
        if targets.isEmpty { targets = [(pubkey: pubkey, sats: amountSats)] }
        var paid = 0
        var lastError: Error?
        for target in targets {
            do {
                try await pay(target.pubkey, sats: target.sats, comment: comment, note: note)
                paid += target.sats
            } catch WalletError.paymentPending {
                throw WalletError.paymentPending
            } catch {
                lastError = error
            }
        }
        if paid == 0, let lastError { throw lastError }
        if paid < amountSats {
            ToastCenter.shared.show(L("zapSplitPartial", ["sent": Sats.format(paid), "total": Sats.format(amountSats)]), style: .error)
        }
        if let note {
            zappedSats[note.id, default: 0] += paid
            zappedNoteIds.insert(note.id)
            scheduleReceiptSync(note.id)
        }
    }

    private func pay(_ pubkey: String, sats: Int, comment: String, note: Note?) async throws {
        guard let amountMsat = SatsAmount.msat(sats) else { throw ZapError.invalidAmount }
        let recipient = await recipient(pubkey)
        let params: LnurlPayParams
        if let address = recipient.lightningAddress {
            params = try await Lnurl.payParams(address: address)
            ZapperDirectory.shared.record(pubkey, address: address, params: params)
        } else if let url = recipient.lnurl {
            params = try await Lnurl.payParams(url: url)
        } else {
            throw ZapError.noLightningAddress
        }
        guard params.allowsNostr, let nostrPubkey = params.nostrPubkey, !nostrPubkey.isEmpty else { throw ZapError.zapsNotSupported }
        var tags: [[String]] = [
            ["relays"] + RelayConfig.mainRelays,
            ["amount", String(amountMsat)],
            ["lnurl", params.lnurl],
            ["p", pubkey],
        ]
        if let note {
            tags.append(["e", note.id])
            tags.append(["k", String(note.kind)])
        }
        let zapRequest = try signEvent(kind: 9734, content: comment.trimmingCharacters(in: .whitespacesAndNewlines), tags: tags)
        let invoice = try await Lnurl.requestInvoice(params, amountMsat: amountMsat, zapRequest: zapRequest)
        try await WalletService.shared.payBolt11(invoice)
    }

    private func scheduleReceiptSync(_ noteId: String) {
        Task {
            for delay in [3, 8] {
                try? await Task.sleep(for: .seconds(delay))
                await SyncService.shared.syncInteractions(for: [noteId])
                if delay == 8 { zappedSats[noteId] = nil }
                DataBus.shared.interactionsChanged()
            }
        }
    }
}
