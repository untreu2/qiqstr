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
                NoteVideoView(url: item.url, aspectRatio: item.aspectRatio, blurhash: item.blurhash, poster: item.poster, alt: item.alt)
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
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .leading)
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
                                Text("+\(images.count - 4)").font(.title2.weight(.semibold)).foregroundStyle(.white)
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
        let item = images[index]
        return NoteMediaImage(item: item, maxPixel: 1100)
            .contentShape(Rectangle())
            .onTapGesture { viewer = NotePhotoSelection(index: index) }
            .accessibilityElement()
            .accessibilityLabel(item.alt ?? L("photos"))
            .accessibilityAddTraits([.isButton, .isImage])
            .accessibilityIdentifier("note-media-image")
            .overlay(alignment: .bottomLeading) {
                if let alt = item.alt {
                    NoteAltBadge(text: alt).padding(8)
                }
            }
    }
}

struct NoteMediaImage: View {
    let item: NoteMediaItem
    var maxPixel: CGFloat = 1100
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
                } else {
                    NoteMediaPlaceholder(blurhash: item.blurhash)
                }
            }
            .clipped()
            .task(id: item.url) {
                image = nil
                guard let url = URL(string: item.url), url.scheme?.hasPrefix("http") == true else { return }
                let start = ContinuousClock.now
                let loaded = await ImagePipeline.shared.image(for: url, maxPixel: maxPixel)
                if ContinuousClock.now - start < .milliseconds(60) {
                    image = loaded
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { image = loaded }
                }
            }
    }
}

struct NoteMediaPlaceholder: View {
    let blurhash: String?

    var body: some View {
        if let blurhash, let image = BlurHash.image(blurhash) {
            Image(uiImage: image).resizable()
        } else {
            Rectangle().fill(AppColors.tile)
        }
    }
}

struct NoteAltBadge: View {
    let text: String
    @State private var presented = false

