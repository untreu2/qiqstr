import SwiftUI
import UIKit

actor ImagePipeline {
    static let shared = ImagePipeline()
    private let cache = NSCache<NSString, UIImage>()
    private var tasks: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 50_000_000, diskCapacity: 400_000_000)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private static let maxDownloadBytes = 30 * 1024 * 1024

    init() {
        cache.countLimit = 400
        cache.totalCostLimit = 160 * 1024 * 1024
    }


    func image(for url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(url.absoluteString)#\(maxPixel)"
        if let hit = cache.object(forKey: key as NSString) { return hit }
        if let task = tasks[key] { return await task.value }
        let task = Task<UIImage?, Never> {
            guard let data = await download(url) else { return nil }
            return await Task.detached { ImagePipeline.downsample(data, maxPixel: maxPixel) }.value
        }
        tasks[key] = task
        let image = await task.value
        tasks[key] = nil
        if let image, let cg = image.cgImage { cache.setObject(image, forKey: key as NSString, cost: cg.bytesPerRow * cg.height) }
        return image
    }

    private func download(_ url: URL) async -> Data? {
        if let cached = session.configuration.urlCache?.cachedResponse(for: URLRequest(url: url))?.data { return cached }
        guard let (file, response) = try? await session.download(from: url) else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0, size <= Self.maxDownloadBytes, let data = try? Data(contentsOf: file) else { return nil }
        session.configuration.urlCache?.storeCachedResponse(CachedURLResponse(response: response, data: data), for: URLRequest(url: url))
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

    var body: some View {
        Group {
            if let image {
                if contentMode == .fill {
                    Color.clear
                        .overlay { Image(uiImage: image).resizable().aspectRatio(contentMode: .fill) }
                        .clipped()
                } else {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                }
            } else {
                placeholder()
            }
        }
        .task(id: "\(url ?? "")#\(maxPixel)") {
            image = nil
            guard let url, let u = URL(string: url), u.scheme?.hasPrefix("http") == true else { return }
            let loaded = await ImagePipeline.shared.image(for: u, maxPixel: maxPixel)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
