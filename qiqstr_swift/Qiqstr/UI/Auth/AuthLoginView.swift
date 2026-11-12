import SwiftUI
import UIKit

@MainActor
@Observable
final class AuthLoginViewModel {
    var input = ""
    var isObscured = true
    var isLoading = false
    var isDecrypting = false
    var errorMessage: String?
    var password = ""
    var passwordError: String?
    var failureCount = 0

    var isEncryptedInput: Bool { Ncryptsec.matches(input) }
    var canSubmit: Bool {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isLoading else { return false }
        return !isEncryptedInput || !password.isEmpty
    }
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
        guard canSubmit else { return }
        isLoading = true
        errorMessage = nil
        passwordError = nil
        defer {
            isLoading = false
            isDecrypting = false
        }
        do {
            if isEncryptedInput {
                isDecrypting = true
                let key: String
                do {
                    key = try await Ncryptsec.decrypt(value, password: password)
                } catch {
                    passwordError = coreMessage(error)
                    failureCount += 1
                    return
                }
                isDecrypting = false
                password = ""
                try await Session.shared.login(key)
            } else {
                try await Session.shared.login(value)
            }
        } catch {
            errorMessage = L("errorPrefix", ["message": coreMessage(error)])
            failureCount += 1
        }
    }
}

struct AuthLoginView: View {
    @State private var model = AuthLoginViewModel()
    @State private var showScanner = false
    @FocusState private var focused: Bool
    @FocusState private var passwordFocused: Bool

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
                    if model.isEncryptedInput {
                        passwordField
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
                passwordFocused = false
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
        .animation(.snappy, value: model.isEncryptedInput)
        .animation(.snappy, value: model.passwordError)
        .onChange(of: model.input) { old, new in
            if model.isEncryptedInput, new.count - old.count > 1 { passwordFocused = true }
        }
        .onChange(of: model.password) { _, _ in model.passwordError = nil }
        .sensoryFeedback(.error, trigger: model.failureCount)
        .disabled(model.isLoading)
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("authNcryptsecDetected"), systemImage: "lock")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            QiqTextField(placeholder: L("authNcryptsecPassword"), text: $model.password, isSecure: true)
                .textContentType(.password)
                .focused($passwordFocused)
                .submitLabel(.go)
                .onSubmit { Task { await model.login() } }
                .accessibilityIdentifier("login-ncryptsec-password")
            if let message = model.passwordError {
                AuthErrorText(message: message)
                    .accessibilityIdentifier("login-ncryptsec-error")
            }
            if model.isDecrypting {
                Label {
                    Text(L("authDecrypting"))
                } icon: {
                    ProgressView().controlSize(.small)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
        }
        .transition(.opacity)
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
