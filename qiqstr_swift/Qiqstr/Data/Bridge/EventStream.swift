import Foundation
import QiqstrCore

final class StreamSinkBridge: EventSink, @unchecked Sendable {
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private let lock = NSLock()
    private var closed = false

    init(_ continuation: AsyncThrowingStream<String, Error>.Continuation) {
        self.continuation = continuation
    }

    func close() {
        lock.lock(); closed = true; lock.unlock()
    }

    func onItem(item: String) -> Bool {
        lock.lock(); let isClosed = closed; lock.unlock()
        if isClosed { return false }
        if case .terminated = continuation.yield(item) { close(); return false }
        return true
    }

    func onError(message: String) {
        continuation.finish(throwing: CoreError(message))
    }

    func onDone() {
        continuation.finish()
    }

    func isClosed() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return closed
    }
}

enum EventStream {
    static func make(_ start: @escaping @Sendable (EventSink) async throws -> Void) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let sink = StreamSinkBridge(continuation)
            let task = Task.detached {
                do {
                    try await start(sink)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                sink.close()
                task.cancel()
            }
        }
    }
}

