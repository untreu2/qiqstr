import Foundation
import Observation
import QiqstrCore

enum WalletBackendKind: String, Sendable {
    case nwc
}

struct WalletTransaction: Identifiable, Hashable, Sendable {
    var id: String
    var isIncoming: Bool
    var amountSats: Int
    var feesSats: Int
    var description: String?
    var invoice: String?
    var createdAt: Int
    var method: String

    var paymentHash: String? { invoice.flatMap { Bolt11.decode($0)?.paymentHash } }

    init(json j: JSONObject) {
        isIncoming = j.bool("isIncoming") || j.str("type") == "incoming"
        amountSats = j.int("amount")
        feesSats = j.int("fees_paid")
        description = j.str("description")
        invoice = j.str("invoice")
        createdAt = j.int("created_at")
        method = "lightning"
        id = invoice ?? "\(createdAt)-\(amountSats)-\(isIncoming)-\(description ?? "")"
    }
}

struct PaymentResult: Sendable {
    var preimage: String?
    var feesSats: Int
}

struct CreatedInvoice: Hashable, Sendable {
    var invoice: String
    var paymentHash: String?
    var amountSats: Int
    var description: String?
    var createdAt: Date
    var expiresAt: Date?
}

protocol WalletBackend: Sendable {
    var kind: WalletBackendKind { get }
    var lightningAddress: String? { get }
    var displayName: String? { get }
    func balanceSats() async throws -> Int
    func transactions(limit: Int, offset: Int) async throws -> [WalletTransaction]
    func payInvoice(_ invoice: String) async throws -> PaymentResult
    func makeInvoice(amountSats: Int, description: String?) async throws -> CreatedInvoice
}

struct NWCWalletBackend: WalletBackend {
    let uri: String
    let lightningAddress: String?
    let displayName: String?
    var kind: WalletBackendKind { .nwc }

    init(uri: String) throws {
        guard validateNwcUri(uri: uri) else { throw WalletError.invalidConnection }
        let info = JSON.object(try parseNwcUri(uri: uri)) ?? [:]
        self.uri = uri
        lightningAddress = info.str("lud16")
        displayName = info.strings("relays").first.flatMap { URL(string: $0)?.host() }
    }

    func balanceSats() async throws -> Int {
        let json = JSON.object(try await nwcGetBalance(nwcUri: uri)) ?? [:]
        return json.int("balance") / 1000
    }

    func transactions(limit: Int, offset: Int) async throws -> [WalletTransaction] {
        let raw = try await nwcListTransactions(nwcUri: uri, limit: UInt64(limit), offset: UInt64(offset))
        let list = (JSON.object(raw)?["transactions"] as? [JSONObject]) ?? []
        return list.map(WalletTransaction.init(json:))
    }

    func payInvoice(_ invoice: String) async throws -> PaymentResult {
        let json = JSON.object(try await nwcPayInvoice(nwcUri: uri, invoice: invoice)) ?? [:]
        return PaymentResult(preimage: json.str("preimage"), feesSats: json.int("fees_paid") / 1000)
    }

    func makeInvoice(amountSats: Int, description: String?) async throws -> CreatedInvoice {
        let raw = try await nwcMakeInvoice(nwcUri: uri, amountMsats: UInt64(amountSats) * 1000, description: description)
        let json = JSON.object(raw) ?? [:]
        guard let invoice = json.str("invoice") else { throw WalletError.emptyInvoice }
        let decoded = Bolt11.decode(invoice)
        return CreatedInvoice(
            invoice: invoice,
            paymentHash: json.str("payment_hash") ?? decoded?.paymentHash,
            amountSats: amountSats,
            description: description,
            createdAt: decoded?.createdAt ?? Date(),
            expiresAt: decoded?.expiresAt
        )
    }
}

enum WalletConnectionState: Equatable {
    case disconnected
    case connected
}

enum WalletError: LocalizedError, Equatable {
    case notConnected
    case invalidConnection
    case noAccount
    case emptyInvoice
    case invalidAmount
    case amountOutOfRange(min: Int, max: Int)
    case amountlessInvoice
    case invoiceExpired
    case invoiceAmountMismatch
    case unrecognized
    case lnurl(String)
    case resolveFailed
    case cashuTooSmall
    case nothingToMelt

