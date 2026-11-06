import SwiftUI

@MainActor
@Observable
final class ArticleDetailModel {
    enum Phase: Equatable { case loading, fetching, loaded, missing }

    private(set) var phase: Phase = .loading
    private(set) var article: Article?
    private(set) var blocks: [MarkdownBlock] = []
    private(set) var highlights: [ArticleHighlight] = []
    private(set) var isLoadingHighlights = false
    @ObservationIgnored private var blockTexts: [String] = []
    @ObservationIgnored private var highlightsAddress: ArticleAddress?

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
            blockTexts = blocks.map(\.plainText)
            let mentioned = MarkdownParser.pubkeys(in: article.content)
            Task { await ProfileCache.shared.load([article.pubkey] + mentioned) }
        }
        phase = .loaded
        if highlightsAddress != article.address {
            highlightsAddress = article.address
            Task { await loadHighlights() }
        }
    }

    func loadHighlights() async {
        guard let address = article?.address else { return }
        isLoadingHighlights = true
        defer { isLoadingHighlights = false }
        let local = await HighlightService.local(for: address)
        if !local.isEmpty { highlights = local }
        let fetched = await HighlightService.fetch(for: address)
        guard address == article?.address else { return }
        highlights = fetched
        await ProfileCache.shared.load(Array(Set(fetched.map(\.pubkey))))
    }

    func publishHighlight(text: String, context: String, comment: String) async -> Bool {
        guard let article else { return false }
        do {
            let highlight = try await HighlightService.publish(text: text, context: context, comment: comment, article: article)
            if !highlights.contains(where: { $0.id == highlight.id }) { highlights.insert(highlight, at: 0) }
            ToastCenter.shared.show(L("highlightPublished"), style: .success)
            return true
        } catch {
            ToastCenter.shared.error(error)
            return false
        }
    }

    func blockIndex(for highlight: ArticleHighlight) -> Int? {
        let needle = highlight.content.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? highlight.content
        return blockTexts.firstIndex { $0.contains(needle) }
    }
}

extension MarkdownBlock {
    var plainText: String {
        switch self {
        case .heading(_, let text), .paragraph(let text): MarkdownInline.plain(text)
        case .code(_, let code): code
        case .quote(let inner): inner.map(\.plainText).joined(separator: "\n")
        case .list(_, _, let items): items.flatMap(\.blocks).map(\.plainText).joined(separator: "\n")
        case .table(let header, let rows): ([header] + rows).flatMap { $0 }.map(MarkdownInline.plain).joined(separator: "\n")
        case .image, .nostr, .rule: ""
        }
    }
}

@MainActor
@Observable
final class ReaderProgressTracker {
    var metrics = ReaderScrollMetrics(offset: 0, maxOffset: 0)
    var restored = false
    @ObservationIgnored var restoring = false
}

struct ReaderProgressBar: View {
    let tracker: ReaderProgressTracker
    let minutes: Int

    private var progress: Double { tracker.metrics.progress }

    private var timeLeft: String {
        if tracker.restored, progress >= ReadingProgressStore.finishThreshold { return L("articleFinished") }
        return L("articleMinutesLeft", ["count": max(1, Int((Double(minutes) * (1 - progress)).rounded(.up)))])
    }

    var body: some View {
        ProgressView(value: progress)
            .progressViewStyle(.linear)
            .tint(.primary)
            .scaleEffect(x: 1, y: 0.6, anchor: .top)
            .opacity(tracker.restored ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: tracker.restored)
            .navigationSubtitle(timeLeft)
            .accessibilityLabel(L("articleReadingProgress"))
            .accessibilityValue(L("articlePercentRead", ["percent": Int((progress * 100).rounded())]))
            .accessibilityIdentifier("article-progress")
    }
}

struct ReaderScrollMetrics: Equatable {
    var offset: CGFloat
    var maxOffset: CGFloat

    var progress: Double {
        guard maxOffset > 1 else { return 1 }
        return min(max(Double(offset / maxOffset), 0), 1)
    }
}

struct ArticleDetailView: View {
    var articleId: String? = nil
    var naddr: String? = nil
    init(articleId: String) { self.articleId = articleId }
    init(naddr: String) { self.naddr = naddr }

