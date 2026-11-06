import Foundation
import UIKit

nonisolated enum BlurHash {
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~")
    private static let values: [Character: Int] = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    static func image(_ hash: String) -> UIImage? {
        if let hit = cache.object(forKey: hash as NSString) { return hit }
        guard let image = decode(hash) else { return nil }
        cache.setObject(image, forKey: hash as NSString)
        return image
    }

    static func decode(_ hash: String, width: Int = 32, height: Int = 32, punch: Float = 1) -> UIImage? {
        let chars = Array(hash)
        guard chars.count >= 6, let sizeFlag = decode83(chars[0..<1]) else { return nil }
        let numY = sizeFlag / 9 + 1
        let numX = sizeFlag % 9 + 1
        guard chars.count == 4 + 2 * numX * numY, let quantisedMaximum = decode83(chars[1..<2]), let dc = decode83(chars[2..<6]) else { return nil }
        let maximum = Float(quantisedMaximum + 1) / 166 * punch
        var colors: [(Float, Float, Float)] = [(srgbToLinear(dc >> 16), srgbToLinear((dc >> 8) & 255), srgbToLinear(dc & 255))]
        for index in 1..<(numX * numY) {
            let start = 4 + index * 2
            guard let value = decode83(chars[start..<(start + 2)]) else { return nil }
            colors.append((
                signPow((Float(value / (19 * 19)) - 9) / 9, 2) * maximum,
                signPow((Float((value / 19) % 19) - 9) / 9, 2) * maximum,
                signPow((Float(value % 19) - 9) / 9, 2) * maximum
            ))
        }
        let cosX = (0..<width).map { x in (0..<numX).map { i in cos(Float.pi * Float(x) * Float(i) / Float(width)) } }
        let cosY = (0..<height).map { y in (0..<numY).map { j in cos(Float.pi * Float(y) * Float(j) / Float(height)) } }
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var r: Float = 0, g: Float = 0, b: Float = 0
                for j in 0..<numY {
                    for i in 0..<numX {
                        let basis = cosX[x][i] * cosY[y][j]
                        let color = colors[i + j * numX]
                        r += color.0 * basis
                        g += color.1 * basis
                        b += color.2 * basis
                    }
                }
                let offset = (y * width + x) * 4
                pixels[offset] = linearToSrgb(r)
                pixels[offset + 1] = linearToSrgb(g)
                pixels[offset + 2] = linearToSrgb(b)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: cg)
    }

    static func encode(_ image: UIImage, componentsX: Int = 4, componentsY: Int = 3) -> String? {
        guard let source = image.cgImage else { return nil }
        let size = 32
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { return nil }
        let linear = pixels.map { srgbToLinear(Int($0)) }
        var factors: [(Float, Float, Float)] = []
        for j in 0..<componentsY {
            for i in 0..<componentsX {
                let normalisation: Float = (i == 0 && j == 0) ? 1 : 2
                var r: Float = 0, g: Float = 0, b: Float = 0
                for y in 0..<size {
                    let cy = cos(Float.pi * Float(j) * Float(y) / Float(size))
                    for x in 0..<size {
                        let basis = normalisation * cos(Float.pi * Float(i) * Float(x) / Float(size)) * cy
                        let offset = (y * size + x) * 4
                        r += basis * linear[offset]
                        g += basis * linear[offset + 1]
                        b += basis * linear[offset + 2]
                    }
                }
                let scale = 1 / Float(size * size)
                factors.append((r * scale, g * scale, b * scale))
            }
        }
        let dc = factors[0]
        let ac = factors.dropFirst()
        var hash = encode83((componentsX - 1) + (componentsY - 1) * 9, length: 1)
        let maximum: Float
        if let actual = ac.map({ max(abs($0.0), abs($0.1), abs($0.2)) }).max() {
            let quantised = Int(max(0, min(82, (actual * 166 - 0.5).rounded(.down))))
            maximum = Float(quantised + 1) / 166
            hash += encode83(quantised, length: 1)
        } else {
            maximum = 1
            hash += encode83(0, length: 1)
        }
        hash += encode83((Int(linearToSrgb(dc.0)) << 16) + (Int(linearToSrgb(dc.1)) << 8) + Int(linearToSrgb(dc.2)), length: 4)
        for factor in ac {
            let quant = { (value: Float) in Int(max(0, min(18, (signPow(value / maximum, 0.5) * 9 + 9.5).rounded(.down)))) }
            hash += encode83(quant(factor.0) * 19 * 19 + quant(factor.1) * 19 + quant(factor.2), length: 2)
        }
        return hash
    }

    private static func decode83(_ chars: ArraySlice<Character>) -> Int? {
        var value = 0
        for char in chars {
            guard let digit = values[char] else { return nil }
            value = value * 83 + digit
        }
        return value
    }

    private static func encode83(_ value: Int, length: Int) -> String {
        var result = ""
        var divisor = 1
        for _ in 1..<max(length, 1) { divisor *= 83 }
        for _ in 0..<length {
            result.append(alphabet[(value / divisor) % 83])
            divisor = max(divisor / 83, 1)
        }
        return result
    }

    private static func srgbToLinear(_ value: Int) -> Float {
        let v = Float(value) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func linearToSrgb(_ value: Float) -> UInt8 {
        let v = max(0, min(1, value))
        let srgb = v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
        return UInt8(max(0, min(255, srgb * 255 + 0.5)))
    }

    private static func signPow(_ value: Float, _ exponent: Float) -> Float {
        (value < 0 ? -1 : 1) * pow(abs(value), exponent)
    }
}
