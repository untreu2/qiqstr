import AVKit
import SwiftUI

struct DMMediaBubble<Menu: View>: View {
    let message: DMMessage
    let shape: UnevenRoundedRectangle
    let onCopyImage: (UIImage) -> Void
    @ViewBuilder let menu: () -> Menu

    private enum Phase: Equatable {
        case loading
        case image(UIImage, URL)
        case video(URL?)
        case file(URL)
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var isOpeningVideo = false
    @State private var viewerImage: DMViewerItem?
    @State private var videoItem: DMViewerItem?

    private var file: DMFileInfo? { message.file }
    private var mine: Bool { message.isMine }
    private var foreground: Color { mine ? AppColors.background : AppColors.textPrimary }
    private var secondary: Color { mine ? AppColors.background.opacity(0.7) : AppColors.textSecondary }
    private var fill: Color { mine ? AppColors.textPrimary : AppColors.tile }

    var body: some View {
        content
            .contentShape(.contextMenuPreview, shape)
            .task(id: message.id) { await load() }
            .fullScreenCover(item: $viewerImage) { item in
                DMImageViewer(url: item.url)
            }
            .fullScreenCover(item: $videoItem) { item in
                DMVideoPlayer(url: item.url)
            }
    }

    @ViewBuilder
    private var content: some View {
        if file?.isEncrypted == false {
            legacy
        } else {
            switch phase {
            case .loading:
                placeholder(height: file?.isVideo == true ? 160 : 220) { ProgressView().tint(secondary) }
                    .contextMenu { menu() }
            case .image(let image, let url):
                Button {
                    viewerImage = DMViewerItem(url: url)
                } label: {
                    imageView(image)
                }
                .buttonStyle(PressableStyle())
                .contextMenu {
                    Button {
                        onCopyImage(image)
                    } label: {
                        Label(L("copy"), systemImage: "doc.on.doc")
                    }
                    ShareLink(item: url) { Label(L("share"), systemImage: "square.and.arrow.up") }
                    menu()
                }
                .accessibilityIdentifier("dm-media-image")
            case .video(let url):
                Button {
                    Task { await openVideo(url) }
                } label: {
                    placeholder(height: 160) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle().fill(.ultraThinMaterial).frame(width: 56, height: 56)
                                if isOpeningVideo { ProgressView() } else { Image(systemName: "play.fill").font(.system(size: 22)).foregroundStyle(AppColors.textPrimary) }
                            }
                            Text(L("videoTapToPlay")).font(.system(size: 13)).foregroundStyle(secondary)
                        }
                    }
                }
                .buttonStyle(PressableStyle())
                .contextMenu {
                    if let url { ShareLink(item: url) { Label(L("share"), systemImage: "square.and.arrow.up") } }
                    menu()
                }
                .accessibilityIdentifier("dm-media-video")
            case .file(let url):
                ShareLink(item: url) {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.fill").font(.system(size: 20))
                        Text(L("fileType", ["type": url.pathExtension.uppercased()])).font(.system(size: 14, weight: .medium))
                        Image(systemName: "square.and.arrow.up").font(.system(size: 14))
                    }
                    .foregroundStyle(foreground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(fill, in: shape)
                }
                .contextMenu { menu() }
            case .failed(let reason):
                placeholder(height: 120) {
                    VStack(spacing: 6) {
                        Image(systemName: "lock.trianglebadge.exclamationmark").font(.system(size: 22))
                        Text(L("failedToDecryptMedia")).font(.system(size: 13, weight: .semibold))
                        Text(reason).font(.system(size: 11)).lineLimit(2).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(secondary)
                    .padding(.horizontal, 12)
                }
                .onTapGesture { Task { await load(force: true) } }
                .contextMenu { menu() }
            }
        }
    }

    private func imageView(_ image: UIImage) -> some View {
        let width: CGFloat = 240
        let ratio = image.size.width > 0 ? image.size.height / image.size.width : 1
        let height = min(max(width * ratio, 120), 340)
        return Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipShape(shape)
            .contentShape(shape)
    }

    private func placeholder<Content: View>(height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        ZStack { content() }
            .frame(width: 240, height: height)
            .background(fill, in: shape)
    }

    @ViewBuilder
    private var legacy: some View {
        if file?.isImage == true || DMText.isImageURL(message.content) {
            RemoteImage(url: message.content, maxPixel: 720) {
                placeholder(height: 220) { ProgressView().tint(secondary) }
            }
            .frame(width: 240, height: 240)
            .clipShape(shape)
            .contextMenu { menu() }
        } else {
            placeholder(height: 100) {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 22))
                    Text(L("legacyUnencryptedMedia")).font(.system(size: 12))
                }
                .foregroundStyle(secondary)
            }
            .contextMenu { menu() }
        }
    }

    private func load(force: Bool = false) async {
        guard let file, file.isEncrypted else { return }
        if !force, phase != .loading { return }
        phase = .loading
        if file.isVideo {
            phase = .video(nil)
            return
        }
        do {
            let url = try await DMService.shared.decryptedFileURL(for: message)
            if file.isImage {
                let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return ImagePipeline.downsample(data, maxPixel: 900)
                }.value
                phase = image.map { .image($0, url) } ?? .file(url)
            } else {
                phase = .file(url)
            }
        } catch is CancellationError {
            phase = .loading
        } catch {
            phase = .failed(DMService.shared.errorMessage(error))
        }
    }

    private func openVideo(_ cached: URL?) async {
        if let cached {
            videoItem = DMViewerItem(url: cached)
            return
        }
        guard !isOpeningVideo else { return }
        isOpeningVideo = true
        defer { isOpeningVideo = false }
        do {
            let url = try await DMService.shared.decryptedFileURL(for: message)
            phase = .video(url)
            videoItem = DMViewerItem(url: url)
        } catch {
            phase = .failed(DMService.shared.errorMessage(error))
        }
    }
}

struct DMViewerItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct DMImageViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(zoom.simultaneously(with: pan))
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(duration: 0.3)) {
                            if scale > 1 { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero } else { scale = 2.5; lastScale = 2.5 }
                        }
                    }
                    .accessibilityIdentifier("dm-image-viewer")
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .top) {
            HStack {
                GlassIconButton(systemImage: "xmark", accessibilityLabel: L("closeDialog")) { dismiss() }
                    .accessibilityIdentifier("dm-image-viewer-close")
                Spacer()
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .task {
            image = await Task.detached { () -> UIImage? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return ImagePipeline.downsample(data, maxPixel: 3000)
            }.value
        }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in scale = max(1, min(lastScale * value.magnification, 6)) }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 { withAnimation(.spring(duration: 0.3)) { offset = .zero; lastOffset = .zero } }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                if scale > 1 {
                    offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
                } else {
                    offset = CGSize(width: 0, height: value.translation.height)
                }
            }
            .onEnded { value in
                if scale <= 1 {
                    if abs(value.translation.height) > 120 { dismiss() } else { withAnimation(.spring(duration: 0.3)) { offset = .zero } }
                } else {
                    lastOffset = offset
                }
            }
    }
}

struct DMVideoPlayer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player).ignoresSafeArea()
            }
        }
        .overlay(alignment: .topLeading) {
            GlassIconButton(systemImage: "xmark", accessibilityLabel: L("closeDialog")) { dismiss() }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .accessibilityIdentifier("dm-video-close")
        }
        .preferredColorScheme(.dark)
        .onAppear {
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
        }
        .onDisappear { player?.pause() }
    }
}
