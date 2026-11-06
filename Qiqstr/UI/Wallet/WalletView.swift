import SwiftUI

enum WalletSheet: Identifiable {
    case connect(String?)
    case send(String?)
    case cashu(String?)
    case payment(WalletTransaction)

    var id: String {
        switch self {
        case .connect: "connect"
        case .send: "send"
        case .cashu: "cashu"
        case .payment(let tx): "payment-\(tx.id)"
        }
    }
}

@MainActor
@Observable
final class WalletViewModel {
    static let collapsedTransactionCount = 5

    var sheet: WalletSheet?
    var showScanner = false
    var showDisconnectConfirm = false
    var showMeltConfirm = false
    var showAllTransactions = false
    var refreshTick = 0
    private var pendingScan: String?

    var wallet: WalletService { WalletService.shared }

    var visibleTransactions: [WalletTransaction] {
        showAllTransactions ? wallet.transactions : Array(wallet.transactions.prefix(Self.collapsedTransactionCount))
    }

    var hasHiddenTransactions: Bool { wallet.transactions.count > Self.collapsedTransactionCount }

    func receive() { Router.shared.push(.walletReceive) }

    func scanned(_ code: String) { pendingScan = code }

    func scannerDismissed() {
        guard let code = pendingScan else { return }
        pendingScan = nil
        if WalletService.isWalletConnectURI(code) {
            sheet = .connect(code)
        } else if !wallet.isConnected {
            ToastCenter.shared.show(L("pleaseConnectWalletFirst"), style: .error)
        } else if CashuTokenInfo.looksLikeToken(code) {
            sheet = .cashu(code)
        } else {
            sheet = .send(code)
        }
    }

    func refresh() async {
        await wallet.refresh()
        refreshTick += 1
    }

    func disconnect() {
        wallet.disconnect()
        showAllTransactions = false
        ToastCenter.shared.show(L("nwcDisconnected"))
    }

    func meltAll() async {
        do {
            let sats = try await wallet.meltAllCashu()
            ToastCenter.shared.show(L("cashuMeltAllSuccess", ["amount": Sats.format(sats)]), style: .success)
        } catch {
            ToastCenter.shared.error(error)
        }
    }
}

struct WalletView: View {
    @State private var wallet = WalletService.shared
    @State private var model = WalletViewModel()

    var body: some View {
        Group {
            if wallet.isConnected {
                WalletDashboard(model: model)
            } else {
                WalletOnboardingView(model: model)
            }
        }
        .background(AppColors.background)
        .navigationTitle(L("wallet"))
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            if wallet.isConnected {
                ToolbarItem(placement: .topBarTrailing) { menu }
            }
        }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .connect(let uri): ConnectWalletSheet(initialURI: uri)
            case .send(let input): SendSheet(initialInput: input)
            case .cashu(let token): CashuRedeemSheet(initialToken: token)
            case .payment(let tx): PaymentDetailSheet(transaction: tx)
            }
        }
        .fullScreenCover(isPresented: $model.showScanner, onDismiss: model.scannerDismissed) {
            QRScannerView { model.scanned($0) }
        }
        .confirmationDialog(L("walletDisconnectTitle"), isPresented: $model.showDisconnectConfirm, titleVisibility: .visible) {
            Button(L("walletDisconnect"), role: .destructive) { model.disconnect() }
                .accessibilityIdentifier("wallet-disconnect-confirm")
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(L("walletDisconnectMessage"))
        }
        .confirmationDialog(L("cashuMeltAll"), isPresented: $model.showMeltConfirm, titleVisibility: .visible) {
            Button(L("cashuMeltAll")) { Task { await model.meltAll() } }
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(L("walletMeltAllConfirm", ["amount": Sats.format(wallet.cashuBalanceSats)]))
        }
        .sensoryFeedback(.success, trigger: wallet.lastPaymentAt)
    }

    private var menu: some View {
        Menu {
            Button { model.sheet = .cashu(nil) } label: { Label(L("walletReceiveCashu"), systemImage: "banknote") }
                .accessibilityIdentifier("wallet-menu-cashu")
            if wallet.cashuBalanceSats > 0 {
                Button { model.showMeltConfirm = true } label: { Label(L("cashuMeltAll"), systemImage: "bolt") }
                    .disabled(wallet.isRedeemingCashu)
            }
            Button { Task { await model.refresh() } } label: { Label(L("refresh"), systemImage: "arrow.clockwise") }
                .accessibilityIdentifier("wallet-menu-refresh")
            Divider()
            Button(role: .destructive) { model.showDisconnectConfirm = true } label: {
                Label(L("walletDisconnect"), systemImage: "bolt.slash")
            }
            .accessibilityIdentifier("wallet-menu-disconnect")
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(L("walletMore"))
        .accessibilityIdentifier("wallet-menu")
    }
}

