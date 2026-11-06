import SwiftUI

struct AvatarView: View {
    let url: String?
    var size: CGFloat = 40
    var pubkey: String? = nil

    var body: some View {
        RemoteImage(url: url, maxPixel: size * 3) {
            ZStack {
                Circle().fill(AppColors.avatarPlaceholder.opacity(0.35))
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(AppColors.avatarPlaceholder)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct ProfileAvatar: View {
    let pubkey: String
    var size: CGFloat = 40
    var fallbackURL: String? = nil
    @State private var cache = ProfileCache.shared

    var body: some View {
        AvatarView(url: cache.profile(pubkey)?.picture.nilIfEmpty ?? fallbackURL, size: size)
            .task(id: pubkey) {
                if cache.profile(pubkey) == nil { await cache.load([pubkey]) }
            }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
