import SwiftUI

@MainActor
@Observable
final class ReceiveViewModel {
    enum Mode: Hashable { case invoice, token }

    var mode: Mode = .invoice
    var amountText = ""
    var descriptionText = ""
    private(set) var invoice: CreatedInvoice?
    private(set) var isCreating = false
    private(set) var error: String?
    private(set) var isPaid = false
    private(set) var copiedTick = 0

    var wallet: WalletService { WalletService.shared }

    var amount: Int? {
        guard let value = Int(amountText.filter(\.isNumber)), value > 0 else { return nil }
        return value
    }

    var canCreate: Bool { amount != nil && !isCreating && wallet.isConnected }

    var qrContent: String? {
        if let invoice { return "lightning:\(invoice.invoice)" }
        if let address = wallet.lightningAddress, amountText.isEmpty { return "lightning:\(address)" }
        return nil
    }

    private(set) var isExpired = false

    func create() async {
        guard let amount else { return }
        isCreating = true
        error = nil
        defer { isCreating = false }
        do {
            invoice = try await wallet.makeInvoice(amount: amount, description: descriptionText)
            isPaid = false
            isExpired = false
        } catch {
            self.error = L("failedToCreateInvoice", ["message": coreMessage(error)])
        }
    }

    func reset() {
        invoice = nil
        isPaid = false
        isExpired = false
        error = nil
    }

    func copy(_ text: String) {
        UIPasteboard.general.string = text
        copiedTick += 1
        ToastCenter.shared.show(L("copiedToClipboard"), style: .success)
    }

    func watch() async {
        guard let invoice else { return }
        while !Task.isCancelled && !isPaid {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, self.invoice == invoice else { return }
            if let expiry = invoice.expiresAt, expiry < Date() {
                isExpired = true
                return
            }
            if await wallet.isInvoicePaid(invoice), self.invoice == invoice {
                isPaid = true
                ToastCenter.shared.show(L("paymentReceived"), style: .success)
            }
        }
    }
}

struct ReceiveView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = ReceiveViewModel()
    @State private var cashuModel = CashuRedeemModel(token: nil)
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Picker(L("receive"), selection: $model.mode) {
                    Text(L("invoice")).tag(ReceiveViewModel.Mode.invoice)
                    Text(L("token")).tag(ReceiveViewModel.Mode.token)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("receive-mode")
                if !model.wallet.isConnected {
                    EmptyStateView(systemImage: "bolt.slash", title: L("pleaseConnectWalletFirst"))
                } else if model.mode == .invoice {
                    invoiceContent
                } else {
                    CashuRedeemForm(model: cashuModel) { dismiss() }
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColors.background)
        .navigationTitle(L("receive"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.invoice != nil && !model.isPaid {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                        .accessibilityLabel(L("walletNewInvoice"))
                        .accessibilityIdentifier("receive-new-invoice")
                }
            }
        }
        .task(id: model.invoice) { await model.watch() }
        .sensoryFeedback(.success, trigger: model.isPaid) { _, paid in paid }
        .sensoryFeedback(.success, trigger: model.copiedTick)
        .onChange(of: model.isPaid) { _, paid in
            guard paid else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                dismiss()
            }
        }
        .accessibilityIdentifier("receive-view")
    }

    @ViewBuilder private var invoiceContent: some View {
        if model.isPaid, let invoice = model.invoice {
            PaymentSuccessView(title: L("paymentReceived"), amount: invoice.amountSats, fee: nil) { dismiss() }
                .frame(minHeight: 420)
        } else if let invoice = model.invoice {
            invoiceCard(invoice)
        } else {
            qrPlaceholder
            form
        }
    }

    @ViewBuilder private var qrPlaceholder: some View {
        if let content = model.qrContent, let address = model.wallet.lightningAddress {
            VStack(spacing: 12) {
                Button { model.copy(address) } label: { QRCodeView(content: content, size: 220) }
                    .buttonStyle(PressableStyle())
                Label(address, systemImage: "bolt.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityIdentifier("receive-lightning-address")
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "qrcode")
                    .font(.system(size: 72))
                    .foregroundStyle(AppColors.textSecondary.opacity(0.25))
                Text(L("enterAmountToGenerateInvoice"))
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            QiqTextField(placeholder: L("amountInSats"), text: $model.amountText, keyboard: .numberPad)
                .focused($focused)
                .accessibilityIdentifier("receive-amount")
            QiqTextField(placeholder: L("listDescriptionHint"), text: $model.descriptionText, autocapitalize: true)
                .focused($focused)
                .accessibilityIdentifier("receive-description")
            if let error = model.error {
                Text(error).font(.system(size: 13)).foregroundStyle(AppColors.error).accessibilityIdentifier("receive-error")
            }
            PrimaryButton(title: L("walletCreateInvoice"), isLoading: model.isCreating, isEnabled: model.canCreate) {
                focused = false
                Task { await model.create() }
            }
            .padding(.top, 4)
            .accessibilityIdentifier("receive-create")
        }
    }

    private func invoiceCard(_ invoice: CreatedInvoice) -> some View {
        VStack(spacing: 16) {
            Button { model.copy(invoice.invoice) } label: {
                QRCodeView(content: "lightning:\(invoice.invoice)", size: 240)
                    .opacity(model.isExpired ? 0.25 : 1)
            }
            .buttonStyle(PressableStyle())
            .disabled(model.isExpired)
            VStack(spacing: 6) {
                Text("\(Sats.format(invoice.amountSats)) \(L("walletSats"))")
                    .font(AppFont.brandSemibold(30))
                    .accessibilityIdentifier("receive-invoice-amount")
                if let description = invoice.description {
                    Text(description).font(.system(size: 15)).foregroundStyle(AppColors.textSecondary).multilineTextAlignment(.center)
                }
                if model.isExpired {
                    Label(L("walletInvoiceExpired"), systemImage: "clock.badge.xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.error)
                } else if let expiry = invoice.expiresAt {
                    HStack(spacing: 4) {
                        Text(L("walletExpiresIn"))
                        Text(timerInterval: Date()...expiry, countsDown: true).monospacedDigit()
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                }
            }
            Button { model.copy(invoice.invoice) } label: {
                HStack(spacing: 8) {
                    Text(WalletFormat.truncated(invoice.invoice, head: 14, tail: 10))
                        .font(.system(size: 13, design: .monospaced))
                        .lineLimit(1)
                    Image(systemName: "doc.on.doc").font(.system(size: 13))
                }
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("receive-invoice-chip")
            if model.isExpired {
                PrimaryButton(title: L("walletNewInvoice")) { model.reset() }
            } else {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        SecondaryButton(title: L("copy"), systemImage: "doc.on.doc") { model.copy(invoice.invoice) }
                            .accessibilityIdentifier("receive-copy")
                        ShareLink(item: invoice.invoice) {
                            Label(L("share"), systemImage: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .accessibilityIdentifier("receive-share")
                    }
                }
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("walletWaitingForPayment")).font(.system(size: 14)).foregroundStyle(AppColors.textSecondary)
                }
                .padding(.top, 4)
                .accessibilityIdentifier("receive-waiting")
            }
        }
    }
}
