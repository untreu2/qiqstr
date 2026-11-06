import SwiftUI
import UIKit

actor ImagePipeline {
    static let shared = ImagePipeline()
    private let cache = NSCache<NSString, UIImage>()
    private var tasks: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 50_000_000, diskCapacity: 400_000_000)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    init() { cache.countLimit = 400 }


    func image(for url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(url.absoluteString)#\(Int(maxPixel))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        if let task = tasks[url] { return await task.value }
        let task = Task<UIImage?, Never> {
            guard let (data, _) = try? await session.data(from: url) else { return nil }
            return await Task.detached { ImagePipeline.downsample(data, maxPixel: maxPixel) }.value
        }
        tasks[url] = task
        let image = await task.value
        tasks[url] = nil
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return UIImage(data: data) }
        let count = CGImageSourceGetCount(source)
        if count > 1 { return UIImage(data: data) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return UIImage(data: data) }
        return UIImage(cgImage: cg)
    }
}

struct RemoteImage<Placeholder: View>: View {
    let url: String?
    var maxPixel: CGFloat = 800
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: UIImage?
    @State private var failed = false

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
        .task(id: url) {
            image = nil
            guard let url, let u = URL(string: url), u.scheme?.hasPrefix("http") == true else { return }
            image = await ImagePipeline.shared.image(for: u, maxPixel: maxPixel)
        }
    }
}
