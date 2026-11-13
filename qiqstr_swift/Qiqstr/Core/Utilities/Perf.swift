import Foundation
import os

nonisolated enum Perf {
    static let signposter = OSSignposter(subsystem: "me.untreu.qiqstrswift", category: .pointsOfInterest)
    private static let launch = signposter.beginInterval("Launch to first feed", id: signposter.makeSignpostID())
    private static let firstFeed = OSAllocatedUnfairLock(initialState: false)

    static func start() {
        _ = launch
    }

    static func feedShown(count: Int) {
        guard count > 0, firstFeed.withLock({ done in
            defer { done = true }
            return !done
        }) else { return }
        signposter.endInterval("Launch to first feed", launch, "\(count) notes")
    }

    static func measure<T>(_ name: StaticString, _ work: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(name, state) }
        return try await work()
    }
}
