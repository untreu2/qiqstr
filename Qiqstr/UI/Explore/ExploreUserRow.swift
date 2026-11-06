import SwiftUI

struct ExploreUserRow: View {
    let profile: Profile
    var showsFollowButton = true
    var avatarSize: CGFloat = 44
    @State private var cache = ProfileCache.shared

    private var resolved: Profile { cache.profile(profile.pubkey) ?? profile }

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatar(pubkey: profile.pubkey, size: avatarSize, fallbackURL: profile.picture.nilIfEmpty)
            VStack(alignment: .leading, spacing: 2) {
                Text(resolved.bestName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(resolved.nip05.nilIfEmpty ?? Profile.shortNpub(profile.pubkey))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if showsFollowButton, profile.pubkey != Session.shared.pubkey {
                ExploreFollowButton(pubkey: profile.pubkey)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityIdentifier("user-row-\(profile.pubkey)")
    }
}

struct ExploreFollowButton: View {
    let pubkey: String
    @State private var follows = FollowService.shared
    @State private var busy = false
    @State private var feedback = 0

    var body: some View {
        let following = follows.isFollowing(pubkey)
        Button {
            Task { await toggle(following) }
        } label: {
            ZStack {
                Text(following ? L("following") : L("follow"))
                    .font(.system(size: 14, weight: .semibold))
                    .opacity(busy ? 0 : 1)
                if busy { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .foregroundStyle(following ? AppColors.textPrimary : AppColors.background)
            .background(following ? AppColors.tile : AppColors.textPrimary, in: Capsule())
        }
        .buttonStyle(.borderless)
        .disabled(busy)
        .sensoryFeedback(.impact(weight: .light), trigger: feedback)
        .accessibilityIdentifier("user-follow-\(pubkey)")
    }

    private func toggle(_ following: Bool) async {
        busy = true
        defer { busy = false }
        do {
            if following { try await follows.unfollow(pubkey) } else { try await follows.follow(pubkey) }
            feedback += 1
        } catch {
            ToastCenter.shared.error(error)
        }
    }
}

struct ExploreUserMenu: View {
    let pubkey: String
    @State private var lists = FollowSetService.shared

    var body: some View {
        Button { Router.shared.push(.profile(pubkey)) } label: { Label(L("exploreOpenProfile"), systemImage: "person.crop.circle") }
        Button {
            UIPasteboard.general.string = Nip19.npub(pubkey) ?? pubkey
            ToastCenter.shared.show(L("copiedNpub"), style: .success)
        } label: { Label(L("exploreCopyNpub"), systemImage: "doc.on.doc") }
        if !lists.sets.isEmpty, pubkey != Session.shared.pubkey {
            Menu {
                ForEach(lists.sets) { set in
                    let member = set.pubkeys.contains(pubkey)
                    Button {
                        Task {
                            do {
                                if member { try await lists.removeMember(pubkey, from: set.id) } else { try await lists.addMember(pubkey, to: set.id) }
                                ToastCenter.shared.show(L(member ? "exploreMemberRemoved" : "exploreMemberAdded"), style: .success)
                            } catch {
                                ToastCenter.shared.error(error)
                            }
                        }
                    } label: {
                        Label(set.displayTitle, systemImage: member ? "checkmark.circle.fill" : "circle")
                    }
                }
            } label: { Label(L("addToList"), systemImage: "list.bullet") }
        }
    }
}
