import SwiftUI
import UIKit

@MainActor
@Observable
final class AuthLoginViewModel {
    var input = ""
    var isObscured = true
    var isLoading = false
    var errorMessage: String?
    var failureCount = 0

    var canSubmit: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading }

    func paste() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        input = text
        errorMessage = nil
    }

    func applyScanned(_ value: String) {
        input = Nip19.stripScheme(value.trimmingCharacters(in: .whitespacesAndNewlines))
        errorMessage = nil
    }

    func login() async {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await Session.shared.login(value)
        } catch {
            errorMessage = L("errorPrefix", ["message": coreMessage(error)])
            failureCount += 1
        }
        isLoading = false
    }
}

struct AuthLoginView: View {
    @State private var model = AuthLoginViewModel()
    @State private var showScanner = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                AuthHeader(title: L("login"), subtitle: L("loginSubtitle"))
                VStack(alignment: .leading, spacing: 20) {
                    QiqTextField(
                        placeholder: L("enterSeedPhraseOrNsec"),
                        text: $model.input,
                        isSecure: model.isObscured,
                        trailing: AnyView(trailingControls)
                    )
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit { Task { await model.login() } }
                    .accessibilityIdentifier("login-input")
                    if let message = model.errorMessage {
                        AuthErrorText(message: message)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("loginExampleSeed"))
                        Text(L("loginExampleNsec"))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineSpacing(3)
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColors.background)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: L("login"), isLoading: model.isLoading, isEnabled: model.canSubmit) {
                focused = false
                Task { await model.login() }
            }
            .accessibilityIdentifier("login-submit")
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(AppColors.background)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if AuthQRScannerSheet.isAvailable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .accessibilityLabel(L("scanQRCode"))
                    .accessibilityIdentifier("login-scan")
                }
            }
        }
        .sheet(isPresented: $showScanner) {
            AuthQRScannerSheet { model.applyScanned($0) }
        }
        .animation(.snappy, value: model.errorMessage)
        .sensoryFeedback(.error, trigger: model.failureCount)
        .disabled(model.isLoading)
    }

    private var trailingControls: some View {
        HStack(spacing: 14) {
            Button {
                model.isObscured.toggle()
            } label: {
                Image(systemName: model.isObscured ? "eye.slash" : "eye")
                    .font(.system(size: 18))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isObscured ? L("showKey") : L("hideKey"))
            .accessibilityIdentifier("login-toggle-visibility")
            Button {
                model.paste()
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.background)
                    .frame(width: 38, height: 38)
                    .background(AppColors.textPrimary, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(L("authPaste"))
            .accessibilityIdentifier("login-paste")
        }
    }
}
