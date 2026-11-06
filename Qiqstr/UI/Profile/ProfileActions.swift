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
                    Button { Router.shared.push(.editProfile) } label: {
                        Text(L("editProfileButton"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.horizontal, 18)
                            .frame(height: 40)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .accessibilityIdentifier("profile-edit")
                } else if Session.shared.pubkey != nil {
                    FollowButton(pubkey: model.pubkey, displayName: model.displayName)
                }
            }
        }
    }
}

enum ReportReason: String, CaseIterable, Identifiable {
    case spam, nudity, profanity, illegal, impersonation, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spam: L("reportReasonSpam")
        case .nudity: L("reportReasonNudity")
        case .profanity: L("reportReasonProfanity")
        case .illegal: L("reportReasonIllegal")
        case .impersonation: L("reportReasonImpersonation")
        case .other: L("reportReasonOther")
        }
    }
}

struct ProfileModerationModifier: ViewModifier {
    let model: ProfileViewModel
    @Binding var confirmMute: Bool
    @Binding var showReport: Bool
    @State private var mutes = MuteService.shared
    @State private var feedback = 0

    func body(content: Content) -> some View {
        content
            .alert(L("muteUser", ["user": model.displayName]), isPresented: $confirmMute) {
                Button(L("mute"), role: .destructive) { Task { await setMuted(true) } }
                    .accessibilityIdentifier("confirm-mute")
                Button(L("cancel"), role: .cancel) {}
            } message: {
                Text(L("muteUserDescription"))
            }
            .confirmationDialog(L("reportUser", ["user": model.displayName]), isPresented: $showReport, titleVisibility: .visible) {
                ForEach(ReportReason.allCases) { reason in
                    Button(reason.title, role: .destructive) { Task { await report(reason) } }
                        .accessibilityIdentifier("report-\(reason.rawValue)")
                }
                Button(L("cancel"), role: .cancel) {}
            } message: {
                Text(L("reportUserDescription"))
            }
            .sensoryFeedback(.success, trigger: feedback)
    }

    private func setMuted(_ muted: Bool) async {
        do {
            if muted { try await mutes.mute(model.pubkey) } else { try await mutes.unmute(model.pubkey) }
            Session.shared.mutedPubkeys = mutes.mutedPubkeys
            feedback += 1
            DataBus.shared.feedChanged()
        } catch {
            ToastCenter.shared.error(error)
        }
    }

    private func report(_ reason: ReportReason) async {
        do {
            try await InteractionService.shared.report(pubkey: model.pubkey, noteId: nil, reason: reason.rawValue)
            feedback += 1
            ToastCenter.shared.show(L("reportSubmitted"), style: .success)
        } catch {
            ToastCenter.shared.error(error)
        }
    }

    static func unmute(_ model: ProfileViewModel) async {
        do {
            try await MuteService.shared.unmute(model.pubkey)
            Session.shared.mutedPubkeys = MuteService.shared.mutedPubkeys
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

    var body: some View {
        Menu {
            Button {
                UIPasteboard.general.string = model.npub
                ToastCenter.shared.show(L("copiedNpub"), style: .success)
            } label: { Label(L("profileCopyNpub"), systemImage: "doc.on.doc") }
            .accessibilityIdentifier("menu-copy-npub")
            ShareLink(item: URL(string: "nostr:\(model.npub)") ?? URL(string: "nostr:")!) {
                Label(L("share"), systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("menu-share")
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
    }
}
