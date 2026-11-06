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
    @ScaledMetric(relativeTo: .headline) private var authorAvatarSize: CGFloat = 40

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                LoadingView()
            case .fetching:
                ProgressView(L("exploreFetchingArticle"))
                    .controlSize(.large)
                    .foregroundStyle(.secondary)
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
        if let article = model.article {
            if let naddr = article.naddr {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: "nostr:\(naddr)") { Label(L("share"), systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("article-share")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let naddr = article.naddr {
                        Button {
                            copy("nostr:\(naddr)")
                        } label: { Label(L("exploreCopyArticleLink"), systemImage: "link") }
                    }
                    Button {
                        copy(article.content)
                    } label: { Label(L("exploreCopyMarkdown"), systemImage: "doc.on.doc") }
                    if let url = article.shareURL {
                        Button { Router.shared.sheet = .url(url) } label: { Label(L("exploreOpenInBrowser"), systemImage: "safari") }
                    }
                    Divider()
                    Button { Router.shared.push(.profile(article.pubkey)) } label: { Label(L("exploreViewAuthor"), systemImage: "person.crop.circle") }
                } label: {
                    Label(L("exploreMoreOptions"), systemImage: "ellipsis")
                }
                .accessibilityIdentifier("article-more")
            }
        }
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        copied += 1
        ToastCenter.shared.show(L("copiedToClipboard"), style: .success)
    }

    private func content(_ article: Article) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let image = article.image?.nilIfEmpty {
                    Color.clear
                        .aspectRatio(3 / 2, contentMode: .fit)
                        .overlay {
                            RemoteImage(url: image, maxPixel: 1600) {
                                Rectangle().fill(.quaternary)
                            }
                        }
                        .clipShape(.rect(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .frame(maxWidth: Self.readableWidth + 32)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("article-hero")
                }
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(article.displayTitle)
                            .font(.largeTitle.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("article-title")
                        if let summary = article.summary?.nilIfEmpty {
                            Text(summary)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    authorRow(article)
                    if !article.hashtags.isEmpty {
                        ArticleTagFlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(article.hashtags, id: \.self) { tag in
                                Button("#\(tag)") { Router.shared.push(.hashtag(tag)) }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                    .controlSize(.small)
                                    .accessibilityIdentifier("article-hashtag-\(tag)")
                            }
                        }
                    }
                    Divider()
                    MarkdownView(blocks: model.blocks)
                        .accessibilityIdentifier("article-body")
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 60)
                .frame(maxWidth: Self.readableWidth + 40, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .refreshable { await model.load(articleId: articleId, naddr: naddr) }
    }

    private func authorRow(_ article: Article) -> some View {
        Button { Router.shared.push(.profile(article.pubkey)) } label: {
            HStack(spacing: 12) {
                ProfileAvatar(pubkey: article.pubkey, size: authorAvatarSize, fallbackURL: article.authorImage)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cache.profile(article.pubkey)?.bestName ?? article.authorName?.nilIfEmpty ?? Profile.shortNpub(article.pubkey))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(Self.dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(article.publishedAt)))) · \(L("exploreMinRead", ["count": article.readingMinutes]))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("article-author")
    }

    private static let readableWidth: CGFloat = 680

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        if let code = UserDefaults.standard.string(forKey: "app_language") { formatter.locale = Locale(identifier: code) }
        return formatter
    }()
}
