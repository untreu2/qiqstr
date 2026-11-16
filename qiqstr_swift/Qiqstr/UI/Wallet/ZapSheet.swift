import SwiftUI

enum ZapTarget: Hashable {
    case note(Note)
    case profile(String)

    var pubkey: String {
        switch self {
        case .note(let note): note.pubkey
        case .profile(let pubkey): pubkey
        }
    }

    var note: Note? {
        if case .note(let note) = self { return note }
        return nil
    }
}

@MainActor
@Observable
final class ZapViewModel {
    let target: ZapTarget
    var selectedPreset: Int?
    var customAmount = ""
    var comment = ""
    private(set) var recipient: ZapRecipient?
    private(set) var isLoadingRecipient = true
    private(set) var nutzapInfo: NutzapInfo?
    var method: ZapMethod = .lightning

    var splits: [ZapSplit] { target.note?.zapSplits ?? [] }
    private(set) var isZapping = false
    private(set) var mayHaveSettled = false
    private(set) var zappedTick = 0
    private(set) var failedTick = 0

    init(target: ZapTarget) {
        self.target = target
        let initial = ZapService.lastAmount ?? ZapService.defaultAmount
        if ZapService.presetAmounts.contains(initial) {
            selectedPreset = initial
        } else {
            customAmount = String(initial)
        }
    }

    var canZap: Bool { ZapService.shared.canZap }

    var amount: Int? {
        if let custom = Int(customAmount.filter(\.isNumber)), custom > 0 { return custom }
        return customAmount.isEmpty ? selectedPreset : nil
    }

    var fiatEstimate: String? {
        amount.flatMap { BitcoinPriceService.shared.formatted(sats: $0) }.map { L("walletFiatEstimate", ["amount": $0]) }
    }

    var hasPayDestination: Bool { recipient?.lightningAddress != nil || recipient?.lnurl != nil }
    var canNutzap: Bool { nutzapInfo != nil }
    var hasAnyDestination: Bool { hasPayDestination || canNutzap }
    var usesNutzap: Bool { canNutzap && (method == .nutzap || !hasPayDestination) }
    var canSubmit: Bool { canZap && amount != nil && !isZapping && !mayHaveSettled && hasAnyDestination }

    var recipientName: String {
        let fallback = ProfileCache.shared.profile(target.pubkey)?.bestName ?? Profile.shortNpub(target.pubkey)
        return splits.isEmpty ? recipient?.name ?? fallback : fallback
    }

    func select(_ preset: Int) {
        selectedPreset = preset
        customAmount = ""
    }

    func load() async {
        async let price: Void = BitcoinPriceService.shared.refreshIfNeeded()
        let splitPubkeys = splits.map(\.pubkey)
        if !splitPubkeys.isEmpty { await ProfileCache.shared.load(splitPubkeys) }
        recipient = await ZapService.shared.recipient(splitPubkeys.first ?? target.pubkey)
        if AppStorePolicy.allowsCashu, splitPubkeys.isEmpty { nutzapInfo = await NutzapService.shared.info(for: target.pubkey) }
        isLoadingRecipient = false
        await price
    }

    func zap() async -> Bool {
        guard let amount, canSubmit else { return false }
        isZapping = true
        defer { isZapping = false }
        do {
            if usesNutzap {
                try await NutzapService.shared.send(to: target.pubkey, note: target.note, amountSats: amount, comment: comment)
            } else {
                try await ZapService.shared.zap(note: target.note, pubkey: target.pubkey, amountSats: amount, comment: comment)
            }
            zappedTick += 1
            ZapService.lastAmount = amount
            ToastCenter.shared.show(L("walletZapped", ["sats": Sats.format(amount), "user": recipientName]), style: .success)
            return true
        } catch WalletError.paymentPending {
            mayHaveSettled = true
            failedTick += 1
            ToastCenter.shared.show(L("walletPaymentPending"), style: .error)
            return true
        } catch {
            failedTick += 1
            ToastCenter.shared.show("\(L("failedToZap")): \(coreMessage(error))", style: .error)
            return false
        }
    }

    func openWallet() {
        Router.shared.sheet = nil
        Router.shared.selectedTab = .wallet
    }
}

enum ZapMethod: String, CaseIterable, Identifiable {
    case lightning, nutzap
    var id: String { rawValue }
    var title: String { self == .lightning ? L("zapMethodLightning") : L("zapMethodNutzap") }
}

struct ZapSplitRow: View {
    let split: ZapSplit
    let percent: Int
    @State private var cache = ProfileCache.shared

