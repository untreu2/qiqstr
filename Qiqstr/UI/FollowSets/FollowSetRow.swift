import SwiftUI

extension FollowSet {
    static func memberCountText(_ count: Int) -> String {
        switch count {
        case 0: L("exploreMembersZero")
        case 1: L("exploreMembersOne")
        default: L("exploreMembersOther", ["count": count])
        }
    }
}

struct FollowSetRow: View {
    let set: FollowSet
    var showsOwner = false
    var isFavorite = false
    @State private var cache = ProfileCache.shared

    var body: some View {
        HStack(spacing: 14) {
            FollowSetAvatarStack(pubkeys: Array(set.pubkeys.prefix(3)), fallbackIcon: "person.2")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(set.displayTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if isFavorite {
                        Image(systemName: "pin.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(L("exploreInFeed"))
                    }
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .task(id: set.id) {
            await cache.load(Array(set.pubkeys.prefix(3)) + (showsOwner ? [set.pubkey] : []))
        }
    }

    private var subtitle: String {
        let count = FollowSet.memberCountText(set.pubkeys.count)
        guard showsOwner else { return set.description.isEmpty ? count : "\(count) · \(set.description)" }
        let owner = cache.profile(set.pubkey)?.bestName ?? Profile.shortNpub(set.pubkey)
        return "\(count) · \(L("exploreByAuthor", ["name": owner]))"
    }
}

struct FollowSetAvatarStack: View {
    let pubkeys: [String]
    var size: CGFloat = 30
    var fallbackIcon = "person.2"

    var body: some View {
        ZStack {
            if pubkeys.isEmpty {
                IconTile(systemImage: fallbackIcon, size: 46, tint: .secondary)
            } else {
                ForEach(Array(pubkeys.enumerated()), id: \.offset) { index, pubkey in
                    ProfileAvatar(pubkey: pubkey, size: size)
                        .overlay(Circle().strokeBorder(AppColors.background, lineWidth: 2))
                        .offset(x: CGFloat(index) * 8 - CGFloat(pubkeys.count - 1) * 4, y: CGFloat(index % 2 == 0 ? -4 : 4))
                        .zIndex(Double(-index))
                }
            }
        }
        .frame(width: 46, height: 46)
        .accessibilityHidden(true)
    }
}
