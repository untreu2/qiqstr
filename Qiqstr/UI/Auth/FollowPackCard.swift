import SwiftUI

struct FollowPackHeader: View {
    let pack: FollowPack
    let isSelected: Bool
    let isDisabled: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                FollowPackArtwork(url: pack.image.nilIfEmpty, isBuiltIn: pack.kind == 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pack.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let summary = pack.summary.nilIfEmpty {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                FollowPackAvatarStack(pubkeys: Array(pack.members.prefix(5)))
                Text(L("memberCount", ["count": pack.members.count]))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                PillButton(title: isSelected ? L("authPackSelected") : L("authFollowAll"), systemImage: isSelected ? "checkmark" : nil, filled: !isSelected, action: onToggle)
                    .disabled(isDisabled)
                    .accessibilityIdentifier("pack-follow-all")
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

struct FollowPackArtwork: View {
    let url: String?
    var isBuiltIn = false

    var body: some View {
        Group {
            if let url {
                RemoteImage(url: url, maxPixel: 168) { fallback }
            } else {
                fallback
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        IconTile(systemImage: isBuiltIn ? "sparkles" : "person.3.fill", size: 56)
    }
}

struct FollowPackAvatarStack: View {
    let pubkeys: [String]
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(pubkeys, id: \.self) { pubkey in
                ProfileAvatar(pubkey: pubkey, size: size)
                    .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}

struct FollowPackSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColors.tile)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Follow pack title")
                        .font(.headline)
                    Text(verbatim: "A short description of the people in this follow pack")
                        .font(.subheadline)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                HStack(spacing: -8) {
                    ForEach(0..<5, id: \.self) { _ in
                        Circle().fill(AppColors.tile).frame(width: 28, height: 28)
                    }
                }
                Text(verbatim: "24 members").font(.footnote)
                Spacer()
                Capsule().fill(AppColors.tile).frame(width: 84, height: 30)
            }
        }
        .padding(.vertical, 6)
        .redacted(reason: .placeholder)
        .phaseAnimator([0.45, 1]) { content, opacity in
            content.opacity(opacity)
        } animation: { _ in .easeInOut(duration: 0.9) }
        .accessibilityHidden(true)
    }
}

struct FollowPackMemberRow: View {
    let pubkey: String
    let isSelected: Bool
    let alreadyFollowing: Bool
    let action: () -> Void

    @State private var cache = ProfileCache.shared

    var body: some View {
        let profile = cache.profile(pubkey)
        Button(action: action) {
            HStack(spacing: 12) {
                ProfileAvatar(pubkey: pubkey, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile?.bestName ?? Profile.shortNpub(pubkey))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let detail = profile?.about.nilIfEmpty ?? profile?.nip05.nilIfEmpty {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if alreadyFollowing {
                    Text(L("following"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(alreadyFollowing)
        .accessibilityAddTraits(isSelected || alreadyFollowing ? .isSelected : [])
        .accessibilityIdentifier("suggested-user-\(pubkey.prefix(8))")
    }
}
