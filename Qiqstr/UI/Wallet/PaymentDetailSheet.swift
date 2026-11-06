import SwiftUI

struct PaymentDetailSheet: View {
    let transaction: WalletTransaction
    @Environment(\.dismiss) private var dismiss
    @State private var showTechnical = false
    @State private var copiedTick = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    VStack(spacing: 0) {
                        row(L("status"), value: transaction.isIncoming ? L("received") : L("sent"))
                        if transaction.createdAt > 0 { row(L("date"), value: TimeFormat.full(transaction.createdAt)) }
                        if !transaction.isIncoming { row(L("fee"), value: "\(Sats.format(transaction.feesSats)) \(L("walletSats"))") }
                        row(L("method"), value: L("walletMethodLightning"))
                        if let description = transaction.description { row(L("description"), value: description, last: true) }
                    }
                    .background(AppColors.overlayLight, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    if transaction.invoice != nil || transaction.paymentHash != nil { technical }
                }
                .padding(20)
            }
            .navigationTitle(L("details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() } label: { Image(systemName: "xmark") }
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
            TransactionIcon(isIncoming: transaction.isIncoming, size: 60)
            Text("\(WalletFormat.signed(transaction.amountSats, incoming: transaction.isIncoming)) \(L("walletSats"))")
                .font(AppFont.brandSemibold(34))
                .foregroundStyle(transaction.isIncoming ? AppColors.success : AppColors.textPrimary)
                .accessibilityIdentifier("payment-detail-amount")
        }
        .padding(.top, 8)
    }

    private var technical: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { showTechnical.toggle() }
            } label: {
                HStack {
                    Text(L("details")).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(showTechnical ? 180 : 0))
                }
                .foregroundStyle(AppColors.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("payment-detail-toggle")
            if showTechnical {
                if let hash = transaction.paymentHash { copyRow(L("paymentHash"), hash) }
                if let invoice = transaction.invoice { copyRow(L("invoice"), invoice) }
            }
        }
        .padding(16)
        .background(AppColors.overlayLight, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func row(_ label: String, value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label).font(.system(size: 14)).foregroundStyle(AppColors.textSecondary)
                Spacer()
                Text(value).font(.system(size: 14, weight: .medium)).multilineTextAlignment(.trailing).textSelection(.enabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            if !last { Divider().padding(.leading, 16) }
        }
    }

    private func copyRow(_ label: String, _ value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            copiedTick += 1
            ToastCenter.shared.show(L("copiedToClipboardWithType", ["type": label]), style: .success)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(AppColors.textSecondary)
                    Text(value).font(.system(size: 12, design: .monospaced)).foregroundStyle(AppColors.textPrimary).lineLimit(4).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "doc.on.doc").font(.system(size: 14)).foregroundStyle(AppColors.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
