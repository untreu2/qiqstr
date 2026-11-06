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
    private(set) var isZapping = false
    private(set) var zappedTick = 0
    private(set) var failedTick = 0

    init(target: ZapTarget) {
        self.target = target
        let initial = ZapService.defaultAmount
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

    var hasPayDestination: Bool { recipient?.lightningAddress != nil || recipient?.lnurl != nil }
    var canSubmit: Bool { canZap && amount != nil && !isZapping && hasPayDestination }

    var recipientName: String {
        recipient?.name ?? ProfileCache.shared.profile(target.pubkey)?.bestName ?? Profile.shortNpub(target.pubkey)
    }

    func select(_ preset: Int) {
        selectedPreset = preset
        customAmount = ""
    }

    func load() async {
        recipient = await ZapService.shared.recipient(target.pubkey)
        isLoadingRecipient = false
    }

    func zap() async -> Bool {
        guard let amount, canSubmit else { return false }
        isZapping = true
        defer { isZapping = false }
        do {
            try await ZapService.shared.zap(note: target.note, pubkey: target.pubkey, amountSats: amount, comment: comment)
            zappedTick += 1
            ToastCenter.shared.show(L("walletZapped", ["sats": Sats.format(amount), "user": recipientName]), style: .success)
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
                } else if !model.isLoadingRecipient && !model.hasPayDestination {
                    Section {
                        Label(L("userNoLightningAddress"), systemImage: "bolt.slash")
                            .foregroundStyle(AppColors.error)
                            .accessibilityIdentifier("zap-no-address")
                    }
                } else {
                    Section(L("amount")) {
                        amounts
                        LabeledContent(L("walletCustomAmount")) {
                            TextField(L("walletSats"), text: $model.customAmount)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .focused($focused)
                                .accessibilityIdentifier("zap-custom-amount")
                        }
                    }
                    Section {
                        TextField(L("commentOptional"), text: $model.comment, axis: .vertical)
                            .lineLimit(1...4)
                            .focused($focused)
                            .accessibilityIdentifier("zap-comment")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if model.canZap && model.hasPayDestination {
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
                    .buttonStyle(.glassProminent)
                    .foregroundStyle(AppColors.background)
                    .buttonBorderShape(.capsule)
                    .controlSize(.extraLarge)
                    .disabled(!model.canSubmit)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("zap-submit")
                }
            }
            .navigationTitle(target.note == nil ? L("zapUser", ["user": model.recipientName]) : L("zapNote"))
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
                .buttonStyle(.glassProminent)
                .foregroundStyle(AppColors.background)
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
