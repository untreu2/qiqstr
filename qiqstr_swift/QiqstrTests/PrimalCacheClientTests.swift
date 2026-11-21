import Network
import XCTest
@testable import qiqstr

nonisolated final class ScriptedSocketServer: @unchecked Sendable {
    enum Reaction {
        case answer([JSONObject])
        case ignore
        case hangUp
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "scripted-socket-server")
    private let react: @Sendable (_ connection: Int, _ request: Int) -> Reaction
    private var connections: [NWConnection] = []
    private var requestCount = 0
    private var closes: [String: Int] = [:]

    var url: URL { URL(string: "ws://127.0.0.1:\(listener.port?.rawValue ?? 0)")! }
    var connectionCount: Int { queue.sync { connections.count } }
    func closeCount(_ subId: String) -> Int { queue.sync { closes[subId] ?? 0 } }
    var closeCounts: [Int] { queue.sync { Array(closes.values) } }

    init(react: @escaping @Sendable (_ connection: Int, _ request: Int) -> Reaction) throws {
        self.react = react
        let parameters = NWParameters.tcp
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        listener = try NWListener(using: parameters, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            let index = self.connections.count
            self.connections.append(connection)
            connection.start(queue: self.queue)
            self.receive(on: connection, index: index)
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
    }

    func stop() {
        queue.sync {
            connections.forEach { $0.cancel() }
            listener.cancel()
        }
    }

    private func receive(on connection: NWConnection, index: Int) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, error == nil, let data else { return }
            if let frame = (try? JSONSerialization.jsonObject(with: data)) as? [Any], let type = frame.first as? String, frame.count > 1, let subId = frame[1] as? String {
                if type == "CLOSE" {
                    self.closes[subId, default: 0] += 1
                } else if type == "REQ" {
                    let request = self.requestCount
                    self.requestCount += 1
                    switch self.react(index, request) {
                    case .ignore: break
                    case .hangUp:
                        connection.cancel()
                        return
                    case .answer(let events):
                        for event in events { self.send(["EVENT", subId, event], on: connection) }
                        self.send(["EOSE", subId], on: connection)
                    }
                }
            }
            self.receive(on: connection, index: index)
        }
    }

    private func send(_ frame: [Any], on connection: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: frame) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }
}

nonisolated enum CachedFixture {
    static func event() -> JSONObject { ["kind": 1, "content": "cached"] }
}

final class PrimalCacheClientTests: XCTestCase {
    func testAConnectionThatWentQuietIsReplacedAfterATimeout() async throws {
        let server = try ScriptedSocketServer { connection, _ in connection == 0 ? .ignore : .answer([CachedFixture.event()]) }
        defer { server.stop() }
        let client = PrimalCacheClient(url: server.url)

        let stalled = await client.request("feed", args: [:], timeout: 1)
        XCTAssertTrue(stalled.isEmpty)
        XCTAssertEqual(server.connectionCount, 1)

        let started = ContinuousClock.now
        let answered = await client.request("feed", args: [:], timeout: 5)
        XCTAssertEqual(answered.count, 1)
        XCTAssertEqual(server.connectionCount, 2)
        XCTAssertLessThan(started.duration(to: .now), .seconds(3))
    }

    func testAnAnsweredRequestIsClosedExactlyOnce() async throws {
        let server = try ScriptedSocketServer { _, _ in .answer([CachedFixture.event()]) }
        defer { server.stop() }
        let client = PrimalCacheClient(url: server.url)

        for _ in 0..<3 {
            let answered = await client.request("feed", args: [:], timeout: 5)
            XCTAssertEqual(answered.count, 1)
        }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(server.closeCounts.sorted(), [1, 1, 1])
        XCTAssertEqual(server.connectionCount, 1)
    }

    func testRequestsWaitingOnAConnectionThatDropsAreAnsweredOnANewOne() async throws {
        let server = try ScriptedSocketServer { connection, request in
            if connection == 0 { return request == 0 ? .ignore : .hangUp }
            return .answer([CachedFixture.event()])
        }
        defer { server.stop() }
        let client = PrimalCacheClient(url: server.url)

        async let first = client.request("first", args: [:], timeout: 6)
        try await Task.sleep(for: .milliseconds(300))
        async let second = client.request("second", args: [:], timeout: 6)
        let started = ContinuousClock.now
        let (a, b) = await (first, second)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(b.count, 1)
        XCTAssertGreaterThanOrEqual(server.connectionCount, 2)
        XCTAssertLessThan(started.duration(to: .now), .seconds(4))
    }

    func testARequestThatKeepsLosingItsConnectionEndsInsteadOfRetryingForever() async throws {
        let server = try ScriptedSocketServer { _, _ in .hangUp }
        defer { server.stop() }
        let client = PrimalCacheClient(url: server.url)

        let started = ContinuousClock.now
        let result = await client.request("feed", args: [:], timeout: 8)
        XCTAssertTrue(result.isEmpty)
        XCTAssertLessThan(started.duration(to: .now), .seconds(4))
        XCTAssertLessThanOrEqual(server.connectionCount, 2)
    }
}
