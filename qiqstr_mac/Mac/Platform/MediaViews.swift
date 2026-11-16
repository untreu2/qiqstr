import AVKit
import SwiftUI

struct MacPager<Page: View>: View {
    @Binding var index: Int
    let count: Int
    @ViewBuilder var page: (Int) -> Page

    var body: some View {
        ZStack {
            if count > 0 {
                page(min(max(index, 0), count - 1))
                    .id(index)
                    .transition(.opacity)
            }
            if count > 1 {
                HStack {
                    arrow("chevron.left", enabled: index > 0) { index -= 1 }
                    Spacer()
                    arrow("chevron.right", enabled: index < count - 1) { index += 1 }
                }
                .padding(.horizontal, 20)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: index)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            guard index > 0 else { return .ignored }
            index -= 1
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard index < count - 1 else { return .ignored }
            index += 1
            return .handled
        }
    }

    private func arrow(_ systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .opacity(enabled ? 1 : 0)
        .disabled(!enabled)
    }
}

struct NoteZoomableImage: View {
    let url: String
    var onSingleTap: () -> Void = {}
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1

    var body: some View {
        RemoteImage(url: url, maxPixel: 2800, contentMode: .fit) {
            ProgressView().tint(.white)
        }
        .scaleEffect(scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            MagnifyGesture()
                .onChanged { scale = min(max(base * $0.magnification, 1), 5) }
                .onEnded { _ in base = scale }
        )
        .onTapGesture(count: 2) {
            withAnimation(.spring(duration: 0.3)) { scale = scale > 1 ? 1 : 2.5 }
            base = scale
        }
        .onTapGesture { onSingleTap() }
    }
}

struct NotePlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    final class PlayerLayerView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            playerLayer.videoGravity = .resizeAspect
            layer?.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }
}

enum NoteFullScreenVideo {
    private static var windows: [NSWindow] = []

    static func present(_ player: AVPlayer, onDismiss: @escaping () -> Void) {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.allowsPictureInPicturePlayback = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 600), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.contentView = view
        window.center()
        player.isExternallyPresented = true
        let observer = WindowCloseObserver {
            player.isExternallyPresented = false
            windows.removeAll { $0 === window }
            onDismiss()
        }
        window.delegate = observer
        objc_setAssociatedObject(window, &WindowCloseObserver.key, observer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        windows.append(window)
        window.makeKeyAndOrderFront(nil)
        player.play()
    }
}

private final class WindowCloseObserver: NSObject, NSWindowDelegate {
    nonisolated(unsafe) static var key: UInt8 = 0
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}

struct SelectableTextView: NSViewRepresentable {
    let text: String
    @Binding var selection: String

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.font = .preferredFont(forTextStyle: .body)
        view.textColor = .labelColor
        view.string = text
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        if view.string != text { view.string = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        guard let container = nsView.textContainer, let manager = nsView.layoutManager else { return nil }
        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        return CGSize(width: width, height: ceil(manager.usedRect(for: container).height))
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var selection: Binding<String>
        init(selection: Binding<String>) { self.selection = selection }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            let range = view.selectedRange()
            let ns = view.string as NSString
            let picked = range.length > 0 && NSMaxRange(range) <= ns.length ? ns.substring(with: range) : ""
            if selection.wrappedValue != picked { selection.wrappedValue = picked }
        }
    }
}

struct AnimatedImageView: NSViewRepresentable {
    let id: String
    let data: Data

    func makeCoordinator() -> GIFAnimator { GIFAnimator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let layer = view.layer else { return }
        context.coordinator.play(id: id, data: data, on: layer)
    }

    static func dismantleNSView(_ view: NSView, coordinator: GIFAnimator) {
        coordinator.stop()
    }
}
