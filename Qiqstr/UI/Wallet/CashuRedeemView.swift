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
        VStack(alignment: .leading, spacing: 16) {
            Text(L("walletCashuRedeemDescription"))
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            QiqTextField(placeholder: L("cashuTokenHint"), text: $model.token, axis: .vertical)
                .lineLimit(3...6)
                .accessibilityIdentifier("cashu-token")
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    SecondaryButton(title: L("walletPaste"), systemImage: "doc.on.clipboard") { model.paste() }
                        .accessibilityIdentifier("cashu-paste")
                    SecondaryButton(title: L("walletScan"), systemImage: "qrcode.viewfinder") { showScanner = true }
                        .accessibilityIdentifier("cashu-scan")
                }
            }
            if let decoded = model.decoded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("amount")).foregroundStyle(AppColors.textSecondary)
                        Spacer()
                        Text("\(Sats.format(decoded.amountSats)) \(L("walletSats"))").font(AppFont.brandSemibold(18))
                    }
                    HStack(alignment: .top) {
                        Text(L("cashuMintUrl")).foregroundStyle(AppColors.textSecondary)
                        Spacer()
                        Text(decoded.mintUrl).font(.system(size: 13, design: .monospaced)).multilineTextAlignment(.trailing).lineLimit(2)
                    }
                }
                .font(.system(size: 14))
                .padding(16)
                .background(AppColors.overlayLight, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityIdentifier("cashu-decoded")
            } else if model.isInvalid {
                Label(L("cashuInvalidToken"), systemImage: "exclamationmark.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.error)
            }
            if !model.hasToken && model.wallet.cashuBalanceSats > 0 {
                Label(L("walletCashuPending", ["amount": Sats.format(model.wallet.cashuBalanceSats)]), systemImage: "banknote")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
            if !model.wallet.isConnected {
                Label(L("cashuNoWallet"), systemImage: "bolt.slash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.error)
            }
            if let error = model.error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("cashu-error")
            }
            PrimaryButton(
                title: model.wallet.isRedeemingCashu ? L("cashuRedeeming") : (model.hasToken || model.wallet.cashuBalanceSats == 0 ? L("cashuRedeem") : L("cashuMeltAll")),
                isLoading: model.wallet.isRedeemingCashu,
                isEnabled: model.canRedeem
            ) { model.submit() }
            .accessibilityIdentifier("cashu-redeem")
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
            ScrollView {
                CashuRedeemForm(model: model) { dismiss() }
                    .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L("cashuToken"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L("cancel"))
                        .accessibilityIdentifier("cashu-cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(model.wallet.isRedeemingCashu)
    }
}
