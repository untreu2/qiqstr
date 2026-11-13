import Foundation
import QiqstrCore

@MainActor
final class ZapperDirectory {
    static let shared = ZapperDirectory()

    private struct Entry: Codable {
        var address: String
        var zapper: String
        var checkedAt: Double
    }

    private let storeKey = "zapper_directory"
    private let lifetime: TimeInterval = 3 * 86_400
    private let limit = 500
    private var entries: [String: Entry] = [:]
    private var inFlight: Set<String> = []
    private var didLoad = false

    func prepare() {
        loadIfNeeded()
        push()
    }

    func record(_ pubkey: String, address: String, params: LnurlPayParams) {
        loadIfNeeded()
        store(pubkey.lowercased(), address: address, zapper: Self.zapper(from: params))
    }

    func verify(_ pubkey: String) async {
        loadIfNeeded()
        let key = pubkey.lowercased()
        guard !key.isEmpty, !inFlight.contains(key) else { return }
        guard let address = await Self.address(for: key) else { return }
        if let entry = entries[key], entry.address == address, Date().timeIntervalSince1970 - entry.checkedAt < lifetime { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        let params: LnurlPayParams
        do {
            if Lnurl.isLightningAddress(address) {
                params = try await Lnurl.payParams(address: address)
            } else if let url = Lnurl.decode(address) {
                params = try await Lnurl.payParams(url: url)
            } else {
                return
            }
        } catch {
            return
        }
        store(key, address: address, zapper: Self.zapper(from: params))
    }

    func reset() {
        inFlight = []
    }

    private func store(_ pubkey: String, address: String, zapper: String) {
        let previous = entries[pubkey]?.zapper
        entries[pubkey] = Entry(address: address, zapper: zapper, checkedAt: Date().timeIntervalSince1970)
        if entries.count > limit {
            let stale = entries.sorted { $0.value.checkedAt < $1.value.checkedAt }.prefix(entries.count - limit).map(\.key)
            stale.forEach { entries[$0] = nil }
        }
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: storeKey) }
        guard previous != zapper else { return }
        push()
        DataBus.shared.interactionsChanged()
        DataBus.shared.notificationsChanged()
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let data = UserDefaults.standard.data(forKey: storeKey), let stored = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = stored
        }
    }

    private func push() {
        setKnownZappers(zappersJson: JSON.string(entries.mapValues(\.zapper)))
    }

    private static func zapper(from params: LnurlPayParams) -> String {
        guard params.allowsNostr, let key = params.nostrPubkey?.lowercased(), key.count == 64, key.allSatisfy(\.isHexDigit) else { return "" }
        return key
    }

    private static func address(for pubkey: String) async -> String? {
        let raw = JSON.object(try? await dbGetProfile(pubkeyHex: pubkey))
        let lud16 = raw?.str("lud16")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if Lnurl.isLightningAddress(lud16) { return lud16 }
        let lud06 = (raw?.str("lud06") ?? lud16).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lud06.hasPrefix("lnurl1") ? lud06 : nil
    }
}
