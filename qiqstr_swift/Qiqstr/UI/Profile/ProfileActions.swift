import SwiftUI

struct ProfileActionButtons: View {
    let model: ProfileViewModel

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if !model.isMe {
                    GlassIconButton(systemImage: "bubble.left", size: 40, accessibilityLabel: L("message")) {
                        Router.shared.push(.dmChat(model.pubkey))
                    }
                    .accessibilityIdentifier("profile-message")
                    if !model.profile.lud16.isEmpty {
                        GlassIconButton(systemImage: "bolt", size: 40, accessibilityLabel: L("zap")) {
                            Router.shared.sheet = .zapProfile(model.pubkey)
                        }
                        .accessibilityIdentifier("profile-zap")
                    }
                }
                GlassIconButton(systemImage: "qrcode", size: 40, accessibilityLabel: L("shareProfile")) {
                    Router.shared.sheet = .shareProfile(model.pubkey)
                }
                .accessibilityIdentifier("profile-share")
                if model.isMe {
                    GlassIconButton(systemImage: "pencil", size: 40, accessibilityLabel: L("editProfileButton")) {
                        Router.shared.push(.editProfile)
                    }
                    .accessibilityIdentifier("profile-edit")
                } else if Session.shared.pubkey != nil {
                    FollowButton(pubkey: model.pubkey, displayName: model.displayName, circular: true)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

struct ProfileModerationModifier: ViewModifier {
    let model: ProfileViewModel
    @Binding var confirmMute: Bool
    @Binding var showReport: Bool
    @State private var mutes = MuteService.shared
    @State private var feedback = 0

    private var reportTarget: Binding<ReportTarget?> {
        Binding(
            get: { showReport ? ReportTarget(pubkey: model.pubkey, name: model.displayName) : nil },
            set: { if $0 == nil { showReport = false } }
        )
    }

    func body(content: Content) -> some View {
        content
            .alert(L("muteUser", ["user": model.displayName]), isPresented: $confirmMute) {
                Button(L("mute"), role: .destructive) { Task { await setMuted(true) } }
                    .accessibilityIdentifier("confirm-mute")
                Button(L("cancel"), role: .cancel) {}
            } message: {
                Text(L("muteUserDescription"))
            }
            .reportSheet(reportTarget) { _ in feedback += 1 }
            .sensoryFeedback(.success, trigger: feedback)
    }

    private func setMuted(_ muted: Bool) async {
        do {
            if muted { try await mutes.mute(model.pubkey) } else { try await mutes.unmute(model.pubkey) }
            feedback += 1
            DataBus.shared.feedChanged()
        } catch {
            ToastCenter.shared.error(error)
        }
    }

    static func unmute(_ model: ProfileViewModel) async {
        do {
            try await MuteService.shared.unmute(model.pubkey)
            DataBus.shared.feedChanged()
        } catch {
            ToastCenter.shared.error(error)
        }
    }
}

struct ProfileMenu: View {
    let model: ProfileViewModel
    @Binding var confirmMute: Bool
    @Binding var showReport: Bool
    @State private var mutes = MuteService.shared
    @State private var showAddToList = false

    var body: some View {
        Menu {
            Button {
                UIPasteboard.general.string = model.npub
                ToastCenter.shared.show(L("copiedNpub"), style: .success)
            } label: { Label(L("profileCopyNpub"), systemImage: "doc.on.doc") }
            .accessibilityIdentifier("menu-copy-npub")
            Button {
                UIPasteboard.general.url = model.profileLink
                ToastCenter.shared.show(L("profileLinkCopied"), style: .success)
            } label: { Label(L("profileCopyLink"), systemImage: "link") }
            .accessibilityIdentifier("menu-copy-link")
            ShareLink(item: model.profileLink, subject: Text(model.displayName)) {
                Label(L("shareProfile"), systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("menu-share")
            Button { Router.shared.sheet = .shareProfile(model.pubkey) } label: {
                Label(L("profileShowQRCode"), systemImage: "qrcode")
            }
            .accessibilityIdentifier("menu-qr")
            if !model.isMe, Session.shared.privateKey != nil {
                Divider()
                Button { showAddToList = true } label: {
                    Label(L("addToList"), systemImage: "text.badge.plus")
                }
                .accessibilityIdentifier("menu-add-to-list")
            }
            if !model.isMe, Session.shared.pubkey != nil {
                Divider()
                if mutes.isMuted(model.pubkey) {
                    Button { Task { await ProfileModerationModifier.unmute(model) } } label: {
                        Label(L("unmute"), systemImage: "speaker.wave.2")
                    }
                    .accessibilityIdentifier("menu-unmute")
                } else {
                    Button(role: .destructive) { confirmMute = true } label: {
                        Label(L("mute"), systemImage: "speaker.slash")
                    }
                    .accessibilityIdentifier("menu-mute")
                }
                Button(role: .destructive) { showReport = true } label: {
                    Label(L("report"), systemImage: "flag")
                }
                .accessibilityIdentifier("menu-report")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(L("profileMoreActions"))
        .accessibilityIdentifier("profile-menu")
        .sheet(isPresented: $showAddToList) {
            AddToListSheet(pubkey: model.pubkey, displayName: model.displayName)
        }
    }
}
