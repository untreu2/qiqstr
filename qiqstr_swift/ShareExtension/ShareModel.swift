import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class ShareModel {
    enum Phase: Equatable { case loading, editing, saving, handoff, failed }

    static let maxImages = 4

    var text = ""
    var images: [SharedImage] = []
    var phase: Phase = .loading
    @ObservationIgnored private weak var context: NSExtensionContext?

    init(context: NSExtensionContext?) {
        self.context = context
    }

    var canPost: Bool {
        phase == .editing && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty)
    }

    func load() async {
        let items = (context?.inputItems as? [NSExtensionItem]) ?? []
        var parts: [String] = []
        for item in items {
            if let content = item.attributedContentText?.string, !content.isEmpty { parts.append(content) }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    guard images.count < Self.maxImages, let data = await Self.loadData(provider, type: .image),
                          let image = SharedImage(source: data) else { continue }
                    images.append(image)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await Self.loadURL(provider), !url.isFileURL { parts.append(url.absoluteString) }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let string = await Self.loadText(provider) { parts.append(string) }
                }
            }
        }
        text = Self.merge(parts)
        phase = .editing
    }

    func remove(_ image: SharedImage) {
        images.removeAll { $0.id == image.id }
    }

    func cancel() {
        context?.cancelRequest(withError: CocoaError(.userCancelled))
    }

    func finish() {
        context?.completeRequest(returningItems: nil)
    }

    func post() {
        guard canPost else { return }
        phase = .saving
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let datas = images.map(\.data)
        Task {
            let id = await Task.detached { try? ShareInbox.write(text: body, images: datas) }.value
            guard id != nil else {
                phase = .failed
                return
            }
            phase = .handoff
        }
    }

    private static func merge(_ parts: [String]) -> String {
        var result: [String] = []
        for part in parts.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !part.isEmpty {
            if result.contains(where: { $0.contains(part) }) { continue }
            result.removeAll { part.contains($0) }
            result.append(part)
        }
        return result.joined(separator: "\n\n")
    }

    private nonisolated static func loadData(_ provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, _ in continuation.resume(returning: data) }
        }
    }

    private nonisolated static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                continuation.resume(returning: item as? URL ?? (item as? String).flatMap(URL.init(string:)))
            }
        }
    }

    private nonisolated static func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                continuation.resume(returning: item as? String ?? (item as? NSAttributedString)?.string)
            }
        }
    }
}
