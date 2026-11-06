import SwiftUI
import UIKit

@MainActor
@Observable
final class AddKeyViewModel {
    var input = ""
    var isRevealed = false
    var isSaving = false
    var isDecrypting = false
    var errorMessage: String?
    var password = ""
    var passwordError: String?
    var failureCount = 0
    var successCount = 0

    var isEncryptedInput: Bool { Ncryptsec.matches(input) }
    var canSubmit: Bool {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSaving else { return false }
        return !isEncryptedInput || !password.isEmpty
    }

    func paste() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        input = text
        errorMessage = nil
    }

    func applyScanned(_ value: String) {
        input = Nip19.stripScheme(value.trimmingCharacters(in: .whitespacesAndNewlines))
        errorMessage = nil
    }

    func submit() async -> Bool {
        guard canSubmit else { return false }
        isSaving = true
        errorMessage = nil
        passwordError = nil
        defer {
            isSaving = false
            isDecrypting = false
        }
        var key = input
        if isEncryptedInput {
            isDecrypting = true
            do {
                key = try await Ncryptsec.decrypt(input, password: password)
            } catch {
                passwordError = coreMessage(error)
                failureCount += 1
                return false
            }
            isDecrypting = false
            password = ""
        }
        do {
            try await Session.shared.addKey(key)
            successCount += 1
            ToastCenter.shared.show(L("addKeySuccess"), style: .success)
            return true
        } catch {
            errorMessage = coreMessage(error)
            failureCount += 1
            return false
        }
    }
}

struct AddKeySheet: View {
    @State private var model = AddKeyViewModel()
    @State private var session = Session.shared
    @State private var cache = ProfileCache.shared
    @State private var showScanner = false
    @FocusState private var focused: Bool
    @FocusState private var passwordFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var accountName: String {
        guard let pubkey = session.pubkey else { return "" }
        return cache.profile(pubkey)?.bestName ?? Profile.shortNpub(pubkey)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Group {
                            if model.isRevealed {
                                TextField(L("addKeyPlaceholder"), text: $model.input, axis: .vertical)
                            } else {
                                SecureField(L("addKeyPlaceholder"), text: $model.input)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(submit)
                        .accessibilityIdentifier("add-key-input")
                        Button {
                            model.isRevealed.toggle()
                        } label: {
                            Image(systemName: model.isRevealed ? "eye" : "eye.slash")
                                .foregroundStyle(.secondary)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(model.isRevealed ? L("hideKey") : L("showKey"))
                    }
                    Button {
                        model.paste()
                    } label: {
                        Label(L("authPaste"), systemImage: "doc.on.clipboard")
                    }
                    if AuthQRScannerSheet.isAvailable {
                        Button {
                            showScanner = true
                        } label: {
                            Label(L("scanQRCode"), systemImage: "qrcode.viewfinder")
                        }
                    }
                } header: {
                    Text(L("privateKeyNsec"))
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        if let message = model.errorMessage {
                            AuthErrorText(message: message)
                        }
                        Text(L("addKeySubtitle", ["name": accountName]))
                    }
                }
                if model.isEncryptedInput {
                    passwordSection
                }
            }
            .navigationTitle(L("addKeyTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isSaving {
                        ProgressView()
                    } else {
                        Button(role: .confirm, action: submit)
                            .disabled(!model.canSubmit)
                            .accessibilityIdentifier("add-key-submit")
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                AuthQRScannerSheet { model.applyScanned($0) }
            }
            .animation(.snappy, value: model.errorMessage)
            .animation(.snappy, value: model.passwordError)
            .animation(.snappy, value: model.isEncryptedInput)
            .onChange(of: model.isEncryptedInput) { _, encrypted in
                if encrypted { passwordFocused = true }
            }
            .onChange(of: model.password) { _, _ in model.passwordError = nil }
            .sensoryFeedback(.error, trigger: model.failureCount)
            .sensoryFeedback(.success, trigger: model.successCount)
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isSaving)
        .accessibilityIdentifier("add-key-sheet")
    }

    private var passwordSection: some View {
        Section {
            SecureField(L("authNcryptsecPassword"), text: $model.password)
                .textContentType(.password)
                .focused($passwordFocused)
                .submitLabel(.done)
                .onSubmit(submit)
                .accessibilityIdentifier("add-key-ncryptsec-password")
            if model.isDecrypting {
                Label {
                    Text(L("authDecrypting"))
                } icon: {
                    ProgressView()
                }
                .foregroundStyle(.secondary)
            }
        } header: {
            Text(L("authNcryptsecPasswordHeader"))
        } footer: {
            if let message = model.passwordError {
                AuthErrorText(message: message)
                    .accessibilityIdentifier("add-key-ncryptsec-error")
            } else {
                Text(L("authNcryptsecDetected"))
            }
        }
    }

    private func submit() {
        focused = false
        passwordFocused = false
        Task {
            if await model.submit() { dismiss() }
        }
    }
}

struct ReadOnlyGateModifier: ViewModifier {
    @State private var gate = ReadOnlyGate.shared
    @State private var session = Session.shared

    func body(content: Content) -> some View {
        content
            .environment(\.canSign, session.canSign)
            .alert(L("readOnlyTitle"), isPresented: $gate.isAlertPresented) {
                Button(L("readOnlyAddKey")) { gate.addKey() }
                    .accessibilityIdentifier("read-only-add-key")
                Button(L("cancel"), role: .cancel) {}
            } message: {
                Text(L("readOnlyMessage"))
            }
            .sheet(isPresented: $gate.isAddingKey) {
                AddKeySheet()
            }
    }
}

extension View {
    func readOnlyGate() -> some View { modifier(ReadOnlyGateModifier()) }
}
