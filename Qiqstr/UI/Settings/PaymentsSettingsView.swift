import SwiftUI

struct PaymentsSettingsView: View {
    @AppStorage("one_tap_zap") private var oneTapZap = false
    @AppStorage("default_zap_amount") private var defaultZapAmount = 21
    @State private var amountText = ""
    @State private var saved = 0
    @FocusState private var amountFocused: Bool

    private static let presets = [21, 100, 500, 1000, 5000]

    var body: some View {
        List {
            SettingsPageHeader(subtitle: L("paymentsSubtitle"))
            Section {
                Button(action: openWallet) {
                    HStack(spacing: 12) {
                        IconTile(systemImage: "wallet.bifold", size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("wallet")).font(.system(size: 16, weight: .semibold)).foregroundStyle(AppColors.textPrimary)
                            Text(L("settingsWalletManage")).font(.system(size: 13)).foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier("payments-open-wallet")
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
                HStack(spacing: 10) {
                    Image(systemName: "bolt").foregroundStyle(AppColors.zap)
                    TextField(L("amountSats"), text: $amountText)
                        .keyboardType(.numberPad)
                        .focused($amountFocused)
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                        .accessibilityIdentifier("payments-amount-field")
                    Text("sats").foregroundStyle(AppColors.textSecondary)
                    Button(L("save")) { save() }
                        .buttonStyle(.glassProminent)
                        .tint(AppColors.textPrimary)
                        .foregroundStyle(AppColors.background)
                        .disabled(!hasChanges)
                        .accessibilityIdentifier("payments-amount-save")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.presets, id: \.self) { preset in
                            let selected = Int(amountText) == preset
                            Button {
                                amountText = "\(preset)"
                            } label: {
                                Text(Sats.format(preset))
                                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                                    .padding(.horizontal, 14)
                                    .frame(height: 32)
                                    .foregroundStyle(selected ? AppColors.background : AppColors.textPrimary)
                                    .background(selected ? AppColors.textPrimary : AppColors.tile, in: Capsule())
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityIdentifier("payments-preset-\(preset)")
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        .settingsListStyle()
        .navigationTitle(L("paymentsTitle"))
        .onAppear { amountText = "\(defaultZapAmount)" }
        .toolbar {
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
