import SwiftUI

struct LoadingView: View {
    var body: some View {
        ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message { Text(message) }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glassProminent)
                    .foregroundStyle(AppColors.background)
                    .buttonBorderShape(.capsule)
            }
        }
    }
}

struct BrandWordmark: View {
    var size: CGFloat = 64
    var body: some View {
        Text("qiqstr").font(AppFont.brand(size)).foregroundStyle(AppColors.textPrimary).kerning(-size * 0.03)
    }
}

struct Toast: Equatable, Identifiable {
    enum Style { case info, success, error }
    let id = UUID()
    var message: String
    var style: Style = .info
}

@MainActor
@Observable
final class ToastCenter {
    static let shared = ToastCenter()
    var current: Toast?

    func show(_ message: String, style: Toast.Style = .info) {
        if style == .error, ReadOnlyGate.intercepts(message) { return }
        let toast = Toast(message: message, style: style)
        current = toast
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if current?.id == toast.id { current = nil }
        }
    }

    func error(_ error: Error) {
        if error is ReadOnlyError { ReadOnlyGate.shared.present(); return }
        show(coreMessage(error), style: .error)
    }
}

func coreMessage(_ error: Error) -> String {
    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    return message
}

struct ToastOverlay: ViewModifier {
    @State private var center = ToastCenter.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = center.current {
                HStack(spacing: 10) {
                    Image(systemName: toast.style == .error ? "exclamationmark.circle.fill" : toast.style == .success ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundStyle(toast.style == .error ? AppColors.error : toast.style == .success ? AppColors.success : AppColors.textPrimary)
                    Text(toast.message).font(.subheadline.weight(.medium)).lineLimit(3)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 8)
                .padding(.horizontal, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { center.current = nil }
                .accessibilityIdentifier("toast")
            }
        }
        .animation(.spring(duration: 0.35), value: center.current)
    }
}

extension View {
    func toastOverlay() -> some View { modifier(ToastOverlay()) }
}
