import Foundation
import Observation

@MainActor
@Observable
final class DMService {
    static let shared = DMService()

    func reset() {}
    func start() async {}
}
