import SwiftUI

@MainActor
@Observable
final class DMSafetyModel {
    var blockTarget: String?
    var deleteTarget: String?
    var reportTarget: ReportTarget?
}

struct DMSafetyMenuItems: View {
    let peer: String
    let safety: DMSafetyModel
    @State private var mutes = MuteService.shared

    var body: some View {
        Section {
            if mutes.isMuted(peer) {
                Button(L("dmUnblock"), systemImage: "hand.raised.slash") {
                    Task { try? await MuteService.shared.unmute(peer) }
                }
                .accessibilityIdentifier("dm-unblock")
            } else {
                Button(L("block"), systemImage: "hand.raised", role: .destructive) { safety.blockTarget = peer }
                    .accessibilityIdentifier("dm-block")
            }
            Button(L("report"), systemImage: "flag", role: .destructive) { safety.reportTarget = ReportTarget(pubkey: peer) }
                .accessibilityIdentifier("dm-report")
            Button(L("dmDeleteConversation"), systemImage: "trash", role: .destructive) { safety.deleteTarget = peer }
                .accessibilityIdentifier("dm-delete-conversation")
        }
    }
}

struct DMSafetyDialogs: ViewModifier {
    @Bindable var safety: DMSafetyModel
    var onRemoved: ((String) -> Void)?
    @State private var cache = ProfileCache.shared

    func body(content: Content) -> some View {
        content
            .alert(blockTitle, isPresented: isPresenting(\.blockTarget), presenting: safety.blockTarget) { peer in
                Button(L("block"), role: .destructive) { block(peer) }
                    .accessibilityIdentifier("dm-block-confirm")
                Button(L("cancel"), role: .cancel) {}
            } message: { _ in
                Text(L("dmBlockMessage"))
            }
            .confirmationDialog(L("dmDeleteConversation"), isPresented: isPresenting(\.deleteTarget), titleVisibility: .visible, presenting: safety.deleteTarget) { peer in
                Button(L("delete"), role: .destructive) {
                    DMService.shared.deleteConversation(with: peer)
                    onRemoved?(peer)
                }
                .accessibilityIdentifier("dm-delete-confirm")
                Button(L("cancel"), role: .cancel) {}
            } message: { _ in
                Text(L("dmDeleteConversationMessage"))
            }
            .reportSheet($safety.reportTarget) { target in
                if MuteService.shared.isMuted(target.pubkey) { onRemoved?(target.pubkey) }
            }
    }

    private var blockTitle: String {
        let peer = safety.blockTarget ?? ""
        return L("dmBlockUser", ["user": cache.profile(peer)?.bestName ?? Profile.shortNpub(peer)])
    }

    private func isPresenting(_ keyPath: ReferenceWritableKeyPath<DMSafetyModel, String?>) -> Binding<Bool> {
        Binding(get: { safety[keyPath: keyPath] != nil }, set: { if !$0 { safety[keyPath: keyPath] = nil } })
    }

    private func block(_ peer: String) {
        Task {
            await Moderation.mute(peer)
            ToastCenter.shared.show(L("dmUserBlocked"), style: .success)
            onRemoved?(peer)
        }
    }
}

struct DMMediaGate<Content: View>: View {
    let message: DMMessage
    let shape: UnevenRoundedRectangle
    @ViewBuilder let content: () -> Content
    @State private var isAllowed = false
    @State private var service = DMService.shared

    var body: some View {
        if isAllowed || message.isMine || service.isKnown(message.peer) {
            content()
        } else {
            Button {
                isAllowed = true
            } label: {
                Label(L("dmLoadMedia"), systemImage: "eye.slash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .frame(minWidth: 200, minHeight: 96)
                    .background(AppColors.tile)
                    .clipShape(shape)
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dm-media-gate")
        }
    }
}
