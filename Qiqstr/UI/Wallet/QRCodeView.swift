import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct QRCodeView: View {
    let content: String
    var size: CGFloat = 260

    var body: some View {
        Group {
            if let image = QRCodeView.image(for: content) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode").font(.system(size: size * 0.4)).foregroundStyle(.black.opacity(0.2))
            }
        }
        .frame(width: size, height: size)
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityIdentifier("qr-code")
    }

    private static let context = CIContext()

    static func image(for content: String) -> CGImage? {
        guard !content.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: output.extent)
    }
}
