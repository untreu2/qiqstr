import SwiftUI
import UIKit

@MainActor
@Observable
final class AddKeyViewModel {
    var input = ""
    var isRevealed = false
    var isSaving = false
    var errorMessage: String?
    var failureCount = 0
    var successCount = 0

    var canSubmit: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving }

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
        defer { isSaving = false }
        do {
            try await Session.shared.addKey(input)
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
            .sensoryFeedback(.error, trigger: model.failureCount)
            .sensoryFeedback(.success, trigger: model.successCount)
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isSaving)
        .accessibilityIdentifier("add-key-sheet")
    }

    private func submit() {
        focused = false
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
