import ImageIO
import UIKit

nonisolated struct SharedImage: Identifiable, Sendable {
    let id = UUID()
    let data: Data
    let thumbnail: UIImage

    init?(source data: Data, maxPixelSize: Int = 2048) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let full = UIImage(cgImage: image)
        guard let jpeg = full.jpegData(compressionQuality: 0.85) else { return nil }
        self.data = jpeg
        self.thumbnail = full.preparingThumbnail(of: CGSize(width: 240, height: 240)) ?? full
    }
}
