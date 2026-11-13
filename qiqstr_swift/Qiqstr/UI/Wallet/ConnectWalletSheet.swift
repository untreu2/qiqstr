import SwiftUI

@MainActor
@Observable
final class ConnectWalletModel {
    var uri: String
    var accepted = false
    private(set) var isConnecting = false
    private(set) var error: String?
    private(set) var connectedTick = 0

    private(set) var clipboardChangeCount = UIPasteboard.general.changeCount
    private var consumedChangeCount = -1

    init(uri: String?) {
        self.uri = uri ?? ""
        accepted = uri == nil && !WalletService.shared.isConnected && UserDefaults.standard.bool(forKey: WalletService.disclaimerAcceptedKey)
    }

    var clipboardHasContent: Bool {
        clipboardChangeCount != consumedChangeCount && (UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs)
    }

    var highlightsPaste: Bool { clipboardHasContent && !isValid }

    func refreshClipboard() { clipboardChangeCount = UIPasteboard.general.changeCount }

    func pasted(_ values: [String]) {
        consumedChangeCount = UIPasteboard.general.changeCount
        refreshClipboard()
        guard let text = values.first(where: { WalletService.isWalletConnectURI($0) }) ?? values.first else { return }
        uri = text.trimmingCharacters(in: .whitespacesAndNewlines)
        error = nil
    }

    func receive(_ incoming: String?) {
        guard let incoming else { return }
        uri = incoming
        error = nil
    }

    var trimmed: String { uri.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isValid: Bool { !trimmed.isEmpty && WalletService.shared.validate(uri: trimmed) }
    var showsInvalid: Bool { !trimmed.isEmpty && !isValid }
    var canConnect: Bool { isValid && accepted && !isConnecting }

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
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: ConnectWalletModel
    @State private var wallet = WalletService.shared
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
                    inputButtons
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text(L("nwcConnectionString"))
                } footer: {
                    if model.showsInvalid {
                        Label(L("nwcInvalidConnectionString"), systemImage: "exclamationmark.circle")
                            .foregroundStyle(AppColors.error)
                    } else if model.isValid {
                        Label(L("walletConnectionLooksGood"), systemImage: "checkmark.circle")
                            .foregroundStyle(AppColors.success)
                    } else if model.highlightsPaste {
                        Text(L("walletClipboardReady"))
                    } else {
                        Text(L("walletNwcConnectDescription"))
                    }
                }
                if WalletService.shared.isConnected {
                    Section {
                        Label(L("walletReplaceWarning", ["wallet": WalletService.shared.walletName ?? WalletService.shared.lightningAddress ?? L("wallet")]), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(AppColors.error)
                            .accessibilityIdentifier("wallet-connect-replace-warning")
                    }
                }
                if !model.isValid {
                    Section {
                        ForEach(WalletProvider.oneTap) { WalletProviderRow(provider: $0) }
                    } header: {
                        Text(L("walletConnectWithApp"))
                    } footer: {
                        Text(L("walletConnectWithAppFooter"))
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
            .animation(.snappy, value: model.isValid)
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
        .sensoryFeedback(.selection, trigger: model.isValid)
        .onAppear {
            model.refreshClipboard()
            model.receive(wallet.consumeIncomingConnectURI())
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshClipboard() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            model.refreshClipboard()
        }
        .onChange(of: wallet.incomingConnectURI) { _, uri in
            if uri != nil { model.receive(wallet.consumeIncomingConnectURI()) }
        }
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerView { model.uri = $0 }
        }
    }

    private var inputButtons: some View {
        HStack(spacing: 10) {
            PasteButton(payloadType: String.self) { model.pasted($0) }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .tint(model.highlightsPaste ? Color(uiColor: .label) : Color(uiColor: .systemGray))
                .symbolEffect(.pulse, isActive: model.highlightsPaste)
                .accessibilityIdentifier("wallet-connect-paste")
            Button { showScanner = true } label: {
                Label(L("walletScan"), systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityIdentifier("wallet-connect-scan-sheet")
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: model.highlightsPaste)
    }
}