    var errorDescription: String? {
        switch self {
        case .notConnected: L("pleaseConnectWalletFirst")
        case .invalidConnection: L("nwcInvalidConnectionString")
        case .noAccount: L("walletNoAccount")
        case .emptyInvoice: L("walletEmptyInvoice")
        case .invalidAmount: L("enterValidAmount")
        case .amountOutOfRange(let min, let max): L("walletAmountRange", ["min": Sats.format(min), "max": Sats.format(max)])
        case .amountlessInvoice: L("walletAmountlessInvoice")
        case .invoiceExpired: L("walletInvoiceExpired")
        case .invoiceAmountMismatch: L("walletInvoiceAmountMismatch")
        case .unrecognized: L("unrecognizedPaymentFormat")
        case .lnurl(let reason): reason
        case .resolveFailed: L("resolveAddressFailed")
        case .cashuTooSmall: L("walletCashuTooSmall")
        case .nothingToMelt: L("walletNothingToMelt")
        }
    }
}

@MainActor
@Observable
final class WalletService {
    static let shared = WalletService()

    static let transactionPageSize = 20

    private(set) var connectionState: WalletConnectionState = .disconnected
    private(set) var backend: WalletBackend?
    private(set) var balanceSats: Int?
    private(set) var balanceError: String?
    private(set) var isRefreshingBalance = false
    private(set) var transactions: [WalletTransaction] = []
    private(set) var isLoadingTransactions = false
    private(set) var hasLoadedTransactions = false
    private(set) var canLoadMoreTransactions = false
    private(set) var transactionsError: String?
    private(set) var cashuBalanceSats = 0
    private(set) var isRedeemingCashu = false
    private(set) var isPaying = false
    private(set) var lastPaymentAt: Date?
    var balanceHidden: Bool = UserDefaults.standard.bool(forKey: "wallet_balance_hidden") {
        didSet { UserDefaults.standard.set(balanceHidden, forKey: "wallet_balance_hidden") }
    }

    private var generation = 0

    var isConnected: Bool { connectionState == .connected && backend != nil }
    var lightningAddress: String? { backend?.lightningAddress }
    var walletName: String? { backend?.displayName }

    private func storageKey(_ pubkey: String) -> String { "nwc_uri_\(pubkey)" }

    func reset() {
        generation += 1
        connectionState = .disconnected
        backend = nil
        balanceSats = nil
        balanceError = nil
        isRefreshingBalance = false
        transactions = []
        isLoadingTransactions = false
        hasLoadedTransactions = false
        canLoadMoreTransactions = false
        transactionsError = nil
        cashuBalanceSats = 0
        isRedeemingCashu = false
        isPaying = false
        lastPaymentAt = nil
    }

    func load() async {
        guard let pubkey = Session.shared.pubkey else { return }
        guard let uri = Keychain.get(storageKey(pubkey)), let backend = try? NWCWalletBackend(uri: uri) else { return }
        self.backend = backend
        connectionState = .connected
        await refresh()
    }

    static func isWalletConnectURI(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("nostr+walletconnect://") || lower.hasPrefix("nostrwalletconnect://")
    }

