#if os(iOS)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum CameraCapture {
    case image(UIImage)
    case video(URL)

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
}

struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (CameraCapture) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture, dismiss: { dismiss() }) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoQuality = .typeHigh
        picker.videoMaximumDuration = 180
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (CameraCapture) -> Void
        private let dismiss: () -> Void

        init(onCapture: @escaping (CameraCapture) -> Void, dismiss: @escaping () -> Void) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(.image(image))
            } else if let url = info[.mediaURL] as? URL {
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent("capture-\(UUID().uuidString).\(url.pathExtension.isEmpty ? "mov" : url.pathExtension)")
                if (try? FileManager.default.copyItem(at: url, to: copy)) != nil { onCapture(.video(copy)) }
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
#endif
