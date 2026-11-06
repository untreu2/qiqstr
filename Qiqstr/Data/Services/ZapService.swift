import Foundation
import QiqstrCore

enum ZapError: LocalizedError {
    case noWallet
    case noAccount
    case noLightningAddress
    case zapsNotSupported
    case invalidAmount

    var errorDescription: String? {
        switch self {
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
        guard canZap else { return .needsSheet }
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
            failure = ZapFailure(note: note, amountSats: amountSats, message: message)
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
        guard amountSats > 0 else { throw ZapError.invalidAmount }
        let privateKey = try Session.shared.requireSigner()
        let recipient = await recipient(pubkey)
        let params: LnurlPayParams
        if let address = recipient.lightningAddress {
            params = try await Lnurl.payParams(address: address)
        } else if let url = recipient.lnurl {
            params = try await Lnurl.payParams(url: url)
        } else {
            throw ZapError.noLightningAddress
        }
        guard params.allowsNostr, let nostrPubkey = params.nostrPubkey, !nostrPubkey.isEmpty else { throw ZapError.zapsNotSupported }
        let amountMsat = Int64(amountSats) * 1000
        var tags: [[String]] = [
            ["relays"] + RelayConfig.mainRelays,
            ["amount", String(amountMsat)],
            ["lnurl", params.lnurl],
            ["p", pubkey],
        ]
        if let note {
            tags.append(["e", note.id])
            tags.append(["k", "1"])
        }
        if let note { pendingSats[note.id] = amountSats }
        defer { if let note { pendingSats[note.id] = nil } }
        let zapRequest = try createZapRequestEvent(tags: tags, content: comment.trimmingCharacters(in: .whitespacesAndNewlines), privateKeyHex: privateKey)
        let invoice = try await Lnurl.requestInvoice(params, amountMsat: amountMsat, zapRequest: zapRequest)
        try await WalletService.shared.payBolt11(invoice)
        if let note {
            zappedSats[note.id, default: 0] += amountSats
            zappedNoteIds.insert(note.id)
            scheduleReceiptSync(note.id)
        }
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