    @State private var model = ArticleDetailModel()
    @State private var cache = ProfileCache.shared
    @State private var store = ReadingProgressStore.shared
    @State private var copied = 0
    @State private var position = ScrollPosition(edge: .top)
    @State private var tracker = ReaderProgressTracker()
    @State private var showSettings = false
    @State private var showHighlights = false
    @State private var highlightDraft: HighlightDraft?
    @State private var scrollTarget: String?
    @Environment(\.scenePhase) private var scenePhase
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
        .onDisappear { store.persist() }
        .onChange(of: scenePhase) { if scenePhase != .active { store.persist() } }
        .sheet(item: $highlightDraft) { draft in
            HighlightComposerSheet(draft: draft) { text, comment in
                await model.publishHighlight(text: text, context: draft.passage, comment: comment)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showHighlights) {
            HighlightsSheet(highlights: model.highlights, isLoading: model.isLoadingHighlights) { highlight in
                if let index = model.blockIndex(for: highlight) { scrollTarget = "article-block-\(index)" }
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let article = model.article {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Label(L("readerSettings"), systemImage: "textformat.size")
                }
                .popover(isPresented: $showSettings) {
                    ReaderSettingsPopover().presentationCompactAdaptation(.popover)
                }
                .accessibilityIdentifier("article-reader-settings")
            }
            if let naddr = article.naddr {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: "nostr:\(naddr)") { Label(L("share"), systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("article-share")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showHighlights = true } label: {
                        Label(model.highlights.isEmpty ? L("highlightsTitle") : L("highlightsCount", ["count": model.highlights.count]), systemImage: "highlighter")
                    }
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

    private var highlighting: MarkdownHighlighting {
        MarkdownHighlighting(
            passages: model.highlights.map(\.content),
            onHighlight: { highlightDraft = HighlightDraft(passage: $0) },
            onShowHighlights: { showHighlights = true }
        )
    }

    private func content(_ article: Article) -> some View {
        ScrollViewReader { proxy in
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
                        if !model.highlights.isEmpty { highlightsButton }
                        Divider()
                        MarkdownView(blocks: model.blocks, anchorPrefix: "article-block")
                            .environment(\.markdownHighlighting, highlighting)
                            .accessibilityIdentifier("article-body")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 60)
                    .frame(maxWidth: Self.readableWidth + 40, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .readerTypography()
            }
            .scrollPosition($position)
            .onScrollGeometryChange(for: ReaderScrollMetrics.self) { geometry in
                ReaderScrollMetrics(
                    offset: geometry.contentOffset.y + geometry.contentInsets.top,
                    maxOffset: geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom - geometry.containerSize.height
                )
            } action: { _, newValue in
                tracker.metrics = newValue
                scrollChanged(article)
            }
            .overlay(alignment: .top) { ReaderProgressBar(tracker: tracker, minutes: article.readingMinutes) }
            .refreshable { await model.load(articleId: articleId, naddr: naddr) }
            .onChange(of: scrollTarget) {
                guard let target = scrollTarget else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(.smooth) { proxy.scrollTo(target, anchor: .top) }
                    scrollTarget = nil
                }
            }
        }
    }

    private func scrollChanged(_ article: Article) {
        guard !tracker.restoring else { return }
        let metrics = tracker.metrics
        if !tracker.restored {
            guard metrics.maxOffset != 0 else { return }
            tracker.restored = true
            if metrics.maxOffset > 0, let saved = store.progress(for: article),
               saved >= ReadingProgressStore.startThreshold, saved < ReadingProgressStore.finishThreshold {
                tracker.restoring = true
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    position.scrollTo(y: CGFloat(saved) * max(tracker.metrics.maxOffset, 0))
                    try? await Task.sleep(for: .milliseconds(200))
                    tracker.restoring = false
                }
                return
            }
        }
        store.record(article, progress: metrics.progress)
    }

    private var highlightsButton: some View {
        Button { showHighlights = true } label: {
            Label(L("highlightsCount", ["count": model.highlights.count]), systemImage: "highlighter")
                .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .accessibilityIdentifier("article-highlights")
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
