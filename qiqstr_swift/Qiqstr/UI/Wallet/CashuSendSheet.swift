import SwiftUI

@MainActor
@Observable
final class CashuSendModel {
    var amountText = ""
    var mint: String
    private(set) var isCreating = false
    private(set) var created: SentCashuToken?
    private(set) var error: String?
    private(set) var doneTick = 0

    init() { mint = NutzapService.shared.sendMint }

    var amount: Int? {
        guard let value = Int(amountText.filter(\.isNumber)), value > 0, SatsAmount.msat(value) != nil else { return nil }
        return value
    }

    var canCreate: Bool { amount != nil && !isCreating && WalletService.shared.isConnected }

    func create() async {
        guard let amount, canCreate else { return }
        isCreating = true
        error = nil
        defer { isCreating = false }
        do {
            NutzapService.shared.sendMint = mint
            created = try await NutzapService.shared.createToken(mint: mint, amountSats: amount)
            doneTick += 1
            amountText = ""
        } catch {
            self.error = coreMessage(error)
        }
    }

    func show(_ token: SentCashuToken) { created = token }
    func reset() { created = nil }
}

struct CashuSendSheet: View {
    @State private var model = CashuSendModel()
    @State private var service = NutzapService.shared
    @State private var wallet = WalletService.shared
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let token = model.created {
                    tokenSection(token)
                } else {
                    Section {
                        LabeledContent(L("amount")) {
                            TextField(L("walletSats"), text: $model.amountText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .focused($focused)
                                .accessibilityIdentifier("cashu-send-amount")
                        }
                        Picker(L("cashuMint"), selection: $model.mint) {
                            ForEach(service.mintOptions, id: \.self) { mint in
                                Text(CashuMint.displayName(mint)).tag(mint)
                            }
                        }
                        .accessibilityIdentifier("cashu-send-mint")
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("cashuSendFooter")).wrapsInFooter()
                            if let error = model.error {
                                Text(error).foregroundStyle(AppColors.error).wrapsInFooter().accessibilityIdentifier("cashu-send-error")
                            }
                        }
                    }
                    if !service.sentTokens.isEmpty {
                        Section(L("cashuSentTokens")) {
                            ForEach(service.sentTokens) { token in
                                Button { model.show(token) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(L("walletSatsAmount", ["amount": Sats.format(token.amountSats)])).foregroundStyle(AppColors.textPrimary)
                                            Text(CashuMint.displayName(token.mint)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        Text(token.createdAt, format: .relative(presentation: .named)).font(.footnote).foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button(L("delete"), systemImage: "trash", role: .destructive) { service.forget(token) }
                                }
                                .accessibilityIdentifier("cashu-sent-row")
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if model.created == nil {
                    Button {
                        focused = false
                        Task { await model.create() }
                    } label: {
                        ZStack {
                            Label(L("cashuCreateToken"), systemImage: "banknote").opacity(model.isCreating ? 0 : 1)
                            if model.isCreating { ProgressView() }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .prominentButtonStyle()
                    .buttonBorderShape(.capsule)
                    .controlSize(.extraLarge)
                    .disabled(!model.canCreate)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("cashu-send-create")
                }
            }
            .navigationTitle(L("cashuSendTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("cancel"), systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("cashu-send-close")
                }
                if model.created != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("cashuNewToken"), systemImage: "plus") { model.reset() }
                            .accessibilityIdentifier("cashu-send-new")
                    }
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(model.isCreating)
        .sensoryFeedback(.success, trigger: model.doneTick)
        .accessibilityIdentifier("cashu-send-sheet")
    }

    @ViewBuilder
    private func tokenSection(_ token: SentCashuToken) -> some View {
        Section {
            VStack(spacing: 14) {
                Text(L("walletSatsAmount", ["amount": Sats.format(token.amountSats)]))
                    .font(.title2.weight(.semibold).monospacedDigit())
                QRCodeView(content: token.token, size: 240)
                Text(token.token)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        } footer: {
            Text(L("cashuTokenFooter")).wrapsInFooter()
        }
        Section {
            Button(L("copy"), systemImage: "doc.on.doc") {
                UIPasteboard.general.string = token.token
                ToastCenter.shared.show(L("copiedToClipboard"), style: .success)
            }
            .accessibilityIdentifier("cashu-token-copy")
            ShareLink(item: token.token) { Label(L("share"), systemImage: "square.and.arrow.up") }
                .accessibilityIdentifier("cashu-token-share")
        }
    }
}

struct CashuMintsSettingsView: View {
    @State private var service = NutzapService.shared
    @State private var wallet = WalletService.shared
    @State private var showAdd = false
    @State private var newMint = ""
    @State private var feedback = 0

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { service.isReceiving }, set: { setReceiving($0) })) {
                    SettingsRowLabel(title: L("nutzapReceive"), systemImage: "banknote")
                }
                .tint(AppColors.switchActive)
                .accessibilityIdentifier("nutzap-receive")
            } footer: {
                Text(L("nutzapReceiveFooter")).wrapsInFooter()
            }
            if wallet.cashuBalanceSats > 0 {
                Section {
                    LabeledContent {
                        Text(L("walletSatsAmount", ["amount": Sats.format(wallet.cashuBalanceSats)])).monospacedDigit()
                    } label: {
                        SettingsRowLabel(title: L("cashuUnclaimed"), systemImage: "tray.and.arrow.down")
                    }
                    .accessibilityIdentifier("nutzap-balance")
                } footer: {
                    Text(L("cashuUnclaimedFooter")).wrapsInFooter()
                }
            }
            Section {
                ForEach(service.mintOptions, id: \.self) { mint in
                    let selected = service.mints.contains(mint)
                    Button { toggle(mint) } label: {
                        HStack {
                            Label(CashuMint.displayName(mint), systemImage: "building.columns")
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            if selected { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(AppColors.textPrimary) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("nutzap-mint-\(CashuMint.displayName(mint))")
                }
                Button(L("cashuAddMint"), systemImage: "plus") {
                    newMint = ""
                    showAdd = true
                }
                .accessibilityIdentifier("nutzap-mint-add")
            } header: {
                Text(L("cashuMints"))
            } footer: {
                Text(L("cashuMintsFooter")).wrapsInFooter()
            }
        }
        .settingsListStyle()
        .disabled(service.isSaving)
        .overlay { if service.isSaving { ProgressView().controlSize(.large) } }
        .navigationTitle(L("nutzapTitle"))
        .navigationBarTitleDisplayMode(.large)
        .alert(L("cashuAddMint"), isPresented: $showAdd) {
            TextField("mint.example.com", text: $newMint)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityIdentifier("nutzap-mint-field")
            Button(L("cancel"), role: .cancel) {}
            Button(L("settingsAdd")) { add(newMint) }
                .disabled(!CashuMint.isValid(newMint))
        }
        .task {
            await service.load()
            await wallet.refreshCashuBalance()
        }
        .task(id: service.receivedTick) { await wallet.refreshCashuBalance() }
        .sensoryFeedback(.success, trigger: feedback)
    }

    private func setReceiving(_ enabled: Bool) {
        guard ReadOnlyGate.check() else { return }
        save { try await service.setReceiving(enabled) }
    }

    private func toggle(_ mint: String) {
        guard ReadOnlyGate.check() else { return }
        var next = service.mints
        if next.contains(mint) { next.removeAll { $0 == mint } } else { next.append(mint) }
        apply(next)
    }

    private func add(_ raw: String) {
        let mint = CashuMint.normalized(raw)
        guard ReadOnlyGate.check(), !service.mints.contains(mint) else { return }
        save {
            _ = try await service.lookup(mint)
            try await service.setReceiving(true, mints: service.mints + [mint])
        }
    }

    private func apply(_ next: [String]) {
        if next.isEmpty {
            save { try await service.setReceiving(false, mints: []) }
        } else {
            save { try await service.setReceiving(true, mints: next) }
        }
    }

    private func save(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                feedback += 1
            } catch {
                ToastCenter.shared.error(error)
            }
        }
    }
}
