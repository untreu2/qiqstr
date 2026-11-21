import Foundation

private actor PrimalCacheClient {
    static let shared = PrimalCacheClient()

    private struct Pending {
        var events: [JSONObject] = []
        var continuation: CheckedContinuation<[JSONObject], Never>
        var watchdog: Task<Void, Never>?
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private var socket: URLSessionWebSocketTask?
    private var readerTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var pending: [String: Pending] = [:]
    private var nextId: UInt64 = 0

    func request(_ name: String, args: JSONObject, timeout: Int) async -> [JSONObject] {
        guard let url = URL(string: RelayConfig.primalCacheUrl) else { return [] }
        idleTask?.cancel()
        idleTask = nil

        nextId &+= 1
        let subId = "qx_\(nextId)"
        let payload = JSON.string(["REQ", subId, ["cache": [name, args]]] as [Any])

        return await withCheckedContinuation { continuation in
            let watchdog = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                await self?.timeoutSubscription(subId)
            }
            pending[subId] = Pending(continuation: continuation, watchdog: watchdog)
            Task { [weak self] in
                await self?.sendRequest(url: url, subId: subId, payload: payload)
            }
        }
    }

    private func sendRequest(url: URL, subId: String, payload: String) async {
        guard pending[subId] != nil else { return }
        let ws = ensureSocket(url: url)
        do {
            try await ws.send(.string(payload))
        } catch {
            resetSocket()
            guard pending[subId] != nil else { return }
            let retryWs = ensureSocket(url: url)
            do {
                try await retryWs.send(.string(payload))
            } catch {
                finishSubscription(subId)
            }
        }
    }

    private func ensureSocket(url: URL) -> URLSessionWebSocketTask {
        if let existing = socket, existing.state == .running {
            return existing
        }
        resetSocket()
        let ws = session.webSocketTask(with: url)
        ws.maximumMessageSize = 8 * 1024 * 1024
        ws.resume()
        socket = ws
        readerTask = Task { [weak self] in
            await self?.readLoop(ws)
        }
        return ws
    }

    private func readLoop(_ ws: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            guard let message = try? await ws.receive() else {
                handleDisconnect(ws)
                return
            }
            guard case .string(let raw) = message,
                  let frame = JSON.any(raw) as? [Any],
                  let type = frame.first as? String,
                  frame.count >= 2,
                  let subId = frame[1] as? String else { continue }
            if type == "EVENT", frame.count >= 3, let event = frame[2] as? JSONObject {
                pending[subId]?.events.append(event)
            } else if type == "EOSE" || type == "CLOSED" || type == "NOTICE" {
                let closeFrame = JSON.string(["CLOSE", subId])
                Task { try? await ws.send(.string(closeFrame)) }
                finishSubscription(subId)
            }
        }
    }

    private func handleDisconnect(_ ws: URLSessionWebSocketTask) {
        guard socket === ws else { return }
        socket = nil
        readerTask?.cancel()
        readerTask = nil
        let ids = Array(pending.keys)
        for id in ids {
            finishSubscription(id)
        }
    }

    private func resetSocket() {
        readerTask?.cancel()
        readerTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
    }

    private func timeoutSubscription(_ subId: String) {
        if let ws = socket {
            let closeFrame = JSON.string(["CLOSE", subId])
            Task { try? await ws.send(.string(closeFrame)) }
        }
        finishSubscription(subId)
    }

    private func finishSubscription(_ subId: String) {
        guard let item = pending.removeValue(forKey: subId) else { return }
        item.watchdog?.cancel()
        item.continuation.resume(returning: item.events)
        scheduleIdleDisconnectIfNeeded()
    }

    private func scheduleIdleDisconnectIfNeeded() {
        guard pending.isEmpty else { return }
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            await self?.closeIfIdle()
        }
    }

    private func closeIfIdle() {
        guard pending.isEmpty else { return }
        resetSocket()
    }
}

nonisolated enum PrimalCache {
    static func request(_ name: String, args: JSONObject, timeout: Int) async -> [JSONObject] {
        await PrimalCacheClient.shared.request(name, args: args, timeout: timeout)
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
