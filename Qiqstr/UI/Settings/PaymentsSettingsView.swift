import SwiftUI

struct PaymentsSettingsView: View {
    @AppStorage("one_tap_zap") private var oneTapZap = false
    @AppStorage("default_zap_amount") private var defaultZapAmount = 21
    @State private var amountText = ""
    @State private var saved = 0
    @FocusState private var amountFocused: Bool

    private static let presets = [21, 100, 500, 1000, 5000]

    var body: some View {
        Form {
            Section {
                Button(action: openWallet) {
                    LabeledContent {
                        Image(systemName: "arrow.up.forward")
                            .font(.footnote.weight(.semibold))
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("wallet")).foregroundStyle(AppColors.textPrimary)
                                Text(L("settingsWalletManage"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            SettingsIcon(systemImage: "wallet.bifold")
                        }
                    }
                }
                .accessibilityIdentifier("payments-open-wallet")
            } header: {
                Text(L("paymentsSubtitle"))
            } footer: {
                Text(L("nwcDescription"))
            }

            Section {
                Toggle(isOn: $oneTapZap) {
                    SettingsRowLabel(title: L("oneTapZap"), systemImage: "bolt.fill", tint: oneTapZap ? AppColors.zap : AppColors.textPrimary)
                }
                .tint(AppColors.switchActive)
                .accessibilityIdentifier("payments-one-tap-zap")
            } footer: {
                Text(L("oneTapZapDescription"))
            }

            Section(L("defaultZapAmount")) {
                LabeledContent {
                    HStack(spacing: 6) {
                        TextField(L("amountSats"), text: $amountText)
                            .keyboardType(.numberPad)
                            .focused($amountFocused)
                            .multilineTextAlignment(.trailing)
                            .font(.body.monospacedDigit())
                            .accessibilityIdentifier("payments-amount-field")
                        Text(verbatim: "sats").foregroundStyle(.secondary)
                    }
                } label: {
                    SettingsRowLabel(title: L("amountSats"), systemImage: "bolt", tint: AppColors.zap)
                }
                Picker(L("defaultZapAmount"), selection: Binding(get: { Int(amountText) ?? 0 }, set: { amountText = "\($0)" })) {
                    ForEach(Self.presets, id: \.self) { preset in
                        Text(Sats.format(preset))
                            .tag(preset)
                            .accessibilityIdentifier("payments-preset-\(preset)")
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .settingsListStyle()
        .navigationTitle(L("paymentsTitle"))
        .navigationBarTitleDisplayMode(.large)
        .onAppear { amountText = "\(defaultZapAmount)" }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("save")) { save() }
                    .disabled(!hasChanges)
                    .accessibilityIdentifier("payments-amount-save")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("done")) { amountFocused = false }
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.selection, trigger: oneTapZap)
    }

    private var hasChanges: Bool { Int(amountText) != defaultZapAmount }

    private func save() {
        guard let amount = Int(amountText.trimmingCharacters(in: .whitespaces)), amount > 0 else {
            ToastCenter.shared.show(L("pleaseEnterValidAmount"), style: .error)
            return
        }
        defaultZapAmount = amount
        amountFocused = false
        saved += 1
        ToastCenter.shared.show(L("amountSavedSuccessfully"), style: .success)
    }

    private func openWallet() {
        let router = Router.shared
        router.popToRoot(.wallet)
        router.selectedTab = .wallet
    }
}
