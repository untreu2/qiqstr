import SwiftUI

struct ProfileHeaderView: View {
    let model: ProfileViewModel
    let topInset: CGFloat
    let bannerHeight: CGFloat
    var onViewImage: (String) -> Void
    var onIdentityPositionChange: (CGFloat) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var mutes = MuteService.shared
    @State private var copiedTrigger = 0

    static let avatarSize: CGFloat = 80

    private var profile: Profile { model.profile }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StretchyBanner(url: profile.banner.nilIfEmpty, height: bannerHeight + topInset) {
                if let banner = profile.banner.nilIfEmpty { onViewImage(banner) }
            }
            VStack(alignment: .leading, spacing: 10) {
                avatarRow
                identity
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.frame(in: .named("profile-viewport")).maxY
                    } action: { onIdentityPositionChange($0) }
                if !profile.about.isEmpty {
                    ProfileBioText(text: profile.about)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("profile-about")
                }
                if !model.badges.isEmpty {
                    ProfileBadgesRow(badges: model.badges)
                        .padding(.top, 2)
                }
                details
                counts
                if let score = model.followScore, !model.isMe {
                    FollowedByRow(score: score, mutuals: model.mutualFollowers)
                }
            }
            .padding(.horizontal, 16)
        }
        .sensoryFeedback(.success, trigger: copiedTrigger)
    }

    private var avatarRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 16) {
                avatar
                Spacer(minLength: 0)
                ProfileActionButtons(model: model).fixedSize()
            }
            VStack(alignment: .leading, spacing: 12) {
                avatar
                ProfileActionButtons(model: model)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.top, 12)
    }

    private var avatar: some View {
        Button {
            if let picture = profile.picture.nilIfEmpty { onViewImage(picture) }
        } label: {
            AvatarView(url: profile.picture.nilIfEmpty, size: Self.avatarSize)
                .background {
                    Circle().fill(AppColors.background).padding(-4)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("profileImage"))
        .accessibilityIdentifier("profile-avatar")
        .padding(.top, -Self.avatarSize / 2)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 6) {
            identityLayout {
                Text(model.displayName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
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
            if model.handle != nil || showsFollowsYou {
                identityLayout {
                    if let handle = model.handle {
                        Text(handle).fixedSize(horizontal: false, vertical: true)
                    }
                    if model.handle != nil && showsFollowsYou && !dynamicTypeSize.isAccessibilitySize {
                        Text(verbatim: "·").accessibilityHidden(true)
                    }
                    if showsFollowsYou {
                        Text(L("profileFollowsYou"))
                            .lineLimit(1)
                            .accessibilityIdentifier("profile-follows-you")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Button(action: copyNpub) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Profile.shortNpub(model.pubkey))
                        .font(.subheadline.monospaced())
                    Image(systemName: "doc.on.doc").font(.caption)
                }
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("profileCopyNpub"))
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
        countsLayout {
            CountButton(value: model.followingCount, label: L("followingCount")) {
                Router.shared.push(.followList(model.pubkey, .following))
            }
            .accessibilityIdentifier("profile-following-count")
            CountButton(value: model.followerCount, label: L(model.followerCount == 1 ? "followerSingular" : "followers")) {
                Router.shared.push(.followList(model.pubkey, .followers))
            }
            .accessibilityIdentifier("profile-followers-count")
        }
    }

    private var identityLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    }

    private var countsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 16))
    }

    private var showsFollowsYou: Bool { model.followsMe && !model.isMe }

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
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(text)
                .font(.subheadline.weight(emphasized ? .medium : .regular))
                .foregroundStyle(emphasized ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
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
