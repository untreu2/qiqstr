import SwiftUI

@MainActor
@Observable
final class SensitiveContentStore {
    static let shared = SensitiveContentStore()
    static let preferenceKey = "show_sensitive_content"

    private(set) var revealed: Set<String> = []

    func isRevealed(_ noteId: String) -> Bool { revealed.contains(noteId) }

    func reveal(_ noteId: String) { revealed.insert(noteId) }
}

struct NoteSensitiveCover: ViewModifier {
    let noteId: String
    let reason: String?
    var compact = false
    @AppStorage(SensitiveContentStore.preferenceKey) private var showSensitive = false
    @State private var store = SensitiveContentStore.shared

    private var showsAll: Bool { AppStorePolicy.allowsSensitiveContentToggle && showSensitive }
    private var hidden: Bool { reason != nil && !showsAll && !store.isRevealed(noteId) }

    func body(content: Content) -> some View {
        if hidden {
            content
                .blur(radius: compact ? 18 : 28, opaque: false)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity, minHeight: compact ? 72 : 112, alignment: .topLeading)
                .overlay { NoteSensitiveOverlay(reason: reason ?? "", compact: compact) { reveal() } }
                .clipShape(.rect(cornerRadius: compact ? 12 : 16, style: .continuous))
        } else {
            content
        }
    }

    private func reveal() {
        withAnimation(.smooth(duration: 0.3)) { store.reveal(noteId) }
    }
}

struct NoteSensitiveOverlay: View {
    let reason: String
    var compact = false
    let onReveal: () -> Void

    private var title: String {
        reason.isEmpty ? L("feedSensitiveContent") : L("feedSensitiveContentReason", ["reason": reason])
    }

    var body: some View {
        ZStack {
            Rectangle().fill(AppColors.tile.opacity(0.55))
            if compact {
                HStack(spacing: 10) {
                    label
                    Spacer(minLength: 8)
                    showButton
                }
                .padding(.horizontal, 12)
            } else {
                VStack(spacing: 10) {
                    label
                    showButton
                }
                .padding(12)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("note-sensitive-cover")
    }

    private var label: some View {
        Label(title, systemImage: "eye.slash")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }

    private var showButton: some View {
        Button(L("feedSensitiveShow"), action: onReveal)
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(compact ? .small : .regular)
            .accessibilityIdentifier("note-sensitive-show")
    }
}

extension View {
    func noteSensitiveCover(_ noteId: String, reason: String?, compact: Bool = false) -> some View {
        modifier(NoteSensitiveCover(noteId: noteId, reason: reason, compact: compact))
    }
}
