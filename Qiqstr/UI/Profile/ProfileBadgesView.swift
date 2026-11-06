import SwiftUI

struct ProfileBadgesRow: View {
    let badges: [ProfileBadge]
    @State private var showSheet = false
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 28

    private let visibleLimit = 8

    var body: some View {
        Button { showSheet = true } label: {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: size), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(badges.prefix(visibleLimit)) { badge in
                    BadgeImage(url: badge.thumbURL, size: size)
                }
                if badges.count > visibleLimit {
                    Text("+\(badges.count - visibleLimit)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("profileBadgesCount", ["count": badges.count]))
        .accessibilityHint(L("profileBadgesHint"))
        .accessibilityIdentifier("profile-badges")
        .sheet(isPresented: $showSheet) { ProfileBadgesSheet(badges: badges) }
    }
}

struct ProfileBadgesSheet: View {
    let badges: [ProfileBadge]
    @Environment(\.dismiss) private var dismiss
    @State private var cache = ProfileCache.shared

    var body: some View {
        NavigationStack {
            List(badges) { badge in
                ProfileBadgeRow(badge: badge, issuer: cache.profile(badge.issuer)) {
                    dismiss()
                    Router.shared.push(.profile(badge.issuer))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L("profileBadges"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityIdentifier("profile-badges-close")
                }
            }
            .task {
                let missing = Array(Set(badges.map(\.issuer))).filter { cache.profile($0) == nil }
                if !missing.isEmpty { await cache.load(missing) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("profile-badges-sheet")
    }
}

private struct ProfileBadgeRow: View {
    let badge: ProfileBadge
    let issuer: Profile?
    var onIssuerTap: () -> Void
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 56

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BadgeImage(url: badge.imageURL, size: size, maxPixel: 400)
            VStack(alignment: .leading, spacing: 4) {
                Text(badge.displayName)
                    .font(.headline)
                if !badge.description.isEmpty {
                    Text(badge.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button(action: onIssuerTap) {
                    HStack(spacing: 6) {
                        ProfileAvatar(pubkey: badge.issuer, size: 18)
                        Text(L("profileBadgeIssuedBy", ["name": issuer?.bestName ?? Profile.shortNpub(badge.issuer)]))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.borderless)
                .padding(.top, 2)
                .accessibilityIdentifier("profile-badge-issuer")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

private struct BadgeImage: View {
    let url: String?
    let size: CGFloat
    var maxPixel: CGFloat = 180

    var body: some View {
        RemoteImage(url: url, maxPixel: maxPixel) {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(AppColors.tile)
                .overlay {
                    Image(systemName: "rosette")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(.secondary)
                }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}
