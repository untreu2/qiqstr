import Foundation
import Observation

@MainActor
@Observable
final class WalletService {
    static let shared = WalletService()

    func reset() {}
    func load() async {}
}
