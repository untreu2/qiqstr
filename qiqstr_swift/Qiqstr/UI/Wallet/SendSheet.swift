import SwiftUI

@MainActor
@Observable
final class SendViewModel {
    enum Phase: Equatable {
        case editing
        case paying
        case sent(amount: Int, fee: Int)
        case redeemed(amount: Int)
    }

    var input: String
    var amountText = ""
    var comment = ""
    var showConfirm = false
    private(set) var request: PaymentRequest?
    private(set) var lnurlParams: LnurlPayParams?
    private(set) var isResolving = false
    private(set) var parseError: String?
    private(set) var payError: String?
    private(set) var phase: Phase = .editing
    private(set) var failureTick = 0
    private(set) var paymentMayHaveSettled = false
    private var settledInput: String?

    var wallet: WalletService { WalletService.shared }

    init(input: String?) { self.input = input ?? "" }

    var trimmedInput: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }

    var amountSats: Int? {
        if case .bolt11(_, let invoice) = request, let sats = invoice.amountSats { return sats }
        if case .cashu(let info) = request { return info.amountSats }
        guard let value = Int(amountText.filter(\.isNumber)), value > 0 else { return nil }
        return value
    }

    var needsAmountField: Bool {
        switch request {
        case .lightningAddress, .lnurl: !(lnurlParams?.isFixedAmount ?? false)
        default: false
        }
    }

    var allowsComment: Bool { (lnurlParams?.commentAllowed ?? 0) > 0 }

    var destination: String {
        switch request {
        case .bolt11(let raw, _): WalletFormat.truncated(raw)
        case .lightningAddress(let address): address
        case .lnurl(let url): url.host() ?? url.absoluteString
        case .cashu(let info): info.mintUrl
        case nil: ""
        }
    }

    var typeLabel: String {
        switch request {
        case .bolt11: L("walletTypeInvoice")
        case .lightningAddress: L("lightningAddress")
        case .lnurl: L("walletTypeLnurl")
        case .cashu: L("cashuToken")
        case nil: ""
        }
    }

    var memo: String? {
        switch request {
        case .bolt11(_, let invoice): invoice.description
        case .lightningAddress, .lnurl: lnurlParams?.description
        default: nil
        }
    }

    var validationMessage: String? {
        if case .bolt11(_, let invoice) = request {
            if invoice.amountMsat == nil { return L("walletAmountlessInvoice") }
            if invoice.isExpired { return L("walletInvoiceExpired") }
            if !invoice.isMainnet { return L("walletWrongNetwork") }
        }
        if needsAmountField, let params = lnurlParams, let sats = amountSats, sats < params.minSats || sats > params.maxSats {
            return WalletError.amountOutOfRange(min: params.minSats, max: params.maxSats).errorDescription
        }
        return nil
    }

    var canSubmit: Bool {
        guard request != nil, phase == .editing, !isResolving, !paymentMayHaveSettled, validationMessage == nil else { return false }
        if case .cashu = request { return !wallet.isRedeemingCashu }
        if case .lightningAddress = request, lnurlParams == nil { return false }
        if case .lnurl = request, lnurlParams == nil { return false }
        return amountSats != nil
    }

    func paste() {
        if let text = UIPasteboard.general.string { input = text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func parse() async {
        let text = trimmedInput
        if paymentMayHaveSettled {
            if text == settledInput { return }
            paymentMayHaveSettled = false
            settledInput = nil
        }
        payError = nil
        guard !text.isEmpty else {
            request = nil
            lnurlParams = nil
            parseError = nil
            isResolving = false
            return
        }
        guard let parsed = wallet.resolve(text) else {
            request = nil
            lnurlParams = nil
            parseError = CashuTokenInfo.looksLikeToken(text) ? L("cashuInvalidToken") : L("unrecognizedPaymentFormat")
            return
        }
        let needsParams: Bool
        switch parsed {
        case .lightningAddress, .lnurl: needsParams = true
        default: needsParams = false
        }
        if parsed == request && (!needsParams || lnurlParams != nil) { return }
        parseError = nil
        request = parsed
        lnurlParams = nil
        switch parsed {
        case .lightningAddress(let address): await resolveParams { try await Lnurl.payParams(address: address) }
        case .lnurl(let url): await resolveParams { try await Lnurl.payParams(url: url) }
        default: break
        }
    }

    private func resolveParams(_ fetch: () async throws -> LnurlPayParams) async {
        isResolving = true
        defer { isResolving = false }
        do {
            let params = try await fetch()
            guard !Task.isCancelled else { return }
            lnurlParams = params
            if params.isFixedAmount { amountText = String(params.minSats) }
        } catch {
            guard !Task.isCancelled else { return }
            parseError = coreMessage(error)
        }
    }

    func submit() {
        guard canSubmit else { return }
        if case .cashu = request {
            Task { await redeem() }
        } else {
            showConfirm = true
        }
    }

    func pay() async {
        guard let request, let amount = amountSats else { return }
        phase = .paying
        payError = nil
        do {
            let result: PaymentResult
            switch request {
            case .bolt11(let raw, _): result = try await wallet.payBolt11(raw)
            case .lightningAddress, .lnurl:
                guard let params = lnurlParams else { throw WalletError.resolveFailed }
                result = try await wallet.pay(params: params, amountSats: amount, comment: comment)
            case .cashu: return
            }
            phase = .sent(amount: amount, fee: result.feesSats)
        } catch WalletError.paymentPending {
            phase = .editing
            paymentMayHaveSettled = true
            settledInput = trimmedInput
            payError = L("walletPaymentPending")
            failureTick += 1
        } catch {
            phase = .editing
            payError = "\(L("paymentFailed")): \(coreMessage(error))"
            failureTick += 1
        }
    }

    func redeem() async {
        guard case .cashu(let info) = request else { return }
        phase = .paying
        payError = nil
        do {
            let sats = try await wallet.redeemCashu(token: info.token)
            phase = .redeemed(amount: sats)
        } catch {
            phase = .editing
            payError = coreMessage(error)
            failureTick += 1
        }
    }
}

struct SendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: SendViewModel
    @State private var showScanner = false
    @FocusState private var focusedAmount: Bool

    init(initialInput: String?) {
        _model = State(initialValue: SendViewModel(input: initialInput))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .sent(let amount, let fee):
                    PaymentSuccessView(title: L("paymentSent"), amount: amount, fee: fee) { dismiss() }
                case .redeemed(let amount):
                    PaymentSuccessView(title: L("cashuRedeemSuccess", ["amount": Sats.format(amount)]), amount: amount, fee: nil) { dismiss() }
                default:
                    form
                }
            }
            .navigationTitle(L("send"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                        .disabled(model.phase == .paying)
                        .accessibilityLabel(L("cancel"))
                        .accessibilityIdentifier("send-cancel")
                }
                if model.phase == .editing || model.phase == .paying {
                    ToolbarItem(placement: .confirmationAction) {
                        if model.phase == .paying || model.wallet.isRedeemingCashu {
                            ProgressView()
                        } else {
                            Button(submitShortTitle) {
                                focusedAmount = false
                                model.submit()
                            }
                            .buttonStyle(.glassProminent)
                            .foregroundStyle(AppColors.background)
                            .disabled(!model.canSubmit)
                            .accessibilityIdentifier("send-submit")
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(model.phase == .paying)
        .task(id: model.trimmedInput) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await model.parse()
        }
        .sensoryFeedback(.error, trigger: model.failureTick)
        .sensoryFeedback(.success, trigger: model.phase) { _, new in
            if case .sent = new { return true }
            if case .redeemed = new { return true }
            return false
        }
        .confirmationDialog(L("walletConfirmPayment"), isPresented: $model.showConfirm, titleVisibility: .visible) {
            Button(L("walletPayAmount", ["amount": Sats.format(model.amountSats ?? 0)])) { Task { await model.pay() } }
                .accessibilityIdentifier("send-confirm")
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(L("walletConfirmPaymentMessage", ["amount": Sats.format(model.amountSats ?? 0), "destination": model.destination]))
        }
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerView { model.input = $0 }
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField(L("walletSendPlaceholder"), text: $model.input, axis: .vertical)
                    .lineLimit(2...5)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("send-input")
                Button { model.paste() } label: { Label(L("walletPaste"), systemImage: "doc.on.clipboard") }
                    .accessibilityIdentifier("send-paste")
                Button { showScanner = true } label: { Label(L("walletScan"), systemImage: "qrcode.viewfinder") }
                    .accessibilityIdentifier("send-scan")
            } footer: {
                if model.isResolving {
                    Label(L("resolvingAddress"), systemImage: "ellipsis")
                        .symbolEffect(.variableColor.iterative)
                } else if let error = model.parseError {
                    message(error, icon: "exclamationmark.circle", color: AppColors.error)
                }
            }
            if model.request != nil { details }
            if let error = model.payError {
                Section {
                    message(error, icon: "xmark.octagon", color: AppColors.error)
                        .accessibilityIdentifier("send-error")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var submitShortTitle: String {
        if case .cashu = model.request { return L("cashuRedeem") }
        return L("send")
    }

    @ViewBuilder
    private var details: some View {
        Section {
            LabeledContent(model.typeLabel) {
                Text(model.destination)
                    .font(.subheadline.monospaced())
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            if !model.needsAmountField, let amount = model.amountSats {
                LabeledContent(L("amount")) {
                    Text(verbatim: "\(Sats.format(amount)) \(L("walletSats"))")
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("send-amount-fixed")
                }
            }
            if let memo = model.memo, !memo.isEmpty {
                LabeledContent(L("description"), value: memo)
            }
            if case .bolt11(_, let invoice) = model.request, invoice.amountMsat != nil, !invoice.isExpired {
                LabeledContent(L("walletExpiresIn")) {
                    Text(timerInterval: Date()...invoice.expiresAt, countsDown: true)
                        .monospacedDigit()
                }
            }
        } footer: {
            if let warning = model.validationMessage {
                message(warning, icon: "exclamationmark.triangle", color: AppColors.warning)
            }
        }
        if model.needsAmountField || model.allowsComment {
            Section {
                if model.needsAmountField {
                    LabeledContent(L("amountInSats")) {
                        TextField(L("walletSats"), text: $model.amountText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .focused($focusedAmount)
                            .accessibilityIdentifier("send-amount")
                    }
                }
                if model.allowsComment {
                    TextField(L("commentOptional"), text: $model.comment, axis: .vertical)
                        .accessibilityIdentifier("send-comment")
                }
            } footer: {
                if model.needsAmountField, let params = model.lnurlParams {
                    Text(L("walletAmountRange", ["min": Sats.format(params.minSats), "max": Sats.format(params.maxSats)]))
                }
            }
        }
    }

    private func message(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.footnote)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct PaymentSuccessView: View {
    let title: String
    let amount: Int
    let fee: Int?
    let onDone: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .imageScale(.large)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, AppColors.success)
                .scaleEffect(1.6)
                .offset(y: appeared ? 0 : 8)
                .opacity(appeared ? 1 : 0)
                .padding(.bottom, 16)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(verbatim: "\(Sats.format(amount)) \(L("walletSats"))")
                .font(.largeTitle.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
            if let fee, fee > 0 {
                Text(verbatim: "\(L("fee")): \(Sats.format(fee)) \(L("walletSats"))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            PrimaryButton(title: L("done"), action: onDone)
                .accessibilityIdentifier("payment-success-done")
        }
        .padding(20)
        .onAppear { withAnimation(.easeOut(duration: 0.25)) { appeared = true } }
        .accessibilityIdentifier("payment-success")
    }
}