    var body: some View {
        Button { presented = true } label: {
            Text(L("feedAltBadge"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .popover(isPresented: $presented) {
            ScrollView {
                Text(text)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .frame(idealWidth: 320, maxHeight: 320)
            .fixedSize(horizontal: false, vertical: true)
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel(L("feedAltTextTitle"))
        .accessibilityHint(text)
        .accessibilityIdentifier("note-media-alt")
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
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .glassEffect(.regular, in: .capsule)
                        }
                        Spacer()
                        if let url = URL(string: urls[min(index, urls.count - 1)]) {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.body.weight(.semibold))
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
    var blurhash: String?
    var poster: String?
    var alt: String?
    @State private var player: AVPlayer?
    @State private var thumbnail: UIImage?
    @State private var duration: Double?
    @State private var isPlaying = false
    @State private var isMuted = true

    var body: some View {
        ZStack {
            if let player {
                NotePlayerLayerView(player: player)
                    .contentShape(Rectangle())
                    .onTapGesture { togglePlayback() }
                    .accessibilityElement()
                    .accessibilityLabel(isPlaying ? L("videoPause") : L("videoTapToPlay"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("note-media-video-surface")
                if !isPlaying { playButton }
            } else {
                Rectangle().fill(Color.black)
                NoteMediaPlaceholder(blurhash: blurhash)
                if let thumbnail {
                    Color.clear
                        .overlay { Image(uiImage: thumbnail).resizable().scaledToFill() }
                        .clipped()
                        .transition(.opacity)
                }
                playButton
            }
        }
        .aspectRatio(min(max(aspectRatio ?? 16 / 9, 0.56), 1.9), contentMode: .fit)
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if player != nil {
                fullScreenButton
            } else if let duration {
                Text(Self.format(duration))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: .capsule)
                    .padding(10)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if player != nil {
                muteButton
            } else if let alt {
                NoteAltBadge(text: alt).padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 460, alignment: .leading)
        .onDisappear {
            guard player?.isExternallyPresented != true else { return }
            player?.pause()
            isPlaying = false
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { note in
            guard let item = note.object as? AVPlayerItem, item === player?.currentItem else { return }
            player?.seek(to: .zero)
            isPlaying = false
        }
        .task(id: url) {
            guard thumbnail == nil, let u = URL(string: url) else { return }
            if let poster, let p = URL(string: poster), let image = await ImagePipeline.shared.image(for: p, maxPixel: 900) {
                withAnimation(.easeOut(duration: 0.2)) { thumbnail = image }
                duration = await NoteVideoThumbnailCache.shared.duration(for: u)
                return
            }
            let preview = await NoteVideoThumbnailCache.shared.preview(for: u)
            duration = preview.duration
            if let image = preview.thumbnail { withAnimation(.easeOut(duration: 0.2)) { thumbnail = image } }
        }
    }

    private var playButton: some View {
        Button(action: play) {
            Image(systemName: "play.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(alt.map { "\(L("videoTapToPlay")), \($0)" } ?? L("videoTapToPlay"))
        .accessibilityValue(duration.map(Self.format) ?? "")
        .accessibilityIdentifier("note-media-video-play")
    }

    private var muteButton: some View {
        controlButton(isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: isMuted ? L("unmute") : L("mute"), identifier: "note-media-video-mute") {
            isMuted.toggle()
            player?.isMuted = isMuted
        }
        .padding(10)
    }

    private var fullScreenButton: some View {
        controlButton("arrow.up.left.and.arrow.down.right", label: L("videoFullScreen"), identifier: "note-media-video-fullscreen") {
            guard let player else { return }
            NoteFullScreenVideo.present(player) { syncFromPlayer() }
        }
        .padding(10)
    }

    private func controlButton(_ symbol: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(.black.opacity(0.35)).interactive(), in: .circle)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func play() {
        if let player {
            player.play()
            isPlaying = true
            return
        }
        guard let u = URL(string: url) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        let p = AVPlayer(url: u)
        p.isMuted = isMuted
        player = p
        p.play()
        isPlaying = true
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    private func syncFromPlayer() {
        guard let player else { return }
        isPlaying = player.timeControlStatus != .paused
        isMuted = player.isMuted
    }

    static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}

struct NoteVideoPreview: Sendable {
    var thumbnail: UIImage?
    var duration: Double?
}

actor NoteVideoThumbnailCache {
    static let shared = NoteVideoThumbnailCache()
    private var cache: [URL: UIImage] = [:]
    private var durations: [URL: Double] = [:]
    private var failed: Set<URL> = []

    func duration(for url: URL) async -> Double? {
        if let hit = durations[url] { return hit }
        guard let value = await Self.loadDuration(AVURLAsset(url: url)) else { return nil }
        durations[url] = value
        return value
    }

    func preview(for url: URL) async -> NoteVideoPreview {
        if let hit = cache[url] { return NoteVideoPreview(thumbnail: hit, duration: durations[url]) }
        if failed.contains(url) { return NoteVideoPreview(thumbnail: nil, duration: durations[url]) }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 900, height: 900)
        async let loadedDuration = Self.loadDuration(asset)
        let cg = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        if let value = await loadedDuration { durations[url] = value }
        guard let cg else {
            failed.insert(url)
            return NoteVideoPreview(thumbnail: nil, duration: durations[url])
        }
        let image = UIImage(cgImage: cg)
        cache[url] = image
        return NoteVideoPreview(thumbnail: image, duration: durations[url])
    }

    private static func loadDuration(_ asset: AVURLAsset) async -> Double? {
        guard let time = try? await asset.load(.duration), time.isNumeric else { return nil }
        let seconds = time.seconds
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}

struct NotePlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

enum NoteFullScreenVideo {
    static func present(_ player: AVPlayer, onDismiss: @escaping () -> Void) {
        guard let presenter = topViewController() else { return }
        let controller = NoteFullScreenPlayerController()
        controller.player = player
        controller.videoGravity = .resizeAspect
        controller.modalPresentationStyle = .fullScreen
        controller.onDismiss = {
            player.isExternallyPresented = false
            onDismiss()
        }
        player.isExternallyPresented = true
        presenter.present(controller, animated: true) { player.play() }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

final class NoteFullScreenPlayerController: AVPlayerViewController {
    var onDismiss: (() -> Void)?
    private var wasPlaying = false

    override func viewWillDisappear(_ animated: Bool) {
        wasPlaying = player?.timeControlStatus != .paused
        super.viewWillDisappear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed else { return }
        if wasPlaying { player?.play() }
        onDismiss?()
    }
}

extension AVPlayer {
    private static var presentedKey: UInt8 = 0

    var isExternallyPresented: Bool {
        get { (objc_getAssociatedObject(self, &Self.presentedKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &Self.presentedKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
