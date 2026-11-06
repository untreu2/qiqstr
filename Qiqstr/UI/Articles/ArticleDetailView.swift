import SwiftUI

@MainActor
@Observable
final class ArticleDetailModel {
    enum Phase: Equatable { case loading, fetching, loaded, missing }

    private(set) var phase: Phase = .loading
    private(set) var article: Article?
    private(set) var blocks: [MarkdownBlock] = []

    func load(articleId: String?, naddr: String?) async {
        if article == nil { phase = .loading }
        if let naddr = naddr ?? articleId.flatMap({ Nip19.stripScheme($0).hasPrefix("naddr1") ? $0 : nil }) {
            await load(address: ArticleAddress(naddr: naddr))
        } else if let articleId {
            await load(id: articleId)
        } else {
            phase = .missing
        }
    }

    private func load(id: String) async {
        if let local = await ArticleService.article(id: id) {
            apply(local)
            await refreshLatest(local.address)
            return
        }
        phase = .fetching
        if let remote = await ArticleService.fetch(id: id) { apply(remote) } else { phase = .missing }
    }

    private func load(address: ArticleAddress?) async {
        guard let address else { phase = .missing; return }
        if let local = await ArticleService.article(at: address) {
            apply(local)
            await refreshLatest(address)
            return
        }
        phase = .fetching
        if let remote = await ArticleService.fetch(address: address) { apply(remote) } else { phase = .missing }
    }

    private func refreshLatest(_ address: ArticleAddress) async {
        guard let latest = await ArticleService.fetch(address: address), let current = article, latest.createdAt > current.createdAt else { return }
        apply(latest)
    }

    private func apply(_ article: Article) {
        let changed = self.article?.id != article.id
        self.article = article
        if changed {
            blocks = MarkdownParser.parse(article.content)
            let mentioned = MarkdownParser.pubkeys(in: article.content)
            Task { await ProfileCache.shared.load([article.pubkey] + mentioned) }
        }
        phase = .loaded
    }
}

struct ArticleDetailView: View {
    var articleId: String? = nil
    var naddr: String? = nil
    init(articleId: String) { self.articleId = articleId }
    init(naddr: String) { self.naddr = naddr }

    @State private var model = ArticleDetailModel()
    @State private var cache = ProfileCache.shared
    @State private var copied = 0

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                LoadingView()
            case .fetching:
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text(L("exploreFetchingArticle")).font(.system(size: 15)).foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .missing:
                EmptyStateView(systemImage: "doc.questionmark", title: L("articleNotFound"), actionTitle: L("retry")) {
                    Task { await model.load(articleId: articleId, naddr: naddr) }
                }
                .frame(maxHeight: .infinity)
            case .loaded:
                if let article = model.article { content(article) }
            }
        }
        .background(AppColors.background)
        .navigationTitle(L("article"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sensoryFeedback(.success, trigger: copied)
        .task { await model.load(articleId: articleId, naddr: naddr) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let article = model.article, let naddr = article.naddr {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: "nostr:\(naddr)") { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel(L("share"))
                    .accessibilityIdentifier("article-share")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = "nostr:\(naddr)"
                        copied += 1
                        ToastCenter.shared.show(L("copiedToClipboard"), style: .success)
                    } label: { Label(L("exploreCopyArticleLink"), systemImage: "link") }
                    Button {
                        UIPasteboard.general.string = article.content
                        copied += 1
                        ToastCenter.shared.show(L("copiedToClipboard"), style: .success)
                    } label: { Label(L("exploreCopyMarkdown"), systemImage: "doc.on.doc") }
                    if let url = article.shareURL {
                        Button { Router.shared.sheet = .url(url) } label: { Label(L("exploreOpenInBrowser"), systemImage: "safari") }
                    }
                    Button { Router.shared.push(.profile(article.pubkey)) } label: { Label(L("exploreViewAuthor"), systemImage: "person.crop.circle") }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel(L("exploreMoreOptions"))
                .accessibilityIdentifier("article-more")
            }
        }
    }

    private func content(_ article: Article) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let image = article.image?.nilIfEmpty {
                    RemoteImage(url: image, maxPixel: 1600) {
                        Rectangle().fill(AppColors.overlayLight)
                    }
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .accessibilityIdentifier("article-hero")
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text(article.displayTitle)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("article-title")
                    if let summary = article.summary?.nilIfEmpty {
                        Text(summary)
                            .font(.system(size: 17))
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    authorRow(article)
                    if !article.hashtags.isEmpty {
                        ArticleTagFlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(article.hashtags, id: \.self) { tag in
                                Button { Router.shared.push(.hashtag(tag)) } label: {
                                    Text("#\(tag)")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AppColors.textPrimary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(AppColors.tile, in: Capsule())
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityIdentifier("article-hashtag-\(tag)")
                            }
                        }
                    }
                    Rectangle().fill(AppColors.divider).frame(height: 1).padding(.vertical, 4)
                    MarkdownView(blocks: model.blocks)
                        .accessibilityIdentifier("article-body")
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 60)
            }
        }
        .refreshable { await model.load(articleId: articleId, naddr: naddr) }
    }

    private func authorRow(_ article: Article) -> some View {
        Button { Router.shared.push(.profile(article.pubkey)) } label: {
            HStack(spacing: 12) {
                ProfileAvatar(pubkey: article.pubkey, size: 42, fallbackURL: article.authorImage)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cache.profile(article.pubkey)?.bestName ?? article.authorName?.nilIfEmpty ?? Profile.shortNpub(article.pubkey))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text("\(Self.dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(article.publishedAt)))) · \(L("exploreMinRead", ["count": article.readingMinutes]))")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("article-author")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        if let code = UserDefaults.standard.string(forKey: "app_language") { formatter.locale = Locale(identifier: code) }
        return formatter
    }()
}
