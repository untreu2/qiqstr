import Foundation

nonisolated enum PrimalCache {
    static func request(_ name: String, args: JSONObject, timeout: Int) async -> [JSONObject] {
        guard let url = URL(string: RelayConfig.primalCacheUrl) else { return [] }
        let socket = URLSession.shared.webSocketTask(with: url)
        socket.maximumMessageSize = 8 * 1024 * 1024
        socket.resume()
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(timeout))
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer {
            watchdog.cancel()
            socket.cancel(with: .normalClosure, reason: nil)
        }
        let subscription = "qx_\(UUID().uuidString.prefix(8))"
        let request: [Any] = ["REQ", subscription, ["cache": [name, args]]]
        do { try await socket.send(.string(JSON.string(request))) } catch { return [] }
        var events: [JSONObject] = []
        while !Task.isCancelled {
            guard let message = try? await socket.receive() else { break }
            guard case .string(let raw) = message, let frame = JSON.any(raw) as? [Any], let type = frame.first as? String else { continue }
            if type == "EOSE" || type == "CLOSED" || type == "NOTICE" { break }
            if type == "EVENT", frame.count >= 3, let event = frame[2] as? JSONObject { events.append(event) }
        }
        try? await socket.send(.string(JSON.string(["CLOSE", subscription])))
        return events
    }

    static func order(_ events: [JSONObject]) -> [String] {
        events.first { $0.int("kind") == 10000113 }
            .flatMap { JSON.object($0["content"] as? String) }
            .map { ($0["elements"] as? [String]) ?? [] } ?? []
    }

    static func page(_ events: [JSONObject]) -> (since: Int, until: Int)? {
        guard let info = events.first(where: { $0.int("kind") == 10000113 }).flatMap({ JSON.object($0["content"] as? String) }) else { return nil }
        return (info.int("since"), info.int("until"))
    }

    static func signed(_ events: [JSONObject], kinds: Set<Int>) -> [JSONObject] {
        events.filter { kinds.contains($0.int("kind")) && $0.str("id") != nil && $0.str("sig") != nil }
    }

    static func content(_ events: [JSONObject], kind: Int) -> Any? {
        events.first { $0.int("kind") == kind }.flatMap { JSON.any($0["content"] as? String) }
    }

    static func contents(_ events: [JSONObject], kind: Int) -> [JSONObject] {
        events.filter { $0.int("kind") == kind }.compactMap { JSON.object($0["content"] as? String) }
    }
}
