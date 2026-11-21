import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

actor ImagePipeline {
    static let shared = ImagePipeline()
    nonisolated private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 400
        c.totalCostLimit = 160 * 1024 * 1024
        return c
    }()
    private var tasks: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 50_000_000, diskCapacity: 400_000_000)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 8
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private static let maxDownloadBytes = 30 * 1024 * 1024

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
        if let cached = session.configuration.urlCache?.cachedResponse(for: request)?.data { return cached }
        guard let (data, response) = try? await session.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        guard !data.isEmpty, data.count <= Self.maxDownloadBytes else { return nil }
        session.configuration.urlCache?.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
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
