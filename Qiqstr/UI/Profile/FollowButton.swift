import SwiftUI

struct FollowButton: View {
    let pubkey: String
    var displayName: String? = nil
    var compact = false
    @State private var follows = FollowService.shared
    @State private var cache = ProfileCache.shared
    @State private var isWorking = false
    @State private var optimistic: Bool?
    @State private var confirmUnfollow = false
    @State private var feedback = 0

    private var isFollowing: Bool { optimistic ?? follows.isFollowing(pubkey) }

    private var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return cache.profile(pubkey)?.bestName ?? L("anonymous")
    }

    var body: some View {
        styled(Button {
            if isFollowing { confirmUnfollow = true } else { Task { await toggle(follow: true) } }
        } label: {
            HStack(spacing: 6) {
                if isWorking {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: isFollowing ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus")
                }
                Text(isFollowing ? L("following") : L("follow"))
                    .lineLimit(1)
            }
            .font((compact ? Font.footnote : Font.subheadline).weight(.semibold))
        })
        .buttonBorderShape(.capsule)
        .controlSize(compact ? .small : .regular)
        .disabled(isWorking)
        .animation(.snappy(duration: 0.2), value: isFollowing)
        .sensoryFeedback(.impact(weight: .light), trigger: feedback)
        .accessibilityIdentifier(isFollowing ? "unfollow-button" : "follow-button")
        .accessibilityLabel(isFollowing ? L("unfollow") : L("follow"))
        .confirmationDialog(L("unfollowUser", ["user": name]), isPresented: $confirmUnfollow, titleVisibility: .visible) {
            Button(L("unfollow"), role: .destructive) { Task { await toggle(follow: false) } }
                .accessibilityIdentifier("confirm-unfollow")
            Button(L("cancel"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private func styled(_ button: some View) -> some View {
        if isFollowing {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.glassProminent)
        }
    }

    private func toggle(follow: Bool) async {
        guard !isWorking else { return }
        isWorking = true
        optimistic = follow
        feedback += 1
        defer {
            isWorking = false
            optimistic = nil
        }
        do {
            if follow { try await follows.follow(pubkey) } else { try await follows.unfollow(pubkey) }
        } catch {
            ToastCenter.shared.error(error)
        }
    }
}
