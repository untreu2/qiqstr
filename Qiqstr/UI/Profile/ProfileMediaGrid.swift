import AVKit
import SwiftUI

struct ProfileMediaSelection: Identifiable {
    let index: Int
    var id: Int { index }
}

struct ProfileMediaGrid: View {
    let entries: [ProfileMediaEntry]
    var onOpen: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                ProfileMediaTile(entry: entry) { onOpen(index) }
            }
        }
        .padding(.horizontal, 2)
        .accessibilityIdentifier("profile-photos")
    }
}

private struct ProfileMediaTile: View {
    let entry: ProfileMediaEntry
    var onOpen: () -> Void
    @State private var videoThumbnail: UIImage?

    var body: some View {
        Button(action: onOpen) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { thumbnail }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if entry.isVideo {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 3)
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onOpen) {
                Label(L(entry.isVideo ? "videoTapToPlay" : "profileViewImage"), systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Button { Router.shared.push(.thread(entry.noteId)) } label: {
                Label(L("profileOpenNote"), systemImage: "text.bubble")
            }
            if let url = URL(string: entry.url) {
                ShareLink(item: url) { Label(L("share"), systemImage: "square.and.arrow.up") }
            }
        }
        .accessibilityLabel(entry.item.alt ?? L(entry.isVideo ? "videoTapToPlay" : "profileViewImage"))
        .accessibilityIdentifier("profile-photo-tile")
        .task(id: entry.url) { await loadVideoThumbnail() }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if entry.isVideo {
            ZStack {
                Rectangle().fill(AppColors.tile)
                if let poster = entry.item.poster {
                    RemoteImage(url: poster, maxPixel: 500) { Color.clear }
                } else if let videoThumbnail {
                    Image(uiImage: videoThumbnail).resizable().scaledToFill().transition(.opacity)
                }
            }
        } else {
            RemoteImage(url: entry.url, maxPixel: 500) {
                NoteMediaPlaceholder(blurhash: entry.item.blurhash)
            }
        }
    }

    private func loadVideoThumbnail() async {
        guard entry.isVideo, entry.item.poster == nil, videoThumbnail == nil, let url = URL(string: entry.url) else { return }
        let preview = await NoteVideoThumbnailCache.shared.preview(for: url)
        if let image = preview.thumbnail { withAnimation(.easeOut(duration: 0.2)) { videoThumbnail = image } }
    }
}

struct ProfileMediaPager: View {
    let entries: [ProfileMediaEntry]
    let startIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var dragOffset: CGFloat = 0
    @State private var chromeVisible = true

    private var current: ProfileMediaEntry? { entries.indices.contains(index) ? entries[index] : nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea().opacity(1 - min(abs(dragOffset) / 400, 0.7))
            TabView(selection: $index) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                    page(entry, isCurrent: offset == index)
                        .tag(offset)
                        .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: dragOffset)
            .simultaneousGesture(dismissDrag)
            .ignoresSafeArea()
            if chromeVisible { chrome.transition(.opacity) }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden(!chromeVisible)
        .onAppear { index = startIndex }
        .sensoryFeedback(.selection, trigger: index)
        .accessibilityIdentifier("profile-media-pager")
    }

    @ViewBuilder
    private func page(_ entry: ProfileMediaEntry, isCurrent: Bool) -> some View {
        if entry.isVideo {
            ProfileMediaVideoPage(url: entry.url, isCurrent: isCurrent)
        } else {
            NoteZoomableImage(url: entry.url) {
                withAnimation(.easeInOut(duration: 0.2)) { chromeVisible.toggle() }
            }
        }
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                if abs(value.translation.height) > abs(value.translation.width) { dragOffset = value.translation.height }
            }
            .onEnded { value in
                if abs(value.translation.height) > 140 { dismiss() } else { withAnimation(.spring(duration: 0.3)) { dragOffset = 0 } }
            }
    }

    private var chrome: some View {
        VStack {
            HStack {
                GlassIconButton(systemImage: "xmark", size: 44, accessibilityLabel: L("closeDialog")) { dismiss() }
                    .accessibilityIdentifier("profile-media-close")
                Spacer()
                if entries.count > 1 {
                    Text("\(index + 1) / \(entries.count)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .glassEffect(.regular, in: .capsule)
                }
                Spacer()
                if let current, let url = URL(string: current.url) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel(L("share"))
                    .accessibilityIdentifier("profile-media-share")
                }
            }
            .padding(.horizontal, 16)
            Spacer()
            if let current {
                Button {
                    dismiss()
                    Router.shared.push(.thread(current.noteId))
                } label: {
                    Label(L("profileOpenNote"), systemImage: "text.bubble")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .padding(.bottom, 12)
                .accessibilityIdentifier("profile-media-open-note")
            }
        }
    }
}

private struct ProfileMediaVideoPage: View {
    let url: String
    let isCurrent: Bool
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().tint(.white)
            }
        }
        .onAppear(perform: prepare)
        .onChange(of: isCurrent) { _, current in
            if current { player?.play() } else { player?.pause() }
        }
        .onDisappear { player?.pause() }
    }

    private func prepare() {
        guard player == nil, let u = URL(string: url) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        let p = AVPlayer(url: u)
        player = p
        if isCurrent { p.play() }
    }
}
