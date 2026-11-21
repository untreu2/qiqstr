import Foundation

actor PrimalCacheClient {
    static let shared = PrimalCacheClient(url: URL(string: RelayConfig.primalCacheUrl))

    private struct Pending {
        var payload: String
        var events: [JSONObject] = []
        var continuation: CheckedContinuation<[JSONObject], Never>
        var watchdog: Task<Void, Never>?
        var socket: ObjectIdentifier?
        var framesAtSend: UInt64 = 0
        var resent = false
    }

    private let url: URL?
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
    private var framesReceived: UInt64 = 0

    init(url: URL?) {
        self.url = url
    }

    func request(_ name: String, args: JSONObject, timeout: Int) async -> [JSONObject] {
        guard url != nil else { return [] }
        idleTask?.cancel()
        idleTask = nil

        nextId &+= 1
        let subId = "qx_\(nextId)"
        let payload = JSON.string(["REQ", subId, ["cache": [name, args]]] as [Any])

        return await withCheckedContinuation { continuation in
            let watchdog = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                await self?.timeOut(subId)
            }
            pending[subId] = Pending(payload: payload, continuation: continuation, watchdog: watchdog)
            Task { [weak self] in
                await self?.send(subId)
            }
        }
    }

    private func send(_ subId: String) async {
        guard let url, let payload = pending[subId]?.payload else { return }
        let ws = ensureSocket(url: url)
        pending[subId]?.socket = ObjectIdentifier(ws)
        pending[subId]?.framesAtSend = framesReceived
        do {
            try await ws.send(.string(payload))
        } catch {
            socketFailed(ws)
        }
    }

    private func ensureSocket(url: URL) -> URLSessionWebSocketTask {
        if let existing = socket, existing.state == .running {
            return existing
        }
        dropSocket()
        let ws = session.webSocketTask(with: url)
        ws.maximumMessageSize = 8 * 1024 * 1024
        ws.resume()
        socket = ws
        framesReceived = 0
        readerTask = Task { [weak self] in
            await self?.readLoop(ws)
        }
        return ws
    }

    private func readLoop(_ ws: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            guard let message = try? await ws.receive() else {
                socketFailed(ws)
                return
            }
            if socket === ws { framesReceived &+= 1 }
            guard case .string(let raw) = message,
                  let frame = JSON.any(raw) as? [Any],
                  let type = frame.first as? String,
                  frame.count >= 2,
                  let subId = frame[1] as? String,
                  pending[subId] != nil else { continue }
            if type == "EVENT", frame.count >= 3, let event = frame[2] as? JSONObject {
                pending[subId]?.events.append(event)
            } else if type == "EOSE" || type == "CLOSED" || type == "NOTICE" {
                if type == "EOSE" { close(subId, on: ws) }
                finish(subId)
            }
        }
    }

    private func close(_ subId: String, on ws: URLSessionWebSocketTask) {
        let closeFrame = JSON.string(["CLOSE", subId])
        Task { try? await ws.send(.string(closeFrame)) }
    }

    private func socketFailed(_ ws: URLSessionWebSocketTask) {
        if socket === ws {
            readerTask?.cancel()
            readerTask = nil
            socket = nil
        }
        ws.cancel(with: .goingAway, reason: nil)
        let failed = ObjectIdentifier(ws)
        for subId in pending.filter({ $0.value.socket == failed }).map(\.key) {
            if pending[subId]?.resent == true {
                finish(subId)
            } else {
                pending[subId]?.resent = true
                pending[subId]?.socket = nil
                Task { [weak self] in
                    await self?.send(subId)
                }
            }
        }
    }

    private func dropSocket() {
        readerTask?.cancel()
        readerTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
    }

    private func timeOut(_ subId: String) {
        guard let item = pending[subId] else { return }
        let current = socket.flatMap { ObjectIdentifier($0) == item.socket ? $0 : nil }
        let heardNothing = current != nil && framesReceived == item.framesAtSend
        if let current, !heardNothing { close(subId, on: current) }
        finish(subId)
        if let current, heardNothing { socketFailed(current) }
    }

    private func finish(_ subId: String) {
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
        dropSocket()
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
