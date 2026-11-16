import SwiftUI

extension Router {
    /// Opens the article editor for a new article, a saved draft, or one of your published articles.
    func writeArticle(_ draft: ArticleDraft = ArticleDraft()) {
        guard ReadOnlyGate.check() else { return }
        sheet = .articleEditor(draft)
    }

    func editArticle(_ article: Article) {
        writeArticle(ArticleDraftStore.shared.draft(editing: article.dTag) ?? ArticleDraft(article: article))
    }
}

struct ArticleDraftsView: View {
    @State private var store = ArticleDraftStore.shared
    @State private var pendingDelete: ArticleDraft?

    var body: some View {
        let drafts = store.all()
        List {
            ForEach(drafts) { draft in
                Button { Router.shared.writeArticle(draft) } label: { row(draft) }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(L("delete"), systemImage: "trash", role: .destructive) { pendingDelete = draft }
                    }
                    .contextMenu {
                        Button(L("delete"), systemImage: "trash", role: .destructive) { pendingDelete = draft }
                    }
                    .accessibilityIdentifier("article-draft-row")
            }
        }
        .listStyle(.plain)
        .overlay {
            if drafts.isEmpty {
                EmptyStateView(systemImage: "doc.text", title: L("articleNoDrafts"), message: L("articleNoDraftsMessage"), actionTitle: L("articleWriteNew")) {
                    Router.shared.writeArticle()
                }
                .accessibilityIdentifier("article-drafts-empty")
            }
        }
        .navigationTitle(L("articleDrafts"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Router.shared.writeArticle() } label: { Label(L("articleWriteNew"), systemImage: "square.and.pencil") }
                    .accessibilityIdentifier("article-drafts-new")
            }
        }
        .confirmationDialog(L("articleDeleteDraftTitle"), isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button(L("delete"), role: .destructive) {
                if let pendingDelete { store.delete(pendingDelete.id) }
                pendingDelete = nil
            }
        }
    }

    private func row(_ draft: ArticleDraft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(draft.displayTitle)
                .font(.headline)
                .lineLimit(2)
            let excerpt = (draft.summary.isEmpty ? draft.content : draft.summary).trimmingCharacters(in: .whitespacesAndNewlines)
            if !excerpt.isEmpty {
                Text(excerpt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                if draft.isEditingPublished {
                    Text(L("articleEditingPublished"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.inputFill, in: .capsule)
                }
                Text(L("articleDraftEdited", ["time": TimeFormat.relative(Int(draft.updatedAt.timeIntervalSince1970))]))
                Text("·")
                Text(L("exploreMinRead", ["count": max(1, draft.wordCount / 220)]))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Toolbar menu for starting an article or opening drafts.
struct ArticleWriteMenu: View {
    @State private var store = ArticleDraftStore.shared

    var body: some View {
        let count = store.all().count
        Menu {
            Button { Router.shared.writeArticle() } label: { Label(L("articleWriteNew"), systemImage: "square.and.pencil") }
                .accessibilityIdentifier("article-write-new")
            Button { Router.shared.push(.articleDrafts) } label: {
                Label(count > 0 ? L("articleDraftsCount", ["count": count]) : L("articleDrafts"), systemImage: "doc.text")
            }
            .accessibilityIdentifier("article-open-drafts")
        } label: {
            Label(L("articleWrite"), systemImage: "square.and.pencil")
        }
        .accessibilityIdentifier("article-write-menu")
    }
}
