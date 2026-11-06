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
        guard request != nil, phase == .editing, !isResolving, validationMessage == nil else { return false }
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
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L("cancel"))
                        .accessibilityIdentifier("send-cancel")
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                QiqTextField(placeholder: L("walletSendPlaceholder"), text: $model.input, axis: .vertical)
                    .lineLimit(2...5)
                    .accessibilityIdentifier("send-input")
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        SecondaryButton(title: L("walletPaste"), systemImage: "doc.on.clipboard") { model.paste() }
                            .accessibilityIdentifier("send-paste")
                        SecondaryButton(title: L("walletScan"), systemImage: "qrcode.viewfinder") { showScanner = true }
                            .accessibilityIdentifier("send-scan")
                    }
                }
                if model.isResolving {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L("resolvingAddress")).font(.system(size: 14)).foregroundStyle(AppColors.textSecondary)
                    }
                }
                if let error = model.parseError {
                    message(error, icon: "exclamationmark.circle", color: AppColors.error)
                }
                if model.request != nil { details }
                if let error = model.payError {
                    message(error, icon: "xmark.octagon", color: AppColors.error)
                        .accessibilityIdentifier("send-error")
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: submitTitle, isLoading: model.phase == .paying || model.wallet.isRedeemingCashu, isEnabled: model.canSubmit) {
                focusedAmount = false
                model.submit()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .accessibilityIdentifier("send-submit")
        }
    }

    private var submitTitle: String {
        if case .cashu = model.request { return L("cashuRedeem") }
        guard let amount = model.amountSats else { return L("send") }
        return L("walletPayAmount", ["amount": Sats.format(amount)])
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(model.typeLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppColors.tile, in: Capsule())
                Spacer()
                if !model.needsAmountField, let amount = model.amountSats {
                    Text("\(Sats.format(amount)) \(L("walletSats"))")
                        .font(AppFont.brandSemibold(20))
                        .accessibilityIdentifier("send-amount-fixed")
                }
            }
            Text(model.destination)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(2)
                .textSelection(.enabled)
            if let memo = model.memo, !memo.isEmpty {
                Text(memo).font(.system(size: 15))
            }
            if case .bolt11(_, let invoice) = model.request, invoice.amountMsat != nil, !invoice.isExpired {
                HStack(spacing: 4) {
                    Text(L("walletExpiresIn"))
                    Text(timerInterval: Date()...invoice.expiresAt, countsDown: true)
                        .monospacedDigit()
                }
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
            }
            if model.needsAmountField {
                QiqTextField(placeholder: L("amountInSats"), text: $model.amountText, keyboard: .numberPad)
                    .focused($focusedAmount)
                    .accessibilityIdentifier("send-amount")
                if let params = model.lnurlParams {
                    Text(L("walletAmountRange", ["min": Sats.format(params.minSats), "max": Sats.format(params.maxSats)]))
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            if model.allowsComment {
                QiqTextField(placeholder: L("commentOptional"), text: $model.comment, autocapitalize: true)
                    .accessibilityIdentifier("send-comment")
            }
            if let warning = model.validationMessage {
                message(warning, icon: "exclamationmark.triangle", color: AppColors.warning)
            }
        }
        .padding(16)
        .background(AppColors.overlayLight, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func message(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 13, weight: .medium))
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
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(AppColors.success, in: Circle())
                .scaleEffect(appeared ? 1 : 0.4)
                .opacity(appeared ? 1 : 0)
            Text(title).font(.system(size: 20, weight: .semibold)).multilineTextAlignment(.center)
            Text("\(Sats.format(amount)) \(L("walletSats"))").font(AppFont.brandSemibold(32))
            if let fee, fee > 0 {
                Text("\(L("fee")): \(Sats.format(fee)) \(L("walletSats"))")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            PrimaryButton(title: L("done"), action: onDone)
                .accessibilityIdentifier("payment-success-done")
        }
        .padding(20)
        .onAppear { withAnimation(.spring(duration: 0.45, bounce: 0.4)) { appeared = true } }
        .accessibilityIdentifier("payment-success")
    }
}
