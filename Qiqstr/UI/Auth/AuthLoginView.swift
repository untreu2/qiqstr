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
    var isViewOnlyInput: Bool { AccountStore.readOnlyPubkey(input) != nil || Nip05Resolver.looksLikeAddress(input) }

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
                        placeholder: L("authLoginPlaceholder"),
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
                    if model.isViewOnlyInput {
                        Label(L("readOnlyLoginHint"), systemImage: "eye")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                            .transition(.opacity)
                            .accessibilityIdentifier("login-view-only-hint")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("loginExampleSeed"))
                        Text(L("loginExampleNsec"))
                        Text(L("loginExampleViewOnly"))
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
        .animation(.snappy, value: model.isViewOnlyInput)
        .sensoryFeedback(.error, trigger: model.failureCount)
        .disabled(model.isLoading)
    }

    private var trailingControls: some View {
        HStack(spacing: 14) {
            Button {
                model.isObscured.toggle()
            } label: {
                Image(systemName: model.isObscured ? "eye.slash" : "eye")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(model.isObscured ? L("showKey") : L("hideKey"))
            .accessibilityIdentifier("login-toggle-visibility")
            Button {
                model.paste()
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.glassProminent)
            .foregroundStyle(AppColors.background)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .accessibilityLabel(L("authPaste"))
            .accessibilityIdentifier("login-paste")
        }
    }
}
