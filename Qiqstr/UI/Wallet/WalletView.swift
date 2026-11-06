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
    static let collapsedTransactionCount = 8

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

    var transactionDays: [TransactionDay] { TransactionDay.group(visibleTransactions) }

    func consumeIncoming() {
        guard let uri = wallet.incomingConnectURI else { return }
        if case .connect = sheet { return }
        sheet = .connect(wallet.consumeIncomingConnectURI() ?? uri)
    }

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
        .navigationBarTitleDisplayMode(.large)
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
        .onAppear { model.consumeIncoming() }
        .onChange(of: wallet.incomingConnectURI) { _, uri in
            if uri != nil { model.consumeIncoming() }
        }
        .task { await BitcoinPriceService.shared.refreshIfNeeded() }
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
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "bolt.fill")
                        .font(.largeTitle)
                        .imageScale(.large)
                        .foregroundStyle(AppColors.zap)
                        .symbolRenderingMode(.hierarchical)
                    Text(L("nwcTitle"))
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(L("walletNwcIntro"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
            Section {
                feature("bolt", L("onboardingCoinosFeatureSend"))
                feature("arrow.down.left", L("walletFeatureReceive"))
                feature("heart", L("onboardingCoinosFeatureZap"))
                feature("banknote", L("walletFeatureCashu"))
            }
            Section {
                ForEach(WalletProvider.all) { WalletProviderRow(provider: $0) }
            } header: {
                Text(L("walletGetWallet"))
            } footer: {
                Text(L("walletGetWalletFooter"))
            }
            Section {
                Text(L("walletNwcHowTo"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(L("walletNwcHowToTitle"))
            }
            Section {
                VStack(spacing: 10) {
                    Button { model.sheet = .connect(nil) } label: {
                        Text(L("walletConnectWallet"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .foregroundStyle(AppColors.background)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .accessibilityIdentifier("wallet-connect")
                    Button { model.showScanner = true } label: {
                        Label(L("scanQRCode"), systemImage: "qrcode.viewfinder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .accessibilityIdentifier("wallet-connect-scan")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text(L("nwcDisclaimer"))
                    .padding(.top, 8)
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("wallet-onboarding")
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(.secondary)
        }
    }
}

struct WalletDashboard: View {
    @Bindable var model: WalletViewModel
    @State private var wallet = WalletService.shared

    var body: some View {
        List {
            Section {
                VStack(spacing: 20) {
                    WalletBalanceCard()
                    actions
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            }
            if wallet.cashuBalanceSats > 0 { cashuSection }
            transactions
        }
        .listStyle(.insetGrouped)
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

    private var cashuSection: some View {
        Section {
            LabeledContent {
                Button(L("walletMelt")) { model.showMeltConfirm = true }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .disabled(wallet.isRedeemingCashu)
                    .accessibilityIdentifier("wallet-cashu-melt")
            } label: {
                Label {
                    Text(L("cashu"))
                    Text(verbatim: "\(Sats.format(wallet.cashuBalanceSats)) \(L("walletSats"))")
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "banknote")
                }
            }
        }
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
                Image(systemName: icon).font(.title3.weight(.semibold))
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 22))
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private var transactions: some View {
        if !wallet.hasLoadedTransactions {
            Section {
                ForEach(0..<4, id: \.self) { index in
                    TransactionRow(transaction: .placeholder(index)) {}
                        .redacted(reason: .placeholder)
                        .disabled(true)
                }
            } header: {
                Text(L("recentTransactions"))
            }
            .accessibilityIdentifier("wallet-transactions")
        } else if wallet.transactions.isEmpty {
            Section {
                emptyTransactions
                    .listRowBackground(Color.clear)
            }
            .accessibilityIdentifier("wallet-transactions")
        } else {
            ForEach(Array(model.transactionDays.enumerated()), id: \.element.id) { index, day in
                Section {
                    ForEach(day.transactions) { tx in
                        TransactionRow(transaction: tx, showsTimeOnly: true) { model.sheet = .payment(tx) }
                    }
                } header: {
                    dayHeader(day, isFirst: index == 0)
                } footer: {
                    if index == model.transactionDays.count - 1, model.hasHiddenTransactions || (model.showAllTransactions && wallet.canLoadMoreTransactions) {
                        transactionFooterButtons
                    }
                }
                .accessibilityIdentifier(index == 0 ? "wallet-transactions" : "wallet-transactions-\(day.id)")
            }
        }
    }

    private func dayHeader(_ day: TransactionDay, isFirst: Bool) -> some View {
        HStack {
            Text(day.title)
            Spacer()
            if isFirst && wallet.isLoadingTransactions { ProgressView().controlSize(.small) }
            Text(day.netText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel(L("walletDayNet", ["amount": day.netText]))
        }
    }

    private var transactionFooterButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.hasHiddenTransactions { expandButton }
            if model.showAllTransactions && wallet.canLoadMoreTransactions { loadMoreButton }
        }
        .font(.subheadline)
        .padding(.top, 6)
    }

    private var emptyTransactions: some View {
        ContentUnavailableView {
            Label(wallet.transactionsError == nil ? L("noTransactionsYet") : L("walletTransactionsUnavailable"), systemImage: wallet.transactionsError == nil ? "bolt.horizontal" : "exclamationmark.triangle")
        } description: {
            Text(wallet.transactionsError ?? L("walletEmptyTransactionsMessage"))
        } actions: {
            if wallet.transactionsError != nil {
                Button(L("retry")) { Task { await wallet.loadTransactions() } }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .accessibilityIdentifier("wallet-transactions-retry")
            } else {
                Button { model.receive() } label: {
                    Label(L("receive"), systemImage: "arrow.down.left")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("wallet-empty-receive")
            }
        }
    }

    private var expandButton: some View {
        Button {
            withAnimation(.snappy) { model.showAllTransactions.toggle() }
        } label: {
            Text(model.showAllTransactions ? L("showLess") : L("showAllTransactions", ["count": wallet.transactions.count]))
        }
        .accessibilityIdentifier("wallet-transactions-toggle")
    }

    private var loadMoreButton: some View {
        Button {
            Task { await wallet.loadMoreTransactions() }
        } label: {
            HStack(spacing: 8) {
                Text(L("walletLoadMore"))
                if wallet.isLoadingTransactions { ProgressView().controlSize(.small) }
            }
        }
        .disabled(wallet.isLoadingTransactions)
        .accessibilityIdentifier("wallet-transactions-more")
    }
}

struct WalletBalanceCard: View {
    @State private var wallet = WalletService.shared
    @State private var prices = BitcoinPriceService.shared
    @AppStorage(BitcoinPriceService.showFiatKey) private var showFiat = true
    @ScaledMetric(relativeTo: .largeTitle) private var balanceSize: CGFloat = 60

    var body: some View {
        Button {
            withAnimation(.snappy) { wallet.balanceHidden.toggle() }
        } label: {
            VStack(spacing: 8) {
                Label(L("walletBalance"), systemImage: wallet.balanceHidden ? "eye.slash" : "eye")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.symbolEffect(.replace))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(balanceText)
                        .font(.system(size: balanceSize, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .contentTransition(.numericText(value: Double(wallet.balanceSats ?? 0)))
                        .redacted(reason: wallet.balanceSats == nil && !wallet.balanceHidden ? .placeholder : [])
                    Text(L("walletSats"))
                        .font(.title3.weight(.semibold))
                        .fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                if let fiat = fiatText {
                    Text(fiat)
                        .font(.title3)
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("wallet-balance-fiat")
                }
                status
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: wallet.balanceHidden)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(wallet.balanceHidden ? L("walletTapToShow") : L("walletTapToHide"))
        .accessibilityIdentifier("wallet-balance")
        .task(id: showFiat) { if showFiat { await prices.refreshIfNeeded() } }
    }

    @ViewBuilder
    private var status: some View {
        if wallet.balanceError != nil {
            Label(L("balanceUnavailable"), systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(AppColors.error)
        } else if let name = wallet.lightningAddress ?? wallet.walletName {
            Label(name, systemImage: wallet.lightningAddress == nil ? "link" : "bolt")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var fiatText: String? {
        guard showFiat, !wallet.balanceHidden, let sats = wallet.balanceSats else { return nil }
        return prices.formatted(sats: sats).map { L("walletFiatEstimate", ["amount": $0]) }
    }

    private var balanceText: String {
        if wallet.balanceHidden { return "••••••" }
        return Sats.format(wallet.balanceSats ?? 0)
    }

    private var accessibilityText: String {
        if wallet.balanceHidden { return L("walletBalanceHidden") }
        let sats = "\(balanceText) \(L("walletSats"))"
        guard let fiatText else { return sats }
        return "\(sats), \(fiatText)"
    }
}

struct TransactionDay: Identifiable {
    let id: String
    let date: Date
    let transactions: [WalletTransaction]

    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L("today") }
        if calendar.isDateInYesterday(date) { return L("yesterday") }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        return date.formatted(date: .long, time: .omitted)
    }

    var net: Int {
        transactions.reduce(0) { $0 + ($1.isIncoming ? $1.amountSats : -$1.amountSats) }
    }

    var netText: String {
        let value = net
        if value == 0 { return "0" }
        return WalletFormat.signed(value, incoming: value > 0)
    }

    static func group(_ transactions: [WalletTransaction]) -> [TransactionDay] {
        let calendar = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [WalletTransaction]] = [:]
        for tx in transactions {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(tx.createdAt)))
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(tx)
        }
        return order.map { day in
            TransactionDay(id: String(Int(day.timeIntervalSince1970)), date: day, transactions: buckets[day] ?? [])
        }
    }
}

struct TransactionRow: View {
    let transaction: WalletTransaction
    var showsTimeOnly = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                TransactionIcon(isIncoming: transaction.isIncoming)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(verbatim: "\(WalletFormat.signed(transaction.amountSats, incoming: transaction.isIncoming)) \(L("walletSats"))")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(transaction.isIncoming ? AppColors.success : .primary)
            }
            .contentShape(Rectangle())
        }
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
        transaction.description?.nilIfEmpty ?? (transaction.isIncoming ? L("received") : L("sent"))
    }

    private var subtitle: String {
        guard showsTimeOnly, transaction.createdAt > 0 else { return WalletFormat.timestamp(transaction.createdAt) }
        return Date(timeIntervalSince1970: TimeInterval(transaction.createdAt)).formatted(date: .omitted, time: .shortened)
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        ToastCenter.shared.show(L("copiedToClipboard"), style: .success)
    }
}

struct TransactionIcon: View {
    let isIncoming: Bool
    var textStyle: Font.TextStyle = .body
    @ScaledMetric(relativeTo: .body) private var baseSize: CGFloat = 34

    var body: some View {
        let color = isIncoming ? AppColors.success : AppColors.textPrimary
        Image(systemName: isIncoming ? "arrow.down.left" : "arrow.up.right")
            .font(.system(textStyle).weight(.semibold))
            .foregroundStyle(color)
            .frame(width: baseSize * scale, height: baseSize * scale)
            .background(color.opacity(0.12), in: Circle())
    }

    private var scale: CGFloat {
        switch textStyle {
        case .largeTitle: 1.8
        case .title, .title2: 1.4
        default: 1
        }
    }
}

extension WalletTransaction {
    static func placeholder(_ index: Int) -> WalletTransaction {
        WalletTransaction(json: [
            "type": index.isMultiple(of: 2) ? "incoming" : "outgoing",
            "amount": 21_000,
            "description": "Lightning payment",
            "created_at": Int(Date().timeIntervalSince1970) - index * 3600,
            "invoice": "placeholder-\(index)",
        ])
    }
}
