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

    init(target: ZapTarget) {
        self.target = target
        _model = State(initialValue: ZapViewModel(target: target))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if !model.canZap {
                        connectCTA
                    } else if !model.isLoadingRecipient && !model.hasPayDestination {
                        Label(L("userNoLightningAddress"), systemImage: "bolt.slash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.error)
                            .accessibilityIdentifier("zap-no-address")
                    } else {
                        amounts
                        QiqTextField(placeholder: L("walletCustomAmount"), text: $model.customAmount, keyboard: .numberPad)
                            .focused($focused)
                            .accessibilityIdentifier("zap-custom-amount")
                        QiqTextField(placeholder: L("commentOptional"), text: $model.comment, autocapitalize: true)
                            .focused($focused)
                            .accessibilityIdentifier("zap-comment")
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if model.canZap && model.hasPayDestination {
                    PrimaryButton(title: submitTitle, isLoading: model.isZapping, isEnabled: model.canSubmit) {
                        focused = false
                        Task { if await model.zap() { dismiss() } }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("zap-submit")
                }
            }
            .navigationTitle(target.note == nil ? L("zapUser", ["user": model.recipientName]) : L("zapNote"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L("cancel"))
                        .accessibilityIdentifier("zap-cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
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
        HStack(spacing: 12) {
            ProfileAvatar(pubkey: target.pubkey, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.recipientName).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Group {
                    if model.isLoadingRecipient {
                        Text(L("loading"))
                    } else if let address = model.recipient?.lightningAddress {
                        Label(address, systemImage: "bolt.fill")
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                if let note = target.note, !note.content.isEmpty {
                    Text(note.content)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var amounts: some View {
        GlassEffectContainer(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(ZapService.presetAmounts, id: \.self) { preset in
                    chip(preset)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: model.selectedPreset)
    }

    private func chip(_ preset: Int) -> some View {
        let selected = model.customAmount.isEmpty && model.selectedPreset == preset
        return Button {
            focused = false
            model.select(preset)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(selected ? AppColors.background : AppColors.zap)
                Text(Sats.compact(preset)).font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(selected ? AppColors.background : AppColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background {
                if selected { Capsule().fill(AppColors.textPrimary) }
            }
            .glassEffect(selected ? .identity : .regular.interactive(), in: .capsule)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(Sats.format(preset)) \(L("walletSats"))")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("zap-amount-\(preset)")
    }

    private var connectCTA: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("walletZapConnectTitle"), systemImage: "bolt.slash")
                .font(.system(size: 16, weight: .semibold))
            Text(L("walletZapConnectMessage"))
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PillButton(title: L("walletConnectWallet"), systemImage: "wallet.bifold") { model.openWallet() }
                .accessibilityIdentifier("zap-connect-wallet")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.overlayLight, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
