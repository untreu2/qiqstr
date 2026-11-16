import ImageIO
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@MainActor
final class GIFAnimator {
    private var generation = 0
    private var currentId: String?

    func play(id: String, data: Data, on layer: CALayer) {
        guard id != currentId else { return }
        currentId = id
        generation += 1
        let token = generation
        layer.contentsGravity = .resizeAspectFill
        layer.masksToBounds = true
        CGAnimateImageDataWithBlock(data as CFData, nil) { [weak self, weak layer] _, frame, stop in
            guard let self, let layer, self.generation == token else {
                stop.pointee = true
                return
            }
            layer.contents = frame
        }
    }

    func stop() {
        generation += 1
        currentId = nil
    }
}

#if os(iOS)
struct AnimatedImageView: UIViewRepresentable {
    let id: String
    let data: Data

    func makeCoordinator() -> GIFAnimator { GIFAnimator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.play(id: id, data: data, on: view.layer)
    }

    static func dismantleUIView(_ view: UIView, coordinator: GIFAnimator) {
        coordinator.stop()
    }
}
#endif

struct AnimatedRemoteImage: View {
    let url: String
    var blurhash: String?
    var maxPixel: CGFloat = 600
    @State private var data: Data?
    @State private var still: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let data {
                    AnimatedImageView(id: url, data: data)
                } else if let still {
                    Image(uiImage: still).resizable().scaledToFill()
                } else {
                    NoteMediaPlaceholder(blurhash: blurhash)
                }
            }
            .clipped()
            .task(id: url) {
                guard let remote = URL(string: url) else { return }
                if still == nil { still = await ImagePipeline.shared.image(for: remote, maxPixel: maxPixel) }
                guard !Task.isCancelled else { return }
                data = await ImagePipeline.shared.data(for: remote)
            }
    }
}

extension NoteMediaItem {
    var isGIF: Bool { (URL(string: url)?.path ?? url).lowercased().hasSuffix(".gif") }
}
