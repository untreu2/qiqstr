import SwiftUI

struct FollowedByRow: View {
    let score: FollowScore
    var mutuals: [String] = []
    @State private var cache = ProfileCache.shared
    @State private var showSheet = false
    private let size: CGFloat = 24

    private var total: Int { max(score.count, mutuals.count) }

    var body: some View {
        Button { if !mutuals.isEmpty { showSheet = true } } label: {
            HStack(spacing: 8) {
                avatars
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !mutuals.isEmpty {
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(mutuals.isEmpty ? [] : .isButton)
        .accessibilityIdentifier("profile-followed-by")
        .sheet(isPresented: $showSheet) { MutualFollowsSheet(pubkeys: mutuals) }
    }

    @ViewBuilder
    private var avatars: some View {
        if !mutuals.isEmpty {
            let shown = Array(mutuals.prefix(3))
            HStack(spacing: -7) {
                ForEach(Array(shown.enumerated()), id: \.element) { index, pubkey in
                    ProfileAvatar(pubkey: pubkey, size: size)
                        .padding(1.5)
                        .background(AppColors.background, in: Circle())
                        .zIndex(Double(shown.count - index))
                }
            }
        } else {
            let urls = Array(score.avatarUrls.prefix(3))
            if !urls.isEmpty {
                HStack(spacing: -7) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        AvatarView(url: url, size: size)
                            .padding(1.5)
                            .background(AppColors.background, in: Circle())
                            .zIndex(Double(urls.count - index))
                    }
                }
            }
        }
    }

    private var summary: String {
        let names = mutuals.prefix(2).compactMap { cache.profile($0)?.bestName.nilIfEmpty }
        guard names.count == min(2, mutuals.count), !names.isEmpty else {
            return total == 1 ? L("profileFollowedByOne") : L("profileFollowedByMany", ["count": Sats.compact(total)])
        }
        let others = total - names.count
        let lead = names.count == 1
            ? L("profileFollowedByOneName", ["first": names[0]])
            : L("profileFollowedByTwoNames", ["first": names[0], "second": names[1]])
        guard others > 0 else { return lead }
        let list = names.count == 1 ? names[0] : L("profileNameList", ["first": names[0], "second": names[1]])
        return others == 1
            ? L("profileFollowedByNamesAndOne", ["names": list])
            : L("profileFollowedByNamesAndOthers", ["names": list, "count": Sats.compact(others)])
    }
}

struct MutualFollowsSheet: View {
    let pubkeys: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(pubkeys, id: \.self) { pubkey in
                UserRowView(pubkey: pubkey) {
                    dismiss()
                    Router.shared.push(.profile(pubkey))
                }
            }
            .listStyle(.plain)
            .navigationTitle(L("profileMutualFollowsTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityIdentifier("mutual-follows-close")
                }
            }
            .task {
                let missing = pubkeys.filter { ProfileCache.shared.profile($0) == nil }
                if !missing.isEmpty { await ProfileCache.shared.load(missing) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("mutual-follows-sheet")
    }
}
