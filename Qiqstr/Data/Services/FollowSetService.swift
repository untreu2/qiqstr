import Foundation
import Observation

@MainActor
@Observable
final class FollowSetService {
    static let shared = FollowSetService()

    func reset() {}
    func load() async {}
}
