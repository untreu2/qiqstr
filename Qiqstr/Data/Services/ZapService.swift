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

struct ZapRecipient: Hashable, Sendable {
    var pubkey: String
    var name: String
    var lightningAddress: String?
    var lnurl: URL?
}

@MainActor
final class ZapService {
    static let shared = ZapService()

    static let presetAmounts = [21, 100, 500, 1000, 5000, 10000]

    static var defaultAmount: Int {
        let stored = UserDefaults.standard.integer(forKey: "default_zap_amount")
        return stored > 0 ? stored : 21
    }

    var canZap: Bool { WalletService.shared.isConnected }

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
        guard let privateKey = Session.shared.privateKey else { throw ZapError.noAccount }
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
        let zapRequest = try createZapRequestEvent(tags: tags, content: comment.trimmingCharacters(in: .whitespacesAndNewlines), privateKeyHex: privateKey)
        let invoice = try await Lnurl.requestInvoice(params, amountMsat: amountMsat, zapRequest: zapRequest)
        try await WalletService.shared.payBolt11(invoice)
        if let note { scheduleReceiptSync(note.id) }
    }

    private func scheduleReceiptSync(_ noteId: String) {
        Task {
            for delay in [3, 8] {
                try? await Task.sleep(for: .seconds(delay))
                await SyncService.shared.syncInteractions(for: [noteId])
                DataBus.shared.interactionsChanged()
            }
        }
    }
}
