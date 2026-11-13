import UIKit
import QiqstrCore
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
        ToastWindow.shared.install()
        current = toast
        AccessibilityNotification.Announcement(message).post()
        let seconds: Double = UIAccessibility.isVoiceOverRunning ? 6 : style == .error ? 4 : 2.6
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if current?.id == toast.id { current = nil }
        }
    }

    func error(_ error: Error) {
        if error is ReadOnlyError { ReadOnlyGate.shared.present(); return }
        if case ListError.cancelled = error { return }
        show(coreMessage(error), style: .error)
    }
}

func coreMessage(_ error: Error) -> String {
    if error is QiqError || error is CoreError { return coreErrorMessage(error) }
    return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
}

struct ToastOverlay: ViewModifier {
    func body(content: Content) -> some View {
        content.onAppear { ToastWindow.shared.install() }
    }
}

private struct ToastHost: View {
    @State private var center = ToastCenter.shared

    var body: some View {
        VStack {
            if let toast = center.current {
                HStack(spacing: 10) {
                    Image(systemName: toast.style == .error ? "exclamationmark.circle.fill" : toast.style == .success ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundStyle(toast.style == .error ? AppColors.error : toast.style == .success ? AppColors.success : AppColors.textPrimary)
                        .accessibilityHidden(true)
                    Text(toast.message).font(.subheadline.weight(.medium)).lineLimit(6)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
                .padding(.top, 8)
                .padding(.horizontal, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { center.current = nil }
                .accessibilityAddTraits(.isStaticText)
                .accessibilityIdentifier("toast")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(duration: 0.35), value: center.current)
    }
}

@MainActor
final class ToastWindow {
    static let shared = ToastWindow()
    private var window: PassthroughWindow?

    func install() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let style = scene.windows.first { !($0 is PassthroughWindow) }?.overrideUserInterfaceStyle ?? .unspecified
        if let window, window.windowScene === scene {
            window.overrideUserInterfaceStyle = style
            return
        }
        let window = PassthroughWindow(windowScene: scene)
        let host = UIHostingController(rootView: ToastHost())
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.overrideUserInterfaceStyle = style
        window.isHidden = false
        self.window = window
    }
}

final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event), hit !== rootViewController?.view else { return nil }
        return hit
    }
}

extension View {
    func toastOverlay() -> some View { modifier(ToastOverlay()) }
}