struct WalletOnboardingView: View {
    @Bindable var model: WalletViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    IconTile(systemImage: "bolt.fill", size: 64, tint: AppColors.zap)
                    Text(L("nwcTitle"))
                        .font(AppFont.brand(28))
                        .kerning(-0.5)
                    Text(L("walletNwcIntro"))
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 20) {
                    feature("bolt", L("onboardingCoinosFeatureSend"))
                    feature("arrow.down.left", L("walletFeatureReceive"))
                    feature("heart", L("onboardingCoinosFeatureZap"))
                    feature("banknote", L("walletFeatureCashu"))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label(L("walletNwcHowToTitle"), systemImage: "questionmark.circle")
                        .font(.system(size: 15, weight: .semibold))
                    Text(L("walletNwcHowTo"))
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.overlayLight, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                VStack(spacing: 10) {
                    PrimaryButton(title: L("walletConnectWallet")) { model.sheet = .connect(nil) }
                        .accessibilityIdentifier("wallet-connect")
                    SecondaryButton(title: L("scanQRCode"), systemImage: "qrcode.viewfinder") { model.showScanner = true }
                        .accessibilityIdentifier("wallet-connect-scan")
                }
                Text(L("nwcDisclaimer"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("wallet-onboarding")
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(AppColors.overlayLight, in: Circle())
            Text(text).font(.system(size: 16)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct WalletDashboard: View {
    @Bindable var model: WalletViewModel
    @State private var wallet = WalletService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                WalletBalanceCard()
                if wallet.cashuBalanceSats > 0 { cashuRow }
                actions
                transactions
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .refreshable { await model.refresh() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await wallet.refreshBalance()
            }
        }
        .sensoryFeedback(.success, trigger: model.refreshTick)
        .accessibilityIdentifier("wallet-dashboard")
    }

    private var cashuRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "banknote").font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(AppColors.overlayLight, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(L("cashu")).font(.system(size: 15, weight: .semibold))
                Text("\(Sats.format(wallet.cashuBalanceSats)) \(L("walletSats"))").font(.system(size: 13)).foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            Button(L("walletMelt")) { model.showMeltConfirm = true }
                .buttonStyle(.glass)
                .disabled(wallet.isRedeemingCashu)
                .accessibilityIdentifier("wallet-cashu-melt")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.overlayLight, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var actions: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                action(L("receive"), "arrow.down.left", id: "wallet-receive") { model.receive() }
                action(L("send"), "arrow.up.right", id: "wallet-send") { model.sheet = .send(nil) }
                action(L("walletScan"), "qrcode.viewfinder", id: "wallet-scan") { model.showScanner = true }
            }
        }
    }

    private func action(_ title: String, _ icon: String, id: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(AppColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 24))
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private var transactions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("recentTransactions"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                if wallet.isLoadingTransactions && wallet.hasLoadedTransactions { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 4)
            if !wallet.hasLoadedTransactions {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
            } else if wallet.transactions.isEmpty {
                emptyTransactions
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(model.visibleTransactions) { tx in
                        TransactionRow(transaction: tx) { model.sheet = .payment(tx) }
                    }
                }
                .accessibilityIdentifier("wallet-transactions")
                if model.hasHiddenTransactions { expandButton }
                if model.showAllTransactions && wallet.canLoadMoreTransactions { loadMoreButton }
            }
        }
    }

    @ViewBuilder private var emptyTransactions: some View {
        VStack(spacing: 10) {
            Text(wallet.transactionsError == nil ? L("noTransactionsYet") : L("walletTransactionsUnavailable"))
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
            if wallet.transactionsError != nil {
                Button(L("retry")) { Task { await wallet.loadTransactions() } }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("wallet-transactions-retry")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var expandButton: some View {
        Button {
            withAnimation(.snappy) { model.showAllTransactions.toggle() }
        } label: {
            HStack(spacing: 4) {
                Text(model.showAllTransactions ? L("showLess") : L("showAllTransactions", ["count": wallet.transactions.count]))
                Image(systemName: model.showAllTransactions ? "chevron.up" : "chevron.down")
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(AppColors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .accessibilityIdentifier("wallet-transactions-toggle")
    }

    private var loadMoreButton: some View {
        Button {
            Task { await wallet.loadMoreTransactions() }
        } label: {
            Text(L("walletLoadMore"))
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .disabled(wallet.isLoadingTransactions)
        .accessibilityIdentifier("wallet-transactions-more")
    }
}

struct WalletBalanceCard: View {
    @State private var wallet = WalletService.shared

    var body: some View {
        Button {
            withAnimation(.snappy) { wallet.balanceHidden.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("walletBalance"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Image(systemName: wallet.balanceHidden ? "eye.slash" : "eye")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(balanceText)
                        .font(AppFont.brandSemibold(fontSize))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText(value: Double(wallet.balanceSats ?? 0)))
                        .redacted(reason: wallet.balanceSats == nil && !wallet.balanceHidden ? .placeholder : [])
                    Text(L("walletSats"))
                        .font(.system(size: 18))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .foregroundStyle(AppColors.textPrimary)
                if wallet.balanceError != nil {
                    Label(L("balanceUnavailable"), systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.error)
                } else if let name = wallet.walletName {
                    Label(name, systemImage: "link")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.overlayLight, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.selection, trigger: wallet.balanceHidden)
        .accessibilityLabel(wallet.balanceHidden ? L("walletBalanceHidden") : "\(balanceText) \(L("walletSats"))")
        .accessibilityHint(wallet.balanceHidden ? L("walletTapToShow") : L("walletTapToHide"))
        .accessibilityIdentifier("wallet-balance")
    }

    private var balanceText: String {
        if wallet.balanceHidden { return "••••••" }
        return Sats.format(wallet.balanceSats ?? 0)
    }

    private var fontSize: CGFloat { (wallet.balanceSats ?? 0) > 9_999_999 ? 38 : 48 }
}

struct TransactionRow: View {
    let transaction: WalletTransaction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                TransactionIcon(isIncoming: transaction.isIncoming, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text(WalletFormat.timestamp(transaction.createdAt))
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer(minLength: 8)
                Text("\(WalletFormat.signed(transaction.amountSats, incoming: transaction.isIncoming)) \(L("walletSats"))")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(transaction.isIncoming ? AppColors.success : AppColors.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(AppColors.overlayLight, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            if let invoice = transaction.invoice {
                Button { copy(invoice) } label: { Label(L("walletCopyInvoice"), systemImage: "doc.on.doc") }
            }
            if let description = transaction.description {
                Button { copy(description) } label: { Label(L("walletCopyDescription"), systemImage: "text.quote") }
            }
            Button(action: onTap) { Label(L("details"), systemImage: "info.circle") }
        }
        .accessibilityIdentifier("wallet-transaction")
    }

    private var title: String {
        transaction.description ?? (transaction.isIncoming ? L("received") : L("sent"))
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        ToastCenter.shared.show(L("copiedToClipboard"), style: .success)
    }
}

struct TransactionIcon: View {
    let isIncoming: Bool
    var size: CGFloat = 38

    var body: some View {
        let color = isIncoming ? AppColors.success : AppColors.error
        Image(systemName: isIncoming ? "arrow.down.left" : "arrow.up.right")
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12), in: Circle())
    }
}
