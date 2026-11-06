import Foundation

@MainActor
final class ZapService {
    static let shared = ZapService()

    var canZap: Bool { false }
    func zap(note: Note?, pubkey: String, amountSats: Int, comment: String) async throws {}
}
