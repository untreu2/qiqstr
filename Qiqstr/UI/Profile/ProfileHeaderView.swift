import SwiftUI

struct ProfileHeaderView: View {
    let model: ProfileViewModel
    let topInset: CGFloat
    let bannerHeight: CGFloat
    var onViewImage: (String) -> Void
    @State private var mutes = MuteService.shared
    @State private var copiedTrigger = 0

    static let avatarSize: CGFloat = 76

    private var profile: Profile { model.profile }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StretchyBanner(url: profile.banner.nilIfEmpty, height: bannerHeight + topInset) {
                if let banner = profile.banner.nilIfEmpty { onViewImage(banner) }
            }
            .overlay(alignment: .bottomTrailing) {
                ProfileActionButtons(model: model)
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
            }
            VStack(alignment: .leading, spacing: 10) {
                avatarRow
                identity
                if !profile.about.isEmpty {
                    ProfileBioText(text: profile.about)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("profile-about")
                }
                details
                counts
                if let score = model.followScore, !model.isMe {
                    FollowedByRow(score: score)
                }
            }
            .padding(.horizontal, 16)
        }
        .sensoryFeedback(.success, trigger: copiedTrigger)
    }

    private var avatarRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                if let picture = profile.picture.nilIfEmpty { onViewImage(picture) }
            } label: {
                AvatarView(url: profile.picture.nilIfEmpty, size: Self.avatarSize)
                    .padding(4)
                    .background(AppColors.background, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("profileImage"))
            .accessibilityIdentifier("profile-avatar")
            Spacer(minLength: 0)
        }
        .padding(.top, -(Self.avatarSize / 2 + 4))
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(model.displayName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .accessibilityIdentifier("profile-name")
                if mutes.isMuted(model.pubkey) {
                    Text(L("mutedButton"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.tile, in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            if let handle = model.handle {
                Text(handle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Button(action: copyNpub) {
                HStack(spacing: 4) {
                    Text(Profile.shortNpub(model.pubkey))
                        .font(.subheadline.monospaced())
                    Image(systemName: "doc.on.doc").font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("copiedNpub"))
            .accessibilityIdentifier("profile-copy-npub")
        }
    }

    @ViewBuilder
    private var details: some View {
        let hasDetails = !profile.nip05.isEmpty || !profile.lud16.isEmpty || model.websiteURL != nil || !profile.location.isEmpty
        if hasDetails {
            VStack(alignment: .leading, spacing: 8) {
                if !profile.nip05.isEmpty {
                    DetailRow(systemImage: "at", text: Nip05Verifier.display(profile.nip05))
                        .accessibilityIdentifier("profile-nip05")
                }
                if let url = model.websiteURL {
                    Button { Router.shared.sheet = .url(url) } label: {
                        DetailRow(systemImage: "link", text: ProfileBioText.prettyLink(profile.website), emphasized: true)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { copy(url.absoluteString) } label: { Label(L("copy"), systemImage: "doc.on.doc") }
                        ShareLink(item: url) { Label(L("share"), systemImage: "square.and.arrow.up") }
                    }
                    .accessibilityIdentifier("profile-website")
                }
                if !profile.lud16.isEmpty {
                    Button { if !model.isMe { Router.shared.sheet = .zapProfile(model.pubkey) } else { copy(profile.lud16) } } label: {
                        DetailRow(systemImage: "bolt.fill", text: profile.lud16, tint: AppColors.zap)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { copy(profile.lud16) } label: { Label(L("copy"), systemImage: "doc.on.doc") }
                    }
                    .accessibilityIdentifier("profile-lud16")
                }
                if !profile.location.isEmpty {
                    DetailRow(systemImage: "mappin.and.ellipse", text: profile.location)
                        .accessibilityIdentifier("profile-location")
                }
            }
        }
    }

    private var counts: some View {
        HStack(spacing: 14) {
            CountButton(value: model.followingCount, label: L("followingCount")) {
                Router.shared.push(.followList(model.pubkey, .following))
            }
            .accessibilityIdentifier("profile-following-count")
            CountButton(value: model.followerCount, label: L(model.followerCount == 1 ? "followerSingular" : "followers")) {
                Router.shared.push(.followList(model.pubkey, .followers))
            }
            .accessibilityIdentifier("profile-followers-count")
            if model.followsMe && !model.isMe {
                Text(L("followingYou"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.tile, in: Capsule())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("profile-follows-you")
            }
        }
    }

    private func copyNpub() {
        UIPasteboard.general.string = model.npub
        copiedTrigger += 1
        ToastCenter.shared.show(L("copiedNpub"), style: .success)
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        copiedTrigger += 1
        ToastCenter.shared.show(L("copiedToClipboard"), style: .success)
    }
}

private struct DetailRow: View {
    let systemImage: String
    let text: String
    var emphasized = false
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(text)
                .font(.subheadline.weight(emphasized ? .medium : .regular))
                .foregroundStyle(emphasized ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contentShape(Rectangle())
    }
}

private struct CountButton: View {
    let value: Int?
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let value {
                    Text(Sats.compact(value))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                } else {
                    ProgressView().controlSize(.mini)
                }
                Text(label).font(.subheadline).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: value)
    }
}

struct FollowedByRow: View {
    let score: FollowScore
    private let size: CGFloat = 24

    var body: some View {
        HStack(spacing: 8) {
            let avatars = Array(score.avatarUrls.prefix(5))
            if !avatars.isEmpty {
                HStack(spacing: -7) {
                    ForEach(Array(avatars.enumerated()), id: \.offset) { index, url in
                        AvatarView(url: url, size: size)
                            .padding(1.5)
                            .background(AppColors.background, in: Circle())
                            .zIndex(Double(avatars.count - index))
                    }
                }
            }
            Text(score.count == 1 ? L("profileFollowedByOne") : L("profileFollowedByMany", ["count": Sats.compact(score.count)]))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile-followed-by")
    }
}

struct StretchyBanner: View {
    let url: String?
    let height: CGFloat
    var onTap: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .scrollView).minY
            let stretch = max(0, minY)
            ZStack {
                placeholder
                if let url {
                    RemoteImage(url: url, maxPixel: 1600) { placeholder }
                }
            }
            .frame(width: proxy.size.width, height: height + stretch)
            .clipped()
            .overlay(alignment: .top) {
                LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 110 + stretch)
                    .allowsHitTesting(false)
            }
            .offset(y: -stretch)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
        }
        .frame(height: height)
        .accessibilityIdentifier("profile-banner")
    }

    private var placeholder: some View {
        LinearGradient(colors: [AppColors.tile, AppColors.overlayLight], startPoint: .topLeading, endPoint: .bottomTrailing)
            .background(AppColors.background)
    }
}
