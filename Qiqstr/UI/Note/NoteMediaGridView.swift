import AVKit
import SwiftUI

struct NoteMediaGridView: View {
    let media: [NoteMediaItem]
    var maxHeight: CGFloat = 420
    @State private var viewer: NotePhotoSelection?

    private var images: [NoteMediaItem] { media.filter { !$0.isVideo } }
    private var videos: [NoteMediaItem] { media.filter(\.isVideo) }

    var body: some View {
        VStack(spacing: 6) {
            if !images.isEmpty { imageGrid }
            ForEach(videos) { item in
                NoteVideoView(url: item.url, aspectRatio: item.aspectRatio)
            }
        }
        .fullScreenCover(item: $viewer) { selection in
            NotePhotoViewer(urls: images.map(\.url), startIndex: selection.index)
        }
    }

    @ViewBuilder
    private var imageGrid: some View {
        let spacing: CGFloat = 4
        switch images.count {
        case 1:
            let ratio = min(max(images[0].aspectRatio ?? 4 / 3, 0.66), 1.9)
            tile(0)
                .aspectRatio(ratio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: maxHeight)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
        case 2:
            HStack(spacing: spacing) { tile(0); tile(1) }
                .frame(height: 220)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
        case 3:
            HStack(spacing: spacing) {
                tile(0)
                VStack(spacing: spacing) { tile(1); tile(2) }
            }
            .frame(height: 260)
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
        default:
            VStack(spacing: spacing) {
                HStack(spacing: spacing) { tile(0); tile(1) }
                HStack(spacing: spacing) {
                    tile(2)
                    tile(3).overlay {
                        if images.count > 4 {
                            ZStack {
                                Color.black.opacity(0.45)
                                Text("+\(images.count - 4)").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                            }
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
            .frame(height: 280)
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
        }
    }

    private func tile(_ index: Int) -> some View {
        Color.clear
            .overlay {
                RemoteImage(url: images[index].url, maxPixel: 1100) {
                    Rectangle().fill(AppColors.tile)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { viewer = NotePhotoSelection(index: index) }
            .accessibilityElement()
            .accessibilityLabel(L("photos"))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("note-media-image")
    }
}

struct NotePhotoSelection: Identifiable {
    let index: Int
    var id: Int { index }
}

struct NotePhotoViewer: View {
    let urls: [String]
    let startIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var dragOffset: CGFloat = 0
    @State private var chromeVisible = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea().opacity(1 - min(abs(dragOffset) / 400, 0.7))
            TabView(selection: $index) {
                ForEach(Array(urls.enumerated()), id: \.offset) { offset, url in
                    NoteZoomableImage(url: url, onSingleTap: { withAnimation(.easeInOut(duration: 0.2)) { chromeVisible.toggle() } })
                        .tag(offset)
                        .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: urls.count > 1 && chromeVisible ? .automatic : .never))
            .offset(y: dragOffset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onChanged { value in
                        if abs(value.translation.height) > abs(value.translation.width) { dragOffset = value.translation.height }
                    }
                    .onEnded { value in
                        if abs(value.translation.height) > 140 { dismiss() } else { withAnimation(.spring(duration: 0.3)) { dragOffset = 0 } }
                    }
            )
            .ignoresSafeArea()
            if chromeVisible {
                VStack {
                    HStack {
                        GlassIconButton(systemImage: "xmark", size: 44, accessibilityLabel: L("closeDialog")) { dismiss() }
                            .accessibilityIdentifier("photo-viewer-close")
                        Spacer()
                        if urls.count > 1 {
                            Text("\(index + 1) / \(urls.count)")
                                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .glassEffect(.regular, in: .capsule)
                        }
                        Spacer()
                        if let url = URL(string: urls[min(index, urls.count - 1)]) {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                            }
                            .glassEffect(.regular.interactive(), in: .circle)
                            .accessibilityIdentifier("photo-viewer-share")
                        }
                    }
                    .padding(.horizontal, 16)
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden(!chromeVisible)
        .onAppear { index = startIndex }
        .accessibilityIdentifier("photo-viewer")
    }
}

struct NoteZoomableImage: UIViewRepresentable {
    let url: String
    var onSingleTap: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(onSingleTap: onSingleTap) }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.frame = scroll.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.addSubview(imageView)
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scroll
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTapped))
        singleTap.require(toFail: doubleTap)
        scroll.addGestureRecognizer(singleTap)
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerYAnchor),
        ])
        spinner.startAnimating()
        context.coordinator.load(url, spinner: spinner)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?
        var onSingleTap: () -> Void
        private var task: Task<Void, Never>?

        init(onSingleTap: @escaping () -> Void) { self.onSingleTap = onSingleTap }

        deinit { task?.cancel() }

        func load(_ url: String, spinner: UIActivityIndicatorView) {
            guard let u = URL(string: url) else { return }
            task = Task { @MainActor [weak self] in
                let image = await ImagePipeline.shared.image(for: u, maxPixel: 2800)
                spinner.stopAnimating()
                spinner.removeFromSuperview()
                self?.imageView?.image = image
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func singleTapped() { onSingleTap() }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll = scrollView else { return }
            if scroll.zoomScale > 1 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
        }
    }
}

struct NoteVideoView: View {
    let url: String
    var aspectRatio: CGFloat?
    @State private var player: AVPlayer?
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .onDisappear { player.pause() }
            } else {
                Rectangle().fill(Color.black)
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                }
                Button {
                    guard let u = URL(string: url) else { return }
                    let p = AVPlayer(url: u)
                    player = p
                    p.play()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(L("videoTapToPlay"))
                .accessibilityIdentifier("note-media-video-play")
            }
        }
        .aspectRatio(min(max(aspectRatio ?? 16 / 9, 0.56), 1.9), contentMode: .fit)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 460)
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .task(id: url) {
            guard thumbnail == nil, let u = URL(string: url) else { return }
            thumbnail = await NoteVideoThumbnailCache.shared.thumbnail(for: u)
        }
    }
}

actor NoteVideoThumbnailCache {
    static let shared = NoteVideoThumbnailCache()
    private var cache: [URL: UIImage] = [:]
    private var failed: Set<URL> = []

    func thumbnail(for url: URL) async -> UIImage? {
        if let hit = cache[url] { return hit }
        if failed.contains(url) { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 900, height: 900)
        guard let cg = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image else {
            failed.insert(url)
            return nil
        }
        let image = UIImage(cgImage: cg)
        cache[url] = image
        return image
    }
}
