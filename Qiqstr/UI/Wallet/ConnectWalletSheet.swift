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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(L("walletNwcConnectDescription"))
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    QiqTextField(placeholder: L("nwcConnectionString"), text: $model.uri, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("wallet-connect-uri")
                    if model.showsInvalid {
                        Label(L("nwcInvalidConnectionString"), systemImage: "exclamationmark.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.error)
                    } else if model.isValid {
                        Label(L("walletConnectionLooksGood"), systemImage: "checkmark.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.success)
                    }
                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            SecondaryButton(title: L("walletPaste"), systemImage: "doc.on.clipboard") { model.paste() }
                                .accessibilityIdentifier("wallet-connect-paste")
                            SecondaryButton(title: L("walletScan"), systemImage: "qrcode.viewfinder") { showScanner = true }
                                .accessibilityIdentifier("wallet-connect-scan-sheet")
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("nwcDisclaimer"))
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle(L("nwcAccept"), isOn: $model.accepted)
                            .font(.system(size: 15, weight: .medium))
                            .tint(AppColors.switchActive)
                            .accessibilityIdentifier("wallet-connect-accept")
                    }
                    .padding(16)
                    .background(AppColors.overlayLight, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    if let error = model.error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.error)
                            .accessibilityIdentifier("wallet-connect-error")
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: L("nwcConnect"), isLoading: model.isConnecting, isEnabled: model.canConnect) {
                    Task { if await model.connect() { dismiss() } }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .accessibilityIdentifier("wallet-connect-submit")
            }
            .navigationTitle(L("nwcTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L("cancel"))
                        .accessibilityIdentifier("wallet-connect-cancel")
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
