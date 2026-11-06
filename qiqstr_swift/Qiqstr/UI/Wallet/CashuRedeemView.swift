import SwiftUI

@MainActor
@Observable
final class CashuRedeemModel {
    var token: String
    var showMeltConfirm = false
    private(set) var decoded: CashuTokenInfo?
    private(set) var isInvalid = false
    private(set) var error: String?
    private(set) var redeemedAmount: Int?

    var wallet: WalletService { WalletService.shared }

    init(token: String?) {
        self.token = token ?? ""
        decode()
    }

    var hasToken: Bool { !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canRedeem: Bool { wallet.isConnected && !wallet.isRedeemingCashu && (decoded != nil || (!hasToken && wallet.cashuBalanceSats > 0)) }

    func decode() {
        error = nil
        guard hasToken else {
            decoded = nil
            isInvalid = false
            return
        }
        decoded = wallet.decodeCashu(token)
        isInvalid = decoded == nil
    }

    func paste() {
        if let text = UIPasteboard.general.string { token = text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func submit() {
        if hasToken {
            Task { await redeem() }
        } else {
            showMeltConfirm = true
        }
    }

    func redeem() async {
        guard let decoded else { return }
        error = nil
        do {
            let sats = try await wallet.redeemCashu(token: decoded.token)
            finish(L("cashuRedeemSuccess", ["amount": Sats.format(sats)]), sats)
        } catch {
            self.error = coreMessage(error)
        }
    }

    func meltAll() async {
        error = nil
        do {
            let sats = try await wallet.meltAllCashu()
            finish(L("cashuMeltAllSuccess", ["amount": Sats.format(sats)]), sats)
        } catch {
            self.error = coreMessage(error)
        }
    }

    private func finish(_ message: String, _ sats: Int) {
        token = ""
        decoded = nil
        redeemedAmount = sats
        ToastCenter.shared.show(message, style: .success)
    }
}

struct CashuRedeemForm: View {
    @Bindable var model: CashuRedeemModel
    var onFinished: (() -> Void)?
    @State private var showScanner = false

    var body: some View {
        Section {
            TextField(L("cashuTokenHint"), text: $model.token, axis: .vertical)
                .lineLimit(3...6)
                .font(.body.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("cashu-token")
            Button { model.paste() } label: { Label(L("walletPaste"), systemImage: "doc.on.clipboard") }
                .accessibilityIdentifier("cashu-paste")
            Button { showScanner = true } label: { Label(L("walletScan"), systemImage: "qrcode.viewfinder") }
                .accessibilityIdentifier("cashu-scan")
            if let decoded = model.decoded {
                Group {
                    LabeledContent(L("amount")) {
                        Text(verbatim: "\(Sats.format(decoded.amountSats)) \(L("walletSats"))")
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    LabeledContent(L("cashuMintUrl")) {
                        Text(decoded.mintUrl)
                            .font(.footnote.monospaced())
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                    }
                }
                .accessibilityIdentifier("cashu-decoded")
            }
            if !model.hasToken && model.wallet.cashuBalanceSats > 0 {
                Label(L("walletCashuPending", ["amount": Sats.format(model.wallet.cashuBalanceSats)]), systemImage: "banknote")
                    .foregroundStyle(.secondary)
            }
            Button { model.submit() } label: {
                HStack {
                    Label(model.wallet.isRedeemingCashu ? L("cashuRedeeming") : (model.hasToken || model.wallet.cashuBalanceSats == 0 ? L("cashuRedeem") : L("cashuMeltAll")), systemImage: "arrow.down.circle")
                    Spacer()
                    if model.wallet.isRedeemingCashu { ProgressView() }
                }
            }
            .disabled(!model.canRedeem)
            .accessibilityIdentifier("cashu-redeem")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if model.decoded == nil && model.isInvalid {
                    Label(L("cashuInvalidToken"), systemImage: "exclamationmark.circle")
                        .foregroundStyle(AppColors.error)
                }
                if !model.wallet.isConnected {
                    Label(L("cashuNoWallet"), systemImage: "bolt.slash")
                        .foregroundStyle(AppColors.error)
                }
                if let error = model.error {
                    Text(error)
                        .foregroundStyle(AppColors.error)
                        .accessibilityIdentifier("cashu-error")
                }
                Text(L("walletCashuRedeemDescription"))
            }
        }
        .onChange(of: model.token) { model.decode() }
        .onChange(of: model.redeemedAmount) { _, amount in
            guard amount != nil, let onFinished else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                onFinished()
            }
        }
        .sensoryFeedback(.success, trigger: model.redeemedAmount)
        .sensoryFeedback(.error, trigger: model.error)
        .confirmationDialog(L("cashuMeltAll"), isPresented: $model.showMeltConfirm, titleVisibility: .visible) {
            Button(L("cashuMeltAll")) { Task { await model.meltAll() } }
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(L("walletMeltAllConfirm", ["amount": Sats.format(model.wallet.cashuBalanceSats)]))
        }
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerView { model.token = $0 }
        }
        .task { await model.wallet.refreshCashuBalance() }
    }
}

struct CashuRedeemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: CashuRedeemModel

    init(initialToken: String?) {
        _model = State(initialValue: CashuRedeemModel(token: initialToken))
    }

    var body: some View {
        NavigationStack {
            Form {
                CashuRedeemForm(model: model) { dismiss() }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L("cashuToken"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                        .accessibilityLabel(L("cancel"))
                        .accessibilityIdentifier("cashu-cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(model.wallet.isRedeemingCashu)
    }
}