    var body: some View {
        HStack(spacing: 10) {
            ProfileAvatar(pubkey: split.pubkey, size: 26)
            Text(cache.profile(split.pubkey)?.bestName ?? Profile.shortNpub(split.pubkey)).lineLimit(1)
            Spacer(minLength: 8)
            Text("\(percent)%").monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ZapSheet: View {
    let target: ZapTarget
    @Environment(\.dismiss) private var dismiss
    @State private var model: ZapViewModel
    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .headline) private var avatarSize: CGFloat = 44

    init(target: ZapTarget) {
        self.target = target
        _model = State(initialValue: ZapViewModel(target: target))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { header }
                if !model.canZap {
                    connectCTA
                } else if !model.isLoadingRecipient && !model.hasAnyDestination {
                    Section {
                        Label(L("userNoLightningAddress"), systemImage: "bolt.slash")
                            .foregroundStyle(AppColors.error)
                            .accessibilityIdentifier("zap-no-address")
                    }
                } else {
                    if model.hasPayDestination, model.canNutzap {
                        Section {
                            Picker(L("zapMethod"), selection: $model.method) {
                                ForEach(ZapMethod.allCases) { method in
                                    Text(method.title).tag(method)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                            .accessibilityIdentifier("zap-method")
                        } footer: {
                            if model.method == .nutzap { Text(L("zapMethodNutzapFooter")).wrapsInFooter() }
                        }
                    }
                    Section {
                        amounts
                        LabeledContent(L("walletCustomAmount")) {
                            TextField(L("walletSats"), text: $model.customAmount)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .focused($focused)
                                .accessibilityIdentifier("zap-custom-amount")
                        }
                    } header: {
                        Text(L("amount"))
                    } footer: {
                        if let fiat = model.fiatEstimate {
                            Text(fiat)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .animation(.snappy, value: fiat)
                        }
                    }
                    Section {
                        TextField(L("commentOptional"), text: $model.comment, axis: .vertical)
                            .lineLimit(1...4)
                            .focused($focused)
                            .accessibilityIdentifier("zap-comment")
                    }
                    if !model.splits.isEmpty {
                        Section {
                            ForEach(model.splits, id: \.pubkey) { split in
                                ZapSplitRow(split: split, percent: ZapSplit.percent(split, of: model.splits))
                            }
                        } header: {
                            Text(L("zapSplitTitle"))
                        } footer: {
                            Text(L("zapSplitFooter")).wrapsInFooter()
                        }
                        .accessibilityIdentifier("zap-splits")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if model.canZap && model.hasAnyDestination {
                    Button {
                        focused = false
                        Task { if await model.zap() { dismiss() } }
                    } label: {
                        ZStack {
                            Label(submitTitle, systemImage: "bolt.fill").opacity(model.isZapping ? 0 : 1)
                            if model.isZapping { ProgressView() }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .prominentButtonStyle()
                    .buttonBorderShape(.capsule)
                    .controlSize(.extraLarge)
                    .disabled(!model.canSubmit)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("zap-submit")
                }
            }
            .navigationTitle(L("zapUser", ["user": model.recipientName]))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                        .accessibilityLabel(L("cancel"))
                        .accessibilityIdentifier("zap-cancel")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isZapping)
        .task { await model.load() }
        .sensoryFeedback(.success, trigger: model.zappedTick)
        .sensoryFeedback(.error, trigger: model.failedTick)
        .accessibilityIdentifier("zap-sheet")
    }

    private var submitTitle: String {
        guard let amount = model.amount else { return L("zap") }
        return L("walletZapAmount", ["amount": Sats.format(amount)])
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ProfileAvatar(pubkey: target.pubkey, size: avatarSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.recipientName)
                    .font(.headline)
                    .lineLimit(1)
                Group {
                    if model.isLoadingRecipient && model.canZap {
                        Text(L("loading"))
                    } else if let address = model.recipient?.lightningAddress {
                        Label(address, systemImage: "bolt.fill")
                            .labelStyle(SettingsCompactLabelStyle())
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                if let note = target.note, !note.content.isEmpty {
                    Text(note.content)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var amounts: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(ZapService.presetAmounts, id: \.self) { preset in
                chip(preset)
            }
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.selection, trigger: model.selectedPreset)
    }

    @ViewBuilder
    private func chip(_ preset: Int) -> some View {
        let selected = model.customAmount.isEmpty && model.selectedPreset == preset
        let label = Label(Sats.compact(preset), systemImage: "bolt.fill")
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .frame(maxWidth: .infinity)
        Group {
            if selected {
                Button { select(preset) } label: { label }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(AppColors.background)
            } else {
                Button { select(preset) } label: { label }
                    .buttonStyle(.bordered)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .accessibilityLabel("\(Sats.format(preset)) \(L("walletSats"))")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("zap-amount-\(preset)")
    }

    private func select(_ preset: Int) {
        focused = false
        model.select(preset)
    }

    private var connectCTA: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "bolt.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(L("walletZapConnectTitle"))
                    .font(.headline)
                Text(L("walletZapConnectMessage"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button { model.openWallet() } label: {
                    Label(L("walletConnectWallet"), systemImage: "wallet.bifold")
                        .font(.headline)
                }
                .prominentButtonStyle()
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .padding(.top, 4)
                .accessibilityIdentifier("zap-connect-wallet")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}