    func validate(uri: String) -> Bool {
        validateNwcUri(uri: uri.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func connect(uri raw: String) async throws {
        guard let pubkey = Session.shared.pubkey else { throw WalletError.noAccount }
        let uri = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let backend = try NWCWalletBackend(uri: uri)
        Keychain.set(uri, for: storageKey(pubkey))
        generation += 1
        self.backend = backend
        connectionState = .connected
        balanceSats = nil
        transactions = []
        hasLoadedTransactions = false
        await refresh()
    }

    func disconnect() {
        if let pubkey = Session.shared.pubkey { Keychain.set(nil, for: storageKey(pubkey)) }
        reset()
    }

    func refresh() async {
        async let balance: Void = refreshBalance()
        async let txs: Void = loadTransactions()
        async let cashu: Void = refreshCashuBalance()
        _ = await (balance, txs, cashu)
    }

    func refreshBalance() async {
        guard let backend, !isRefreshingBalance else { return }
        let generation = generation
        isRefreshingBalance = true
        defer { if generation == self.generation { isRefreshingBalance = false } }
        do {
            let sats = try await backend.balanceSats()
            guard generation == self.generation else { return }
            balanceSats = sats
            balanceError = nil
        } catch {
            guard generation == self.generation else { return }
            balanceError = coreErrorMessage(error)
        }
    }

    func loadTransactions() async {
        guard let backend, !isLoadingTransactions else { return }
        let generation = generation
        isLoadingTransactions = true
        defer { if generation == self.generation { isLoadingTransactions = false } }
        do {
            let page = try await backend.transactions(limit: Self.transactionPageSize, offset: 0)
            guard generation == self.generation else { return }
            transactions = Self.sorted(page)
            canLoadMoreTransactions = page.count >= Self.transactionPageSize
            transactionsError = nil
        } catch {
            guard generation == self.generation else { return }
            transactionsError = coreErrorMessage(error)
        }
        hasLoadedTransactions = true
    }

    func loadMoreTransactions() async {
        guard let backend, canLoadMoreTransactions, !isLoadingTransactions else { return }
        let generation = generation
        isLoadingTransactions = true
        defer { if generation == self.generation { isLoadingTransactions = false } }
        do {
            let page = try await backend.transactions(limit: Self.transactionPageSize, offset: transactions.count)
            guard generation == self.generation else { return }
            let known = Set(transactions.map(\.id))
            transactions = Self.sorted(transactions + page.filter { !known.contains($0.id) })
            canLoadMoreTransactions = page.count >= Self.transactionPageSize
        } catch {
            guard generation == self.generation else { return }
            ToastCenter.shared.error(error)
        }
    }

    private static func sorted(_ list: [WalletTransaction]) -> [WalletTransaction] {
        list.sorted { $0.createdAt > $1.createdAt }
    }

    func refreshCashuBalance() async {
        let generation = generation
        guard let json = JSON.object(try? await cashuGetBalance()) else { return }
        guard generation == self.generation else { return }
        cashuBalanceSats = json.int("total_sats")
    }

    func resolve(_ text: String) -> PaymentRequest? { PaymentRequest.parse(text) }

    @discardableResult
    func pay(invoice input: String, amountSats: Int? = nil, comment: String? = nil) async throws -> PaymentResult {
        guard let request = PaymentRequest.parse(input) else { throw WalletError.unrecognized }
        switch request {
        case .bolt11(let invoice, _):
            return try await payBolt11(invoice)
        case .lightningAddress(let address):
            let params = try await Lnurl.payParams(address: address)
            return try await pay(params: params, amountSats: amountSats, comment: comment)
        case .lnurl(let url):
            let params = try await Lnurl.payParams(url: url)
            return try await pay(params: params, amountSats: amountSats, comment: comment)
        case .cashu:
            throw WalletError.unrecognized
        }
    }

    func pay(params: LnurlPayParams, amountSats: Int?, comment: String?) async throws -> PaymentResult {
        guard let amountSats, amountSats > 0 else { throw WalletError.invalidAmount }
        let invoice = try await Lnurl.requestInvoice(params, amountMsat: Int64(amountSats) * 1000, comment: comment)
        return try await payBolt11(invoice)
    }

    @discardableResult
    func payBolt11(_ invoice: String) async throws -> PaymentResult {
        guard let backend else { throw WalletError.notConnected }
        let trimmed = invoice.trimmingCharacters(in: .whitespacesAndNewlines)
        if let decoded = Bolt11.decode(trimmed) {
            if decoded.amountMsat == nil { throw WalletError.amountlessInvoice }
            if decoded.isExpired { throw WalletError.invoiceExpired }
        }
        let generation = generation
        isPaying = true
        defer { if generation == self.generation { isPaying = false } }
        let result = try await backend.payInvoice(trimmed)
        guard generation == self.generation else { return result }
        lastPaymentAt = Date()
        Task {
            await refreshBalance()
            await loadTransactions()
        }
        return result
    }

    func makeInvoice(amount: Int, description: String?) async throws -> CreatedInvoice {
        guard let backend else { throw WalletError.notConnected }
        guard amount > 0 else { throw WalletError.invalidAmount }
        let memo = description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return try await backend.makeInvoice(amountSats: amount, description: memo)
    }

    func isInvoicePaid(_ invoice: CreatedInvoice) async -> Bool {
        guard let backend, let page = try? await backend.transactions(limit: 10, offset: 0) else { return false }
        let target = invoice.invoice.lowercased()
        let since = Int(invoice.createdAt.timeIntervalSince1970) - 5
        let paid = page.contains { tx in
            guard tx.isIncoming else { return false }
            if let txInvoice = tx.invoice?.lowercased() { return txInvoice == target }
            if let hash = invoice.paymentHash, let txHash = tx.paymentHash { return hash == txHash }
            return tx.amountSats == invoice.amountSats && tx.createdAt >= since
        }
        if paid {
            transactions = Self.sorted(page + transactions.filter { old in !page.contains { $0.id == old.id } })
            Task { await refreshBalance() }
        }
        return paid
    }

    func decodeCashu(_ token: String) -> CashuTokenInfo? {
        CashuTokenInfo.decode(token)
    }

    func redeemCashu(token raw: String) async throws -> Int {
        guard isConnected else { throw WalletError.notConnected }
        guard let info = CashuTokenInfo.decode(raw) else { throw CoreError(L("cashuInvalidToken")) }
        isRedeemingCashu = true
        defer { isRedeemingCashu = false }
        let token = info.token
        do {
            let target = try await lightningTarget(forSats: info.amountSats, attempt: 0)
            let json = JSON.object(try await cashuReceiveAndMelt(token: token, lightningTarget: target)) ?? [:]
            await afterCashuMelt()
            return json.int("amount_sats")
        } catch {
            await refreshCashuBalance()
            guard cashuBalanceSats > 0, lightningAddress == nil else { throw error }
            let melted = try await meltCashuViaInvoices(startAttempt: 1)
            await afterCashuMelt()
            return melted
        }
    }

    func meltAllCashu() async throws -> Int {
        guard isConnected else { throw WalletError.notConnected }
        isRedeemingCashu = true
        defer { isRedeemingCashu = false }
        do {
            let melted: Int
            if let address = lightningAddress {
                let json = JSON.object(try await cashuMeltAll(lightningTarget: address)) ?? [:]
                melted = json.int("total_sats")
            } else {
                melted = try await meltCashuViaInvoices(startAttempt: 0)
            }
            await afterCashuMelt()
            return melted
        } catch {
            await refreshCashuBalance()
            throw error
        }
    }

    private func afterCashuMelt() async {
        await refreshCashuBalance()
        Task {
            try? await Task.sleep(for: .seconds(2))
            await refresh()
        }
    }

    private func meltCashuViaInvoices(startAttempt: Int) async throws -> Int {
        var lastError: Error = WalletError.nothingToMelt
        for attempt in startAttempt..<4 {
            await refreshCashuBalance()
            guard cashuBalanceSats > 0 else { throw lastError }
            do {
                let target = try await lightningTarget(forSats: cashuBalanceSats, attempt: attempt)
                let json = JSON.object(try await cashuMeltAll(lightningTarget: target)) ?? [:]
                return json.int("total_sats")
            } catch WalletError.cashuTooSmall {
                throw WalletError.cashuTooSmall
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func lightningTarget(forSats sats: Int, attempt: Int) async throws -> String {
        if let address = lightningAddress { return address }
        let percent = [1, 2, 4, 8][min(attempt, 3)]
        let buffer = max(2 << attempt, (sats * percent + 99) / 100)
        let amount = sats - buffer
        guard amount > 0 else { throw WalletError.cashuTooSmall }
        return try await makeInvoice(amount: amount, description: L("cashuToken")).invoice
    }
}

struct CashuTokenInfo: Hashable, Sendable {
    var token: String
    var mintUrl: String
    var amountSats: Int

    static func normalized(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("cashu:") { s = String(s.dropFirst(6)) }
        return s
    }

    static func looksLikeToken(_ text: String) -> Bool {
        let s = normalized(text)
        return s.hasPrefix("cashuA") || s.hasPrefix("cashuB")
    }

    static func decode(_ text: String) -> CashuTokenInfo? {
        let token = normalized(text)
        guard looksLikeToken(token), let json = JSON.object(try? cashuDecodeToken(token: token)) else { return nil }
        return CashuTokenInfo(token: token, mintUrl: json.str("mint_url") ?? "", amountSats: json.int("amount_sats"))
    }
}

enum PaymentRequest: Hashable {
    case bolt11(String, Bolt11Invoice)
    case lightningAddress(String)
    case lnurl(URL)
    case cashu(CashuTokenInfo)

    var needsAmount: Bool {
        switch self {
        case .bolt11(_, let invoice): invoice.amountMsat == nil
        case .lightningAddress, .lnurl: true
        case .cashu: false
        }
    }

    static func parse(_ text: String) -> PaymentRequest? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if CashuTokenInfo.looksLikeToken(s) {
            return CashuTokenInfo.decode(s).map { .cashu($0) }
        }
        if s.lowercased().hasPrefix("bitcoin:"), let comps = URLComponents(string: s),
           let ln = comps.queryItems?.first(where: { $0.name.lowercased() == "lightning" })?.value {
            s = ln
        }
        if s.lowercased().hasPrefix("lightning:") { s = String(s.dropFirst(10)) }
        if s.hasPrefix("//") { s = String(s.dropFirst(2)) }
        let lower = s.lowercased()
        if lower.hasPrefix("lnurl1") {
            return Lnurl.decode(lower).map { .lnurl($0) }
        }
        if lower.hasPrefix("lnurlp://"), let url = URL(string: "https://" + s.dropFirst(9)) {
            return .lnurl(url)
        }
        if lower.hasPrefix("ln"), let invoice = Bolt11.decode(lower) {
            return .bolt11(lower, invoice)
        }
        if Lnurl.isLightningAddress(s) {
            return .lightningAddress(lower)
        }
        return nil
    }
}

struct LnurlPayParams: Hashable, Sendable {
    var callback: URL
    var minSendableMsat: Int64
    var maxSendableMsat: Int64
    var commentAllowed: Int
    var allowsNostr: Bool
    var nostrPubkey: String?
    var description: String?
    var lnurl: String
    var domain: String

    var minSats: Int { Int((minSendableMsat + 999) / 1000) }
    var maxSats: Int { Int(maxSendableMsat / 1000) }
    var isFixedAmount: Bool { minSendableMsat == maxSendableMsat }
}

enum Lnurl {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private static let queryValueAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    static func isLightningAddress(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".") && !domain.contains(" ") && !parts[0].contains(" ")
    }

    static func wellKnownURL(address: String) -> URL? {
        let parts = address.lowercased().split(separator: "@")
        guard parts.count == 2 else { return nil }
        let domain = String(parts[1])
        let scheme = domain.hasSuffix(".onion") ? "http" : "https"
        return URL(string: "\(scheme)://\(domain)/.well-known/lnurlp/\(parts[0])")
    }

    static func decode(_ bech32: String) -> URL? {
        guard let (hrp, data) = Bech32.decode(bech32), hrp == "lnurl",
              let bytes = Bech32.convertBits(data, from: 5, to: 8, pad: false),
              let string = String(bytes: bytes, encoding: .utf8) else { return nil }
        return URL(string: string)
    }

    static func encode(_ url: URL) -> String? {
        guard let words = Bech32.convertBits(Array(url.absoluteString.utf8), from: 8, to: 5, pad: true) else { return nil }
        return Bech32.encode(hrp: "lnurl", data: words)
    }

    static func payParams(address: String) async throws -> LnurlPayParams {
        guard let url = wellKnownURL(address: address) else { throw WalletError.resolveFailed }
        return try await payParams(url: url)
    }

    static func payParams(url: URL) async throws -> LnurlPayParams {
        let json = try await fetchJSON(url)
        guard json.str("tag") == "payRequest", let callbackString = json.str("callback"), let callback = URL(string: callbackString) else {
            throw WalletError.resolveFailed
        }
        let metadata = JSON.any(json.str("metadata")) as? [[Any]] ?? []
        let description = metadata.first { ($0.first as? String) == "text/plain" }.flatMap { $0.count > 1 ? $0[1] as? String : nil }
        return LnurlPayParams(
            callback: callback,
            minSendableMsat: int64(json["minSendable"]) ?? 1000,
            maxSendableMsat: int64(json["maxSendable"]) ?? 100_000_000_000,
            commentAllowed: json.int("commentAllowed"),
            allowsNostr: json.bool("allowsNostr"),
            nostrPubkey: json.str("nostrPubkey"),
            description: description,
            lnurl: encode(url) ?? url.absoluteString,
            domain: url.host() ?? ""
        )
    }

    static func requestInvoice(_ params: LnurlPayParams, amountMsat: Int64, comment: String? = nil, zapRequest: String? = nil) async throws -> String {
        guard amountMsat >= params.minSendableMsat, amountMsat <= params.maxSendableMsat else {
            throw WalletError.amountOutOfRange(min: params.minSats, max: params.maxSats)
        }
        guard var comps = URLComponents(url: params.callback, resolvingAgainstBaseURL: false) else { throw WalletError.resolveFailed }
        var items = comps.percentEncodedQueryItems ?? []
        func add(_ name: String, _ value: String) {
            items.append(URLQueryItem(name: name, value: value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed)))
        }
        add("amount", String(amountMsat))
        if let zapRequest {
            add("nostr", zapRequest)
            add("lnurl", params.lnurl)
        } else if let comment = comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty, params.commentAllowed > 0 {
            add("comment", String(comment.prefix(params.commentAllowed)))
        }
        comps.percentEncodedQueryItems = items
        guard let url = comps.url else { throw WalletError.resolveFailed }
        let json = try await fetchJSON(url)
        guard let pr = json.str("pr") else { throw WalletError.emptyInvoice }
        if let decoded = Bolt11.decode(pr), let amount = decoded.amountMsat, amount != amountMsat {
            throw WalletError.invoiceAmountMismatch
        }
        return pr
    }

    private static func fetchJSON(_ url: URL) async throws -> JSONObject {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw WalletError.resolveFailed
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject
        if let json, json.str("status")?.uppercased() == "ERROR" {
            throw WalletError.lnurl(json.str("reason") ?? L("resolveAddressFailed"))
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let json else {
            throw WalletError.resolveFailed
        }
        return json
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let n = value as? NSNumber { return n.int64Value }
        if let s = value as? String { return Int64(s) }
        return nil
    }
}

struct Bolt11Invoice: Hashable, Sendable {
    var network: String
    var amountMsat: Int64?
    var createdAt: Date
    var expirySeconds: Int
    var paymentHash: String?
    var description: String?
    var descriptionHash: String?
    var payeePubkey: String?

    var amountSats: Int? { amountMsat.map { Int($0 / 1000) } }
    var expiresAt: Date { createdAt.addingTimeInterval(TimeInterval(expirySeconds)) }
    var isExpired: Bool { expiresAt < Date() }
    var isMainnet: Bool { network == "bc" }
}

enum Bolt11 {
    static func decode(_ raw: String) -> Bolt11Invoice? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("lightning:") { s = String(s.dropFirst(10)) }
        guard s.hasPrefix("ln"), let (hrp, words) = Bech32.decode(s), words.count > 7 + 104 else { return nil }
        let hrpBody = hrp.dropFirst(2)
        guard let digitStart = hrpBody.firstIndex(where: \.isNumber) else {
            return parse(words, network: String(hrpBody), amountMsat: nil)
        }
        let network = String(hrpBody[..<digitStart])
        var amountPart = String(hrpBody[digitStart...])
        var multiplier: Character?
        if let last = amountPart.last, "munp".contains(last) {
            multiplier = last
            amountPart.removeLast()
        }
        guard let value = Int64(amountPart) else { return nil }
        let msat: Int64?
        switch multiplier {
        case "m": msat = value.multipliedReportingOverflow(by: 100_000_000).overflow ? nil : value * 100_000_000
        case "u": msat = value.multipliedReportingOverflow(by: 100_000).overflow ? nil : value * 100_000
        case "n": msat = value.multipliedReportingOverflow(by: 100).overflow ? nil : value * 100
        case "p": msat = value % 10 == 0 ? value / 10 : nil
        default: msat = value.multipliedReportingOverflow(by: 100_000_000_000).overflow ? nil : value * 100_000_000_000
        }
        guard let msat else { return nil }
        return parse(words, network: network, amountMsat: msat)
    }

    private static func parse(_ words: [UInt8], network: String, amountMsat: Int64?) -> Bolt11Invoice? {
        let payload = Array(words.dropLast(104))
        guard payload.count >= 7 else { return nil }
        let timestamp = number(payload[0..<7])
        var invoice = Bolt11Invoice(network: network, amountMsat: amountMsat, createdAt: Date(timeIntervalSince1970: TimeInterval(timestamp)), expirySeconds: 3600)
        var i = 7
        while i + 3 <= payload.count {
            let type = payload[i]
            let length = Int(payload[i + 1]) * 32 + Int(payload[i + 2])
            let start = i + 3
            let end = start + length
            guard end <= payload.count else { break }
            let field = Array(payload[start..<end])
            switch type {
            case 1 where length == 52: invoice.paymentHash = hex(field)
            case 13: invoice.description = Bech32.convertBits(field, from: 5, to: 8, pad: false).flatMap { String(bytes: $0, encoding: .utf8) }
            case 23 where length == 52: invoice.descriptionHash = hex(field)
            case 6: invoice.expirySeconds = Int(number(field[...]))
            case 19 where length == 53: invoice.payeePubkey = hex(field)
            default: break
            }
            i = end
        }
        return invoice
    }

    private static func number(_ words: ArraySlice<UInt8>) -> Int64 {
        words.prefix(12).reduce(Int64(0)) { $0 * 32 + Int64($1) }
    }

    private static func hex(_ words: [UInt8]) -> String? {
        Bech32.convertBits(words, from: 5, to: 8, pad: false).map { $0.map { String(format: "%02x", $0) }.joined() }
    }
}

enum Bech32 {
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let lookup: [Character: UInt8] = Dictionary(uniqueKeysWithValues: charset.enumerated().map { ($1, UInt8($0)) })

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        let generators: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var chk: UInt32 = 1
        for v in values {
            let top = chk >> 25
            chk = ((chk & 0x1ffffff) << 5) ^ UInt32(v)
            for i in 0..<5 where (top >> UInt32(i)) & 1 == 1 { chk ^= generators[i] }
        }
        return chk
    }

    private static func expand(_ hrp: String) -> [UInt8] {
        let bytes = Array(hrp.utf8)
        return bytes.map { $0 >> 5 } + [0] + bytes.map { $0 & 31 }
    }

    static func decode(_ string: String) -> (String, [UInt8])? {
        let s = string.lowercased()
        guard let separator = s.lastIndex(of: "1") else { return nil }
        let hrp = String(s[..<separator])
        let dataPart = s[s.index(after: separator)...]
        guard !hrp.isEmpty, dataPart.count >= 6 else { return nil }
        var data: [UInt8] = []
        data.reserveCapacity(dataPart.count)
        for c in dataPart {
            guard let v = lookup[c] else { return nil }
            data.append(v)
        }
        guard polymod(expand(hrp) + data) == 1 else { return nil }
        return (hrp, Array(data.dropLast(6)))
    }

    static func encode(hrp: String, data: [UInt8]) -> String {
        let values = expand(hrp) + data + [0, 0, 0, 0, 0, 0]
        let mod = polymod(values) ^ 1
        let checksum = (0..<6).map { UInt8((mod >> (5 * (5 - UInt32($0)))) & 31) }
        return hrp + "1" + String((data + checksum).map { charset[Int($0)] })
    }

    static func convertBits(_ data: [UInt8], from: Int, to: Int, pad: Bool) -> [UInt8]? {
        var acc = 0
        var bits = 0
        var out: [UInt8] = []
        let maxv = (1 << to) - 1
        for value in data {
            let v = Int(value)
            guard v >> from == 0 else { return nil }
            acc = (acc << from) | v
            bits += from
            while bits >= to {
                bits -= to
                out.append(UInt8((acc >> bits) & maxv))
            }
        }
        if pad, bits > 0 { out.append(UInt8((acc << (to - bits)) & maxv)) }
        if !pad, bits >= from { return nil }
        return out
    }
}
