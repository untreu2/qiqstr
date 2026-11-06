import SwiftUI

@MainActor
@Observable
final class ConnectWalletModel {
    var uri: String
    var accepted = false
    private(set) var isConnecting = false
    private(set) var error: String?
    private(set) var connectedTick = 0

    init(uri: String?) { self.uri = uri ?? "" }

    var trimmed: String { uri.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isValid: Bool { !trimmed.isEmpty && WalletService.shared.validate(uri: trimmed) }
    var showsInvalid: Bool { !trimmed.isEmpty && !isValid }
    var canConnect: Bool { isValid && accepted && !isConnecting }

    func paste() {
        if let text = UIPasteboard.general.string { uri = text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func connect() async -> Bool {
        guard !trimmed.isEmpty else {
            error = L("nwcPleaseEnterConnectionString")
            return false
        }
        guard isValid else {
            error = L("nwcInvalidConnectionString")
            return false
        }
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await WalletService.shared.connect(uri: trimmed)
            connectedTick += 1
            ToastCenter.shared.show(L("nwcConnectionSaved"), style: .success)
            return true
        } catch {
            self.error = coreMessage(error)
            return false
        }
    }
}

struct ConnectWalletSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ConnectWalletModel
    @State private var showScanner = false

    init(initialURI: String?) {
        _model = State(initialValue: ConnectWalletModel(uri: initialURI))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("nwcConnectionString"), text: $model.uri, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("wallet-connect-uri")
                    Button { model.paste() } label: { Label(L("walletPaste"), systemImage: "doc.on.clipboard") }
                        .accessibilityIdentifier("wallet-connect-paste")
                    Button { showScanner = true } label: { Label(L("walletScan"), systemImage: "qrcode.viewfinder") }
                        .accessibilityIdentifier("wallet-connect-scan-sheet")
                } header: {
                    Text(L("nwcConnectionString"))
                } footer: {
                    if model.showsInvalid {
                        Label(L("nwcInvalidConnectionString"), systemImage: "exclamationmark.circle")
                            .foregroundStyle(AppColors.error)
                    } else if model.isValid {
                        Label(L("walletConnectionLooksGood"), systemImage: "checkmark.circle")
                            .foregroundStyle(AppColors.success)
                    } else {
                        Text(L("walletNwcConnectDescription"))
                    }
                }
                Section {
                    Toggle(L("nwcAccept"), isOn: $model.accepted)
                        .tint(AppColors.switchActive)
                        .accessibilityIdentifier("wallet-connect-accept")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("nwcDisclaimer"))
                        if let error = model.error {
                            Text(error)
                                .foregroundStyle(AppColors.error)
                                .accessibilityIdentifier("wallet-connect-error")
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L("nwcTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                        .accessibilityLabel(L("cancel"))
                        .accessibilityIdentifier("wallet-connect-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { if await model.connect() { dismiss() } }
                    } label: {
                        if model.isConnecting {
                            ProgressView()
                        } else {
                            Text(L("nwcConnect")).fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .foregroundStyle(AppColors.background)
                    .disabled(!model.canConnect || model.isConnecting)
                    .accessibilityIdentifier("wallet-connect-submit")
                }
            }
        }
        .presentationDetents([.large])
        .sensoryFeedback(.success, trigger: model.connectedTick)
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerView { model.uri = $0 }
        }
    }
}
