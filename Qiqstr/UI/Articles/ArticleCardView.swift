import SwiftUI

struct ArticleCardView: View {
    let article: Article
    @State private var cache = ProfileCache.shared
    @ScaledMetric(relativeTo: .footnote) private var avatarSize: CGFloat = 20

    private var authorName: String {
        cache.profile(article.pubkey)?.bestName ?? article.authorName?.nilIfEmpty ?? Profile.shortNpub(article.pubkey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = article.image?.nilIfEmpty {
                Color.clear
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        RemoteImage(url: image, maxPixel: 1200) {
                            Rectangle().fill(.quaternary)
                                .overlay { Image(systemName: "photo").font(.title2).foregroundStyle(.secondary) }
                        }
                    }
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(article.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if let summary = article.summary?.nilIfEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                footer.padding(.top, 6)
            }
            .padding(14)
        }
        .background(AppColors.inputFill, in: .rect(cornerRadius: 20, style: .continuous))
        .clipShape(.rect(cornerRadius: 20, style: .continuous))
        .contentShape(.rect(cornerRadius: 20, style: .continuous))
        .onTapGesture { Router.shared.push(.article(article.id)) }
        .contextMenu { ArticleMenuItems(article: article) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { Router.shared.push(.article(article.id)) }
        .accessibilityIdentifier("article-card-\(article.id)")
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button { Router.shared.push(.profile(article.pubkey)) } label: {
                HStack(spacing: 6) {
                    ProfileAvatar(pubkey: article.pubkey, size: avatarSize, fallbackURL: article.authorImage)
                    Text(authorName)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("article-card-author-\(article.id)")
            Text("·")
            Text(TimeFormat.relative(article.publishedAt))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(L("exploreMinRead", ["count": article.readingMinutes]))
                .lineLimit(1)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

struct ArticleCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(.quaternary).aspectRatio(16 / 9, contentMode: .fit)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "Placeholder article title for loading").font(.headline)
                Text(verbatim: "A short summary line that stands in while articles load from relays.")
                    .font(.subheadline)
                    .lineLimit(2)
                Text(verbatim: "Author name · 2h").font(.footnote).padding(.top, 6)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.inputFill, in: .rect(cornerRadius: 20, style: .continuous))
        .clipShape(.rect(cornerRadius: 20, style: .continuous))
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
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
                RemoteImage(url: image, maxPixel: 300) { Rectangle().fill(.quaternary) }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                IconTile(systemImage: "doc.richtext", size: 72, tint: AppColors.textSecondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L("article").uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(article.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(cache.profile(article.pubkey)?.bestName ?? article.authorName?.nilIfEmpty ?? Profile.shortNpub(article.pubkey))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
