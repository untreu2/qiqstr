import SwiftUI

struct FollowButton: View {
    let pubkey: String
    var displayName: String? = nil
    var compact = false
    var circular = false
    @State private var follows = FollowService.shared
    @State private var cache = ProfileCache.shared
    @State private var isWorking = false
    @State private var optimistic: Bool?
    @State private var confirmUnfollow = false
    @State private var confirmNewList = false
    @State private var feedback = 0

    private var isFollowing: Bool { optimistic ?? follows.isFollowing(pubkey) }

    private var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return cache.profile(pubkey)?.bestName ?? L("anonymous")
    }

    var body: some View {
        Group {
            if circular { circleBody } else { capsuleBody }
        }
        .newFollowListConfirmation(isPresented: $confirmNewList) {
            Task { await toggle(follow: true, creatingList: true) }
        }
    }

    private var circleBody: some View {
        styled(Button {
            if isFollowing { confirmUnfollow = true } else { Task { await toggle(follow: true) } }
        } label: {
            ZStack {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: isFollowing ? "person.fill.checkmark" : "person.fill.badge.plus")
                        .font(.body.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 40, height: 40)
        })
        .buttonBorderShape(.circle)
        .disabled(isWorking)
        .modifier(FollowFeedback(feedback: feedback, isFollowing: isFollowing, name: name, confirmUnfollow: $confirmUnfollow) {
            Task { await toggle(follow: false) }
        })
    }

    private var capsuleBody: some View {
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
        .modifier(FollowFeedback(feedback: feedback, isFollowing: isFollowing, name: name, confirmUnfollow: $confirmUnfollow) {
            Task { await toggle(follow: false) }
        })
    }

    @ViewBuilder
    private func styled(_ button: some View) -> some View {
        if isFollowing {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.glassProminent).foregroundStyle(AppColors.background)
        }
    }

    private func toggle(follow: Bool, creatingList: Bool = false) async {
        guard !isWorking else { return }
        isWorking = true
        optimistic = follow
        feedback += 1
        defer {
            isWorking = false
            optimistic = nil
        }
        do {
            if follow { try await follows.follow(pubkey, creatingList: creatingList) } else { try await follows.unfollow(pubkey) }
        } catch FollowError.listNotFound {
            confirmNewList = follow
        } catch {
            ToastCenter.shared.error(error)
        }
    }
}

struct NewFollowListConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let create: () -> Void

    func body(content: Content) -> some View {
        content.alert(L("followListMissingTitle"), isPresented: $isPresented) {
            Button(L("followListCreateNew"), action: create)
                .accessibilityIdentifier("follow-list-create-new")
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(L("followListMissingMessage"))
        }
    }
}

extension View {
    func newFollowListConfirmation(isPresented: Binding<Bool>, create: @escaping () -> Void) -> some View {
        modifier(NewFollowListConfirmation(isPresented: isPresented, create: create))
    }
}

private struct FollowFeedback: ViewModifier {
    let feedback: Int
    let isFollowing: Bool
    let name: String
    @Binding var confirmUnfollow: Bool
    let unfollow: () -> Void

    func body(content: Content) -> some View {
        content
            .animation(.snappy(duration: 0.2), value: isFollowing)
            .sensoryFeedback(.impact(weight: .light), trigger: feedback)
            .accessibilityIdentifier(isFollowing ? "unfollow-button" : "follow-button")
            .accessibilityLabel(isFollowing ? L("unfollow") : L("follow"))
            .confirmationDialog(L("unfollowUser", ["user": name]), isPresented: $confirmUnfollow, titleVisibility: .visible) {
                Button(L("unfollow"), role: .destructive, action: unfollow)
                    .accessibilityIdentifier("confirm-unfollow")
                Button(L("cancel"), role: .cancel) {}
            }
    }
}
