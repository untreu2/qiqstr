import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

nonisolated final class CappedDataLoader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct Transfer {
        var data = Data()
        var response: URLResponse?
        var rejected = false
        var continuation: CheckedContinuation<(Data, URLResponse)?, Never>
    }

    let limit: Int
    private(set) var session: URLSession!
    private let lock = NSLock()
    private var transfers: [Int: Transfer] = [:]

    init(configuration: URLSessionConfiguration, limit: Int) {
        self.limit = limit
        super.init()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func data(for request: URLRequest) async -> (Data, URLResponse)? {
        await withCheckedContinuation { continuation in
            let task = session.dataTask(with: request)
            lock.withLock { transfers[task.taskIdentifier] = Transfer(continuation: continuation) }
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let failed = (response as? HTTPURLResponse).map { !(200..<300).contains($0.statusCode) } ?? false
        guard !failed, response.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel)
            return
        }
        lock.withLock { transfers[dataTask.taskIdentifier]?.response = response }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let id = dataTask.taskIdentifier
        let exceeded = lock.withLock { () -> Bool in
            guard let received = transfers[id]?.data.count else { return false }
            guard received + data.count <= limit else {
                transfers[id]?.rejected = true
                transfers[id]?.data = Data()
                return true
            }
            transfers[id]?.data.append(data)
            return false
        }
        if exceeded { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let transfer = lock.withLock({ transfers.removeValue(forKey: task.taskIdentifier) }) else { return }
        guard error == nil, !transfer.rejected, !transfer.data.isEmpty, let response = transfer.response else {
            transfer.continuation.resume(returning: nil)
            return
        }
        transfer.continuation.resume(returning: (transfer.data, response))
    }
}

actor ImagePipeline {
    static let shared = ImagePipeline()
    nonisolated private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 400
        c.totalCostLimit = 160 * 1024 * 1024
        return c
    }()
    private var tasks: [String: Task<UIImage?, Never>] = [:]
    static let maxDownloadBytes = 30 * 1024 * 1024

    private let loader: CappedDataLoader = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 50_000_000, diskCapacity: 400_000_000)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 120
        config.httpMaximumConnectionsPerHost = 8
        config.waitsForConnectivity = false
        return CappedDataLoader(configuration: config, limit: ImagePipeline.maxDownloadBytes)
    }()

    nonisolated func cachedImage(for url: URL, maxPixel: CGFloat) -> UIImage? {
        cache.object(forKey: "\(url.absoluteString)#\(maxPixel)" as NSString)
    }

    func prefetch(urls: [String], maxPixel: CGFloat) {
        for raw in urls {
            guard let url = URL(string: raw), url.scheme?.hasPrefix("http") == true else { continue }
            let key = "\(url.absoluteString)#\(maxPixel)"
            if cache.object(forKey: key as NSString) != nil || tasks[key] != nil { continue }
            let task = Task<UIImage?, Never>(priority: .utility) {
                guard let data = await self.download(url) else { return nil }
                return await Task.detached(priority: .utility) { ImagePipeline.downsample(data, maxPixel: maxPixel) }.value
            }
            tasks[key] = task
            Task(priority: .utility) {
                let image = await task.value
                self.finishTask(key: key, image: image)
            }
        }
    }

    private func finishTask(key: String, image: UIImage?) {
        tasks[key] = nil
        if let image, let cg = image.cgImage {
            cache.setObject(image, forKey: key as NSString, cost: cg.bytesPerRow * cg.height)
        }
    }

    func image(for url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(url.absoluteString)#\(maxPixel)"
        if let hit = cache.object(forKey: key as NSString) { return hit }
        if let task = tasks[key] { return await task.value }
        let task = Task<UIImage?, Never> {
            guard let data = await download(url) else { return nil }
            return await Task.detached(priority: .userInitiated) { ImagePipeline.downsample(data, maxPixel: maxPixel) }.value
        }
        tasks[key] = task
        let image = await task.value
        finishTask(key: key, image: image)
        return image
    }

    func data(for url: URL) async -> Data? {
        await download(url)
    }

    private func download(_ url: URL) async -> Data? {
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        let cache = loader.session.configuration.urlCache
        if let cached = cache?.cachedResponse(for: request)?.data { return cached }
        guard let (data, response) = await loader.data(for: request) else { return nil }
        cache?.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
        return data
    }

    nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct RemoteImage<Placeholder: View>: View {
    let url: String?
    var maxPixel: CGFloat = 800
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: UIImage?
    @State private var loadedKey: String?

    private var currentKey: String { "\(url ?? "")#\(maxPixel)" }

    private var cachedHit: UIImage? {
        guard let url, let u = URL(string: url), u.scheme?.hasPrefix("http") == true else { return nil }
        return ImagePipeline.shared.cachedImage(for: u, maxPixel: maxPixel)
    }

    var body: some View {
        let resolved = (loadedKey == currentKey ? image : nil) ?? cachedHit
        Group {
            if let resolved {
                if contentMode == .fill {
                    Color.clear
                        .overlay { Image(uiImage: resolved).resizable().aspectRatio(contentMode: .fill) }
                        .clipped()
                } else {
                    Image(uiImage: resolved).resizable().aspectRatio(contentMode: .fit)
                }
            } else {
                placeholder()
            }
        }
        .task(id: currentKey) {
            let key = currentKey
            guard let url, let u = URL(string: url), u.scheme?.hasPrefix("http") == true else {
                image = nil
                loadedKey = key
                return
            }
            if let hit = ImagePipeline.shared.cachedImage(for: u, maxPixel: maxPixel) {
                image = hit
                loadedKey = key
                return
            }
            let loaded = await ImagePipeline.shared.image(for: u, maxPixel: maxPixel)
            guard !Task.isCancelled else { return }
            image = loaded
            loadedKey = key
        }
    }
}
