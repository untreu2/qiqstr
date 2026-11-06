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
        Form {
            Section {
                Picker(L("receive"), selection: $model.mode) {
                    Text(L("invoice")).tag(ReceiveViewModel.Mode.invoice)
                    Text(L("token")).tag(ReceiveViewModel.Mode.token)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("receive-mode")
            }
            if !model.wallet.isConnected {
                Section {
                    EmptyStateView(systemImage: "bolt.slash", title: L("pleaseConnectWalletFirst"))
                        .listRowBackground(Color.clear)
                }
            } else if model.mode == .invoice {
                invoiceContent
            } else {
                CashuRedeemForm(model: cashuModel) { dismiss() }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(L("receive"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.invoice != nil && !model.isPaid {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("walletNewInvoice"), systemImage: "arrow.counterclockwise") { model.reset() }
                        .accessibilityIdentifier("receive-new-invoice")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("done")) { focused = false }
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
            Section {
                PaymentSuccessView(title: L("paymentReceived"), amount: invoice.amountSats, fee: nil) { dismiss() }
                    .frame(minHeight: 420)
                    .listRowBackground(Color.clear)
            }
        } else if let invoice = model.invoice {
            invoiceSections(invoice)
        } else {
            qrPlaceholder
            form
        }
    }

    @ViewBuilder private var qrPlaceholder: some View {
        if let content = model.qrContent, let address = model.wallet.lightningAddress {
            Section {
                VStack(spacing: 12) {
                    Button { model.copy(address) } label: { QRCodeView(content: content, size: 200) }
                        .buttonStyle(PressableStyle())
                    Label(address, systemImage: "bolt.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("receive-lightning-address")
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
    }

    private var form: some View {
        Section {
            LabeledContent(L("amountInSats")) {
                TextField(L("walletSats"), text: $model.amountText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($focused)
                    .accessibilityIdentifier("receive-amount")
            }
            TextField(L("listDescriptionHint"), text: $model.descriptionText, axis: .vertical)
                .focused($focused)
                .accessibilityIdentifier("receive-description")
            Button {
                focused = false
                Task { await model.create() }
            } label: {
                HStack {
                    Label(L("walletCreateInvoice"), systemImage: "qrcode")
                    Spacer()
                    if model.isCreating { ProgressView() }
                }
            }
            .disabled(!model.canCreate)
            .accessibilityIdentifier("receive-create")
        } footer: {
            if let error = model.error {
                Text(error).foregroundStyle(AppColors.error).accessibilityIdentifier("receive-error")
            } else if model.qrContent == nil {
                Text(L("enterAmountToGenerateInvoice"))
            }
        }
    }

    @ViewBuilder
    private func invoiceSections(_ invoice: CreatedInvoice) -> some View {
        Section {
            VStack(spacing: 14) {
                Button { model.copy(invoice.invoice) } label: {
                    QRCodeView(content: "lightning:\(invoice.invoice)", size: 220)
                        .opacity(model.isExpired ? 0.25 : 1)
                }
                .buttonStyle(PressableStyle())
                .disabled(model.isExpired)
                Text(verbatim: "\(Sats.format(invoice.amountSats)) \(L("walletSats"))")
                    .font(.title.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .accessibilityIdentifier("receive-invoice-amount")
                if let description = invoice.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
        Section {
            if model.isExpired {
                Label(L("walletInvoiceExpired"), systemImage: "clock.badge.xmark")
                    .foregroundStyle(AppColors.error)
                Button { model.reset() } label: { Label(L("walletNewInvoice"), systemImage: "arrow.counterclockwise") }
            } else {
                if let expiry = invoice.expiresAt {
                    LabeledContent(L("walletExpiresIn")) {
                        Text(timerInterval: Date()...expiry, countsDown: true).monospacedDigit()
                    }
                }
                Button { model.copy(invoice.invoice) } label: {
                    LabeledContent {
                        Text(WalletFormat.truncated(invoice.invoice, head: 10, tail: 8))
                            .font(.footnote.monospaced())
                            .lineLimit(1)
                    } label: {
                        Label(L("copy"), systemImage: "doc.on.doc")
                    }
                }
                .accessibilityIdentifier("receive-copy")
                ShareLink(item: invoice.invoice) {
                    Label(L("share"), systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("receive-share")
            }
        } footer: {
            if !model.isExpired {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("walletWaitingForPayment"))
                }
                .accessibilityIdentifier("receive-waiting")
            }
        }
    }
}
