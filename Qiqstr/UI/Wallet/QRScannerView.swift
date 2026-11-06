import AVFoundation
import CoreImage
import PhotosUI
import SwiftUI
import UIKit

enum CameraPermission {
    case undetermined, authorized, denied, unavailable
}

@MainActor
@Observable
final class QRScannerModel {
    private(set) var permission: CameraPermission = .undetermined
    var torchOn = false
    var hasTorch: Bool { AVCaptureDevice.default(for: .video)?.hasTorch ?? false }

    func requestAccess() async {
        guard AVCaptureDevice.default(for: .video) != nil else {
            permission = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: permission = .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permission = granted ? .authorized : .denied
        default: permission = .denied
        }
    }

    func detect(in item: PhotosPickerItem) async -> String? {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = CIImage(data: data) else { return nil }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: image) ?? []
        return features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
}

struct QRScannerView: View {
    var title: String = L("scanQRCode")
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var model = QRScannerModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var scanned = false
    @State private var photoError = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
            VStack {
                header
                Spacer()
                footer
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.success, trigger: scanned)
        .task { await model.requestAccess() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let code = await model.detect(in: item) { deliver(code) } else { photoError = true }
                photoItem = nil
            }
        }
        .alert(L("walletNoQRCodeFound"), isPresented: $photoError) {
            Button(L("ok"), role: .cancel) {}
        }
        .accessibilityIdentifier("qr-scanner")
    }

    @ViewBuilder private var content: some View {
        switch model.permission {
        case .undetermined:
            ProgressView().tint(.white)
        case .authorized:
            CameraScanner(torchOn: model.torchOn) { deliver($0) }
                .ignoresSafeArea()
            Viewfinder()
        case .denied:
            permissionMessage(title: L("walletCameraAccessTitle"), message: L("walletCameraAccessMessage"), showSettings: true)
        case .unavailable:
            permissionMessage(title: L("walletCameraUnavailable"), message: L("walletCameraUnavailableMessage"), showSettings: false)
        }
    }

    private func permissionMessage(title: String, message: String, showSettings: Bool) -> some View {
        VStack(spacing: 14) {
            IconTile(systemImage: "camera", size: 64, tint: .white)
            Text(title).font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
            Text(message).font(.system(size: 15)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
            if showSettings {
                Button(L("walletOpenSettings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.glassProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .padding(.top, 6)
                .accessibilityIdentifier("qr-open-settings")
            }
        }
        .padding(32)
    }

    private var header: some View {
        HStack {
            GlassIconButton(systemImage: "xmark", accessibilityLabel: L("closeDialog")) { dismiss() }
                .accessibilityIdentifier("qr-close")
            Spacer()
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            Spacer()
            if model.permission == .authorized && model.hasTorch {
                GlassIconButton(systemImage: model.torchOn ? "flashlight.on.fill" : "flashlight.off.fill", accessibilityLabel: L("walletFlashlight")) {
                    model.torchOn.toggle()
                }
                .accessibilityIdentifier("qr-torch")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
    }

    private var footer: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(L("walletChoosePhoto"), systemImage: "photo")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("qr-photo")
                Button {
                    if let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { deliver(text) }
                } label: {
                    Label(L("walletPaste"), systemImage: "doc.on.clipboard")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("qr-paste")
            }
            .foregroundStyle(.white)
        }
    }

    private func deliver(_ code: String) {
        guard !scanned else { return }
        scanned = true
        onScan(code.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

private struct Viewfinder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .strokeBorder(.white.opacity(0.85), lineWidth: 3)
            .frame(width: 250, height: 250)
            .shadow(color: .black.opacity(0.4), radius: 12)
            .allowsHitTesting(false)
    }
}

final class ScannerPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraScanner: UIViewRepresentable {
    var torchOn: Bool
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIView(context: Context) -> ScannerPreviewView {
        let view = ScannerPreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.configure(view.previewLayer)
        return view
    }

    func updateUIView(_ view: ScannerPreviewView, context: Context) {
        context.coordinator.onCode = onCode
        context.coordinator.setTorch(torchOn)
    }

    static func dismantleUIView(_ view: ScannerPreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let session = AVCaptureSession()
        var onCode: (String) -> Void
        private var device: AVCaptureDevice?
        private var delivered = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func configure(_ layer: AVCaptureVideoPreviewLayer) {
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
            self.device = device
            session.beginConfiguration()
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = output.availableMetadataObjectTypes.contains(.qr) ? [.qr] : []
            }
            session.commitConfiguration()
            layer.session = session
            let session = session
            DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        }

        func setTorch(_ on: Bool) {
            guard let device, device.hasTorch, (device.torchMode == .on) != on, (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }

        func stop() {
            let session = session
            DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
        }

        nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            let value = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }.first
            MainActor.assumeIsolated {
                guard let value, !delivered else { return }
                delivered = true
                onCode(value)
            }
        }
    }
}
