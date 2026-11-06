import SwiftUI

struct UserRowView: View {
    let pubkey: String
    var showFollowButton = true
    var onTap: (() -> Void)? = nil
    @State private var cache = ProfileCache.shared

    init(pubkey: String, showFollowButton: Bool = true, onTap: (() -> Void)? = nil) {
        self.pubkey = pubkey
        self.showFollowButton = showFollowButton
        self.onTap = onTap
    }

    private var profile: Profile? { cache.profile(pubkey) }
    private var isMe: Bool { Session.shared.pubkey == pubkey }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                ProfileAvatar(pubkey: pubkey, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(profile?.bestName ?? Profile.shortNpub(pubkey))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let onTap { onTap() } else { Router.shared.push(.profile(pubkey)) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            if showFollowButton, !isMe, Session.shared.pubkey != nil {
                FollowButton(pubkey: pubkey, compact: true)
            }
        }
        .padding(.vertical, 6)
        .contextMenu { contextMenu }
        .accessibilityIdentifier("user-row-\(pubkey.prefix(12))")
        .task(id: pubkey) {
            if profile == nil { await cache.load([pubkey]) }
        }
    }

    private var subtitle: String {
        if let nip05 = profile?.nip05, !nip05.isEmpty { return Nip05Verifier.display(nip05) }
        return Profile.shortNpub(pubkey)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button { Router.shared.push(.profile(pubkey)) } label: { Label(L("profile"), systemImage: "person") }
        Button {
            UIPasteboard.general.string = Nip19.npub(pubkey) ?? pubkey
            ToastCenter.shared.show(L("copiedNpub"), style: .success)
        } label: { Label(L("copy"), systemImage: "doc.on.doc") }
        if !isMe {
            Button { Router.shared.push(.dmChat(pubkey)) } label: { Label(L("message"), systemImage: "bubble.left") }
        }
        Button { Router.shared.sheet = .shareProfile(pubkey) } label: { Label(L("shareProfile"), systemImage: "qrcode") }
    }
}
