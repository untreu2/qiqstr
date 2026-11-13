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
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(resolved.nip05.nilIfEmpty ?? Profile.shortNpub(profile.pubkey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if showsFollowButton, profile.pubkey != Session.shared.pubkey {
                ExploreFollowButton(pubkey: profile.pubkey)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityIdentifier("user-row-\(profile.pubkey)")
    }
}

struct ExploreFollowButton: View {
    let pubkey: String
    @State private var follows = FollowService.shared
    @State private var busy = false
    @State private var feedback = 0
    @State private var confirmNewList = false

    var body: some View {
        let following = follows.isFollowing(pubkey)
        styled(Button {
            Task { await toggle(following) }
        } label: {
            Text(following ? L("following") : L("follow"))
                .fontWeight(.semibold)
                .opacity(busy ? 0 : 1)
                .overlay { if busy { ProgressView().controlSize(.small) } }
        }, following: following)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .disabled(busy)
        .sensoryFeedback(.impact(weight: .light), trigger: feedback)
        .accessibilityIdentifier("user-follow-\(pubkey)")
        .newFollowListConfirmation(isPresented: $confirmNewList) {
            Task { await toggle(false, creatingList: true) }
        }
    }

    @ViewBuilder
    private func styled(_ button: some View, following: Bool) -> some View {
        if following {
            button.buttonStyle(.bordered)
        } else {
            button.buttonStyle(.borderedProminent).foregroundStyle(AppColors.background)
        }
    }

    private func toggle(_ following: Bool, creatingList: Bool = false) async {
        busy = true
        defer { busy = false }
        do {
            if following { try await follows.unfollow(pubkey) } else { try await follows.follow(pubkey, creatingList: creatingList) }
            feedback += 1
        } catch FollowError.listNotFound {
            confirmNewList = !following
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
