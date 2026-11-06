import SwiftUI

struct PaymentDetailSheet: View {
    let transaction: WalletTransaction
    @Environment(\.dismiss) private var dismiss
    @State private var showTechnical = false
    @State private var copiedTick = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    header
                        .listRowBackground(Color.clear)
                }
                Section {
                    LabeledContent(L("status"), value: transaction.isIncoming ? L("received") : L("sent"))
                    if transaction.createdAt > 0 { LabeledContent(L("date"), value: TimeFormat.full(transaction.createdAt)) }
                    if !transaction.isIncoming {
                        LabeledContent(L("fee")) {
                            Text(verbatim: "\(Sats.format(transaction.feesSats)) \(L("walletSats"))").monospacedDigit()
                        }
                    }
                    LabeledContent(L("method"), value: L("walletMethodLightning"))
                    if let description = transaction.description {
                        LabeledContent(L("description")) {
                            Text(description).textSelection(.enabled)
                        }
                    }
                }
                if transaction.invoice != nil || transaction.paymentHash != nil {
                    Section {
                        DisclosureGroup(L("details"), isExpanded: $showTechnical) {
                            if let hash = transaction.paymentHash { copyRow(L("paymentHash"), hash) }
                            if let invoice = transaction.invoice { copyRow(L("invoice"), invoice) }
                        }
                        .accessibilityIdentifier("payment-detail-toggle")
                    }
                }
            }
            .navigationTitle(L("details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityLabel(L("done"))
                        .accessibilityIdentifier("payment-detail-close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.success, trigger: copiedTick)
        .accessibilityIdentifier("payment-detail")
    }

    private var header: some View {
        VStack(spacing: 10) {
            TransactionIcon(isIncoming: transaction.isIncoming, textStyle: .title)
            Text(verbatim: "\(WalletFormat.signed(transaction.amountSats, incoming: transaction.isIncoming)) \(L("walletSats"))")
                .font(.largeTitle.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(transaction.isIncoming ? AppColors.success : .primary)
                .accessibilityIdentifier("payment-detail-amount")
        }
        .frame(maxWidth: .infinity)
    }

    private func copyRow(_ label: String, _ value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            copiedTick += 1
            ToastCenter.shared.show(L("copiedToClipboardWithType", ["type": label]), style: .success)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
    }
}
