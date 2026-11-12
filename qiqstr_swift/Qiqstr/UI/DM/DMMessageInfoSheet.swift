import SwiftUI

struct DMMessageInfoSheet: View {
    let message: DMMessage
    let deliveryRelays: [String]
    let chatRelays: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var cache = ProfileCache.shared

    private var senderName: String {
        message.isMine ? L("dmYou") : (cache.profile(message.sender)?.bestName ?? Profile.shortNpub(message.sender))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(message.isMine ? L("dmInfoSent") : L("dmInfoReceived")) {
                        Text(message.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().hour().minute().second().locale(DMFormat.locale)))
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(L("dmInfoFrom"), value: senderName)
                    LabeledContent(L("dmInfoStatus"), value: status)
                    LabeledContent(L("dmInfoType"), value: message.isFile ? L("dmAttachment") : L("dmInfoText"))
                }
                Section {
                    Label(encryption, systemImage: message.isFile && message.file?.isEncrypted == false ? "exclamationmark.triangle" : "lock.fill")
                        .foregroundStyle(.secondary)
                }
                if message.isMine {
                    relaySection(title: L("dmInfoDeliveredTo"), relays: deliveryRelays, footer: deliveryRelays.isEmpty ? L("dmInfoRelaysUnknown") : L("dmInfoDeliveredFooter"))
                } else {
                    relaySection(title: L("dmInfoChatRelays"), relays: chatRelays, footer: chatRelays.isEmpty ? L("dmInfoRelaysUnknown") : L("dmInfoChatFooter"))
                }
            }
            .navigationTitle(L("dmInfo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("done")) { dismiss() }
                }
            }
        }
        .task { await cache.load([message.sender]) }
    }

    private var status: String {
        switch message.state {
        case .sent: message.isMine ? L("dmInfoStatusSent") : L("dmInfoStatusReceived")
        case .sending: L("dmSending")
        case .failed: L("dmSendFailed")
        }
    }

    private var encryption: String {
        if message.isFile, message.file?.isEncrypted == false { return L("notEncrypted") }
        return L("dmInfoEncrypted")
    }

    private func relaySection(title: String, relays: [String], footer: String) -> some View {
        Section {
            ForEach(relays, id: \.self) { relay in
                Label(relay.replacingOccurrences(of: "wss://", with: ""), systemImage: "server.rack")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
    }
}
