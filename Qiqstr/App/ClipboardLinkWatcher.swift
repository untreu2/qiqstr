import SwiftUI
import UIKit

@MainActor
@Observable
final class ClipboardLinkWatcher {
    static let shared = ClipboardLinkWatcher()
    private(set) var isBannerVisible = false
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private let seenKey = "clipboard_seen_change_count"

    private var seenChangeCount: Int {
        get { UserDefaults.standard.integer(forKey: seenKey) }
        set { UserDefaults.standard.set(newValue, forKey: seenKey) }
    }

    func becameActive() async {
        let pasteboard = UIPasteboard.general
        let count = pasteboard.changeCount
        guard count != seenChangeCount else { return }
        seenChangeCount = count
        guard pasteboard.hasStrings || pasteboard.hasURLs else { return }
        let patterns = (try? await pasteboard.detectedPatterns(for: [\.probableWebURL, \.probableWebSearch])) ?? []
        guard !patterns.isEmpty, count == pasteboard.changeCount else { return }
        showBanner()
    }

    func enteredBackground() {
        seenChangeCount = UIPasteboard.general.changeCount
        dismiss()
    }

    func dismiss() {
        hideTask?.cancel()
        withAnimation(.smooth) { isBannerVisible = false }
    }

    func handle(_ strings: [String]) {
        dismiss()
        if let link = strings.lazy.compactMap(NostrLink.init(text:)).first {
            Router.shared.open(link)
        } else {
            ToastCenter.shared.show(L("clipboardNoLink"))
        }
    }

    private func showBanner() {
        withAnimation(.smooth) { isBannerVisible = true }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}

struct ClipboardLinkBanner: View {
    @State private var watcher = ClipboardLinkWatcher.shared

    var body: some View {
        if watcher.isBannerVisible {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(L("clipboardOpenLink"))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Spacer(minLength: 4)
                PasteButton(payloadType: String.self) { strings in
                    Task { @MainActor in ClipboardLinkWatcher.shared.handle(strings) }
                }
                .labelStyle(.titleOnly)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(AppColors.textPrimary)
                .accessibilityIdentifier("clipboard-open")
                Button {
                    watcher.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L("clipboardDismiss"))
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("clipboard-banner")
        }
    }
}
