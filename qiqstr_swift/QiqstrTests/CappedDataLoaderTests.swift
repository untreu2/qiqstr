import XCTest
@testable import qiqstr

nonisolated final class StreamedResponse: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var bodyBytes = 0
    nonisolated(unsafe) static var declaredLength: Int?
    nonisolated(unsafe) static var chunk = 64 * 1024
    private static let lock = NSLock()
    nonisolated(unsafe) private static var sentBytes = 0

    static var delivered: Int { lock.withLock { sentBytes } }

    static func reset(status: Int = 200, bodyBytes: Int, declaredLength: Int? = nil) {
        self.status = status
        self.bodyBytes = bodyBytes
        self.declaredLength = declaredLength
        lock.withLock { sentBytes = 0 }
    }

    private let stopped = NSLock()
    nonisolated(unsafe) private var isStopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var headers: [String: String] = ["Content-Type": "image/png"]
        if let declared = Self.declaredLength { headers["Content-Length"] = String(declared) }
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        DispatchQueue.global().async { [self] in
            var remaining = Self.bodyBytes
            while remaining > 0 {
                if stopped.withLock({ isStopped }) { return }
                let size = min(Self.chunk, remaining)
                client?.urlProtocol(self, didLoad: Data(count: size))
                Self.lock.withLock { Self.sentBytes += size }
                remaining -= size
                Thread.sleep(forTimeInterval: 0.001)
            }
            if stopped.withLock({ isStopped }) { return }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        stopped.withLock { isStopped = true }
    }
}

final class CappedDataLoaderTests: XCTestCase {
    private let limit = 512 * 1024

    private func makeLoader() -> CappedDataLoader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamedResponse.self]
        return CappedDataLoader(configuration: configuration, limit: limit)
    }

    private var request: URLRequest { URLRequest(url: URL(string: "https://images.example/picture.png")!) }

    func testABodyWithinTheLimitIsReturnedWhole() async {
        StreamedResponse.reset(bodyBytes: limit, declaredLength: limit)
        let result = await makeLoader().data(for: request)
        XCTAssertEqual(result?.0.count, limit)
        XCTAssertEqual((result?.1 as? HTTPURLResponse)?.statusCode, 200)

        StreamedResponse.reset(bodyBytes: 1_000)
        let undeclared = await makeLoader().data(for: request)
        XCTAssertEqual(undeclared?.0.count, 1_000)
    }

    func testADeclaredBodyOverTheLimitIsRefusedBeforeItIsDownloaded() async {
        StreamedResponse.reset(bodyBytes: limit * 40, declaredLength: limit * 40)
        let result = await makeLoader().data(for: request)
        XCTAssertNil(result)
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertLessThan(StreamedResponse.delivered, limit * 4)
    }

    func testAnUndeclaredBodyIsCutOffOnceItPassesTheLimit() async {
        StreamedResponse.reset(bodyBytes: limit * 40)
        let result = await makeLoader().data(for: request)
        XCTAssertNil(result)
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertLessThan(StreamedResponse.delivered, limit * 4)
    }

    func testFailedAndEmptyResponsesReturnNothing() async {
        StreamedResponse.reset(status: 404, bodyBytes: 100)
        let missing = await makeLoader().data(for: request)
        XCTAssertNil(missing)

        StreamedResponse.reset(bodyBytes: 0)
        let empty = await makeLoader().data(for: request)
        XCTAssertNil(empty)
    }

    func testTheImagePipelineKeepsItsThirtyMegabyteCeiling() {
        XCTAssertEqual(ImagePipeline.maxDownloadBytes, 30 * 1024 * 1024)
    }
}
