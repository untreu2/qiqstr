import SwiftUI

struct ArticleCardView: View {
    let article: Article
    @State private var cache = ProfileCache.shared

    private var authorName: String {
        cache.profile(article.pubkey)?.bestName ?? article.authorName?.nilIfEmpty ?? Profile.shortNpub(article.pubkey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = article.image?.nilIfEmpty {
                RemoteImage(url: image, maxPixel: 1200) {
                    Rectangle().fill(AppColors.overlayLight)
                        .overlay { Image(systemName: "photo").font(.system(size: 28)).foregroundStyle(AppColors.textSecondary) }
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(article.displayTitle)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let summary = article.summary?.nilIfEmpty {
                    Text(summary)
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 8) {
                    Button { Router.shared.push(.profile(article.pubkey)) } label: {
                        HStack(spacing: 8) {
                            ProfileAvatar(pubkey: article.pubkey, size: 26, fallbackURL: article.authorImage)
                            Text(authorName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("article-card-author-\(article.id)")
                    Text("·").foregroundStyle(AppColors.textSecondary)
                    Text(TimeFormat.relative(article.publishedAt))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer(minLength: 0)
                    Text(L("exploreMinRead", ["count": article.readingMinutes]))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(AppColors.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture { Router.shared.push(.article(article.id)) }
        .contextMenu { ArticleMenuItems(article: article) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { Router.shared.push(.article(article.id)) }
        .accessibilityIdentifier("article-card-\(article.id)")
    }
}

struct ArticleMenuItems: View {
    let article: Article

    var body: some View {
        Button { Router.shared.push(.article(article.id)) } label: { Label(L("read"), systemImage: "book") }
        Button { Router.shared.push(.profile(article.pubkey)) } label: { Label(L("exploreViewAuthor"), systemImage: "person.crop.circle") }
        if let naddr = article.naddr {
            ShareLink(item: "nostr:\(naddr)") { Label(L("share"), systemImage: "square.and.arrow.up") }
            Button {
                UIPasteboard.general.string = "nostr:\(naddr)"
                ToastCenter.shared.show(L("copiedToClipboard"), style: .success)
            } label: { Label(L("exploreCopyArticleLink"), systemImage: "link") }
        }
        if let url = article.shareURL {
            Button { Router.shared.sheet = .url(url) } label: { Label(L("exploreOpenInBrowser"), systemImage: "safari") }
        }
    }
}

struct CompactArticleCard: View {
    let article: Article
    @State private var cache = ProfileCache.shared

    var body: some View {
        HStack(spacing: 12) {
            if let image = article.image?.nilIfEmpty {
                RemoteImage(url: image, maxPixel: 300) { Rectangle().fill(AppColors.overlayLight) }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                IconTile(systemImage: "doc.richtext", size: 72, tint: AppColors.textSecondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L("article").uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                Text(article.displayTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(cache.profile(article.pubkey)?.bestName ?? article.authorName?.nilIfEmpty ?? Profile.shortNpub(article.pubkey))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppColors.inputFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task(id: article.pubkey) { await cache.load([article.pubkey]) }
    }
}
