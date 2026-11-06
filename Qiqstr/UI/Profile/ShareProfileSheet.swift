import CoreImage.CIFilterBuiltins
import SwiftUI
import VisionKit

enum QRCodeRenderer {
    static func image(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct ShareProfileSheet: View {
    let pubkey: String
    @Environment(\.dismiss) private var dismiss
    @State private var cache = ProfileCache.shared
    @State private var qr: UIImage?
    @State private var copied = 0
    @State private var showScanner = false

    private var npub: String { Nip19.npub(pubkey) ?? pubkey }
    private var link: String { "nostr:\(npub)" }
    private var profile: Profile? { cache.profile(pubkey) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    card
                    npubRow
                    actions
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(AppColors.background)
            .navigationTitle(L("shareProfile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityIdentifier("share-profile-close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showScanner = true } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .accessibilityLabel(L("scanQRCode"))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: copied)
        .task(id: pubkey) {
            qr = QRCodeRenderer.image(link)
            if profile == nil { await cache.load([pubkey]) }
        }
        .fullScreenCover(isPresented: $showScanner) {
            ProfileQRScannerView { value in handleScan(value) }
        }
    }

    private var card: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ProfileAvatar(pubkey: pubkey, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile?.bestName ?? L("anonymous"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let nip05 = profile?.nip05.nilIfEmpty {
                        Text(Nip05Verifier.display(nip05))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white)
                if let qr {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(18)
                        .accessibilityLabel(L("shareProfile"))
                        .accessibilityIdentifier("share-profile-qr")
                } else {
                    ProgressView().tint(.black)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 320)
            Text(L("shareThisToReceiveMessages"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var npubRow: some View {
        Button(action: copyNpub) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("publicKeyNpub"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(npub)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
                Image(systemName: "doc.on.doc")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 22))
        .accessibilityLabel(L("copy"))
        .accessibilityIdentifier("share-profile-copy")
    }

    private var actions: some View {
        VStack(spacing: 12) {
            ShareLink(item: URL(string: link) ?? URL(string: "nostr:")!, subject: Text(profile?.bestName ?? L("profile"))) {
                Label(L("share"), systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .accessibilityIdentifier("share-profile-sharelink")
            SecondaryButton(title: L("scanQRCode"), systemImage: "qrcode.viewfinder") { showScanner = true }
                .accessibilityIdentifier("share-profile-scan")
        }
    }

    private func copyNpub() {
        UIPasteboard.general.string = npub
        copied += 1
        ToastCenter.shared.show(L("copiedNpub"), style: .success)
    }

    private func handleScan(_ value: String) {
        let raw = Nip19.stripScheme(value.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let hex = Nip19.pubkeyHex(from: raw) else {
            ToastCenter.shared.show(L("profileInvalidQRCode"), style: .error)
            return
        }
        showScanner = false
        Router.shared.sheet = nil
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            Router.shared.push(.profile(hex))
        }
    }
}

struct ProfileQRScannerView: View {
    var onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var handled = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                QRDataScanner { value in
                    guard !handled else { return }
                    handled = true
                    onScan(value)
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        handled = false
                    }
                }
                .ignoresSafeArea()
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.85), lineWidth: 3)
                    .frame(width: 250, height: 250)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            } else {
                EmptyStateView(systemImage: "camera", title: L("profileScannerUnavailable"))
                    .foregroundStyle(.white)
                    .frame(maxHeight: .infinity)
            }
            HStack {
                Text(L("scanQRCode"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .glassEffect(.regular, in: .capsule)
                Spacer()
                GlassIconButton(systemImage: "xmark", accessibilityLabel: L("cancel")) { dismiss() }
                    .accessibilityIdentifier("scanner-close")
            }
            .padding()
        }
        .sensoryFeedback(.success, trigger: handled) { _, new in new }
    }
}

private struct QRDataScanner: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        if !controller.isScanning { try? controller.startScanning() }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let code) = item, let value = code.payloadStringValue {
                    onScan(value)
                    return
                }
            }
        }
    }
}
