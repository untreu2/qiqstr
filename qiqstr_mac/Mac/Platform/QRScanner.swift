import CoreImage
import SwiftUI
import UniformTypeIdentifiers

enum QRImageReader {
    static func code(in url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let image = CIImage(contentsOf: url) else { return nil }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return (detector?.features(in: image) ?? []).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
}

struct QRScannerView: View {
    var title: String = L("scanQRCode")
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var notFound = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(L("walletPaste") + " · " + L("walletChoosePhoto"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    if let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { deliver(text) }
                } label: {
                    Label(L("walletPaste"), systemImage: "doc.on.clipboard").frame(minWidth: 140)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut("v")
                .accessibilityIdentifier("qr-paste")
                Button { importing = true } label: {
                    Label(L("walletChoosePhoto"), systemImage: "photo").frame(minWidth: 140)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .accessibilityIdentifier("qr-photo")
            }
        }
        .padding(40)
        .frame(minWidth: 460, minHeight: 320)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L("cancel")) { dismiss() }.accessibilityIdentifier("qr-close")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            if let code = QRImageReader.code(in: url) { deliver(code) } else { notFound = true }
        }
        .alert(L("walletNoQRCodeFound"), isPresented: $notFound) {
            Button(L("ok"), role: .cancel) {}
        }
        .accessibilityIdentifier("qr-scanner")
    }

    private func deliver(_ code: String) {
        onScan(code.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

struct AuthQRScannerSheet: View {
    let onScan: (String) -> Void
    static var isAvailable: Bool { true }

    var body: some View {
        NavigationStack { QRScannerView(onScan: onScan) }
    }
}

struct ProfileQRScannerView: View {
    var onScan: (String) -> Void

    var body: some View {
        NavigationStack { QRScannerView(onScan: onScan) }
    }
}
