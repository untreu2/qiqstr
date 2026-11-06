import SwiftUI

struct ThreadView: View {
    let noteId: String
    @State private var model: ThreadViewModel
    @State private var bus = DataBus.shared
    @State private var store = NoteInteractionStore.shared
    @State private var wot = WebOfTrustService.shared

    init(noteId: String) {
        self.noteId = noteId
        _model = State(initialValue: ThreadViewModel(noteId: noteId))
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(model.ancestors, id: \.id) { note in
                    NoteRowView(note: note, showsThreadContext: false, compact: true, showsConnector: true)
                        .threadRowStyle()
                        .listRowSeparator(.hidden)
                }
                if let focused = model.focused {
                    FocusedNoteView(note: focused, quoteCount: model.quoteCount)
                        .id("focused")
                        .threadRowStyle()
                        .listRowSeparator(.hidden)
                    ThreadReplyEntryButton(note: focused)
                        .threadRowStyle()
                        .listRowSeparator(.hidden)
                }
                replies
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .accessibilityIdentifier("thread-list")
            .refreshable { await model.refresh() }
            .overlay { overlay }
            .onChange(of: model.ancestors.count) { _, count in
                if count > 0 { proxy.scrollTo("focused", anchor: .top) }
            }
        }
        .navigationTitle(L("thread"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.start() }
        .task(id: bus.feedVersion) { await model.reloadLocal() }
        .onChange(of: store.deletedIds) { model.rebuild() }
        .onChange(of: wot.trustedCount) { model.rebuild() }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private var replies: some View {
        if model.focused != nil {
            if model.rows.isEmpty {
                Group {
                    if model.repliesSynced {
                        Text(L("noRepliesFound"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .threadRowStyle()
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("thread-no-replies")
            }
            ForEach(model.rows) { row in
                rowView(row)
                    .threadRowStyle()
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: NoteThreadRow) -> some View {
        switch row {
        case .reply(let note, let depth, let hasChildren):
            NoteRowView(note: note, showsThreadContext: false, compact: depth > 0)
                .padding(.leading, indent(depth))
                .overlay(alignment: .leading) { depthGuides(depth) }
                .noteSwipeActions(note)
                .listRowSeparator(hasChildren ? .hidden : .visible)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        case .moreReplies(let parentId, let hidden, let depth):
            Button { withAnimation(.snappy) { model.expand(parentId) } } label: {
                threadLink(L("moreReplies", ["count": hidden]), systemImage: "chevron.down")
            }
            .buttonStyle(.plain)
            .padding(.leading, indent(depth) + 16)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("thread-more-replies")
        case .continueThread(let id, let count, let depth):
            Button { Router.shared.push(.thread(id)) } label: {
                threadLink("\(L("viewMoreReplies")) (\(count))", systemImage: "arrow.turn.down.right")
            }
            .buttonStyle(.plain)
            .padding(.leading, indent(depth) + 16)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("thread-continue")
        case .loadMore(let remaining):
            Button { withAnimation(.snappy) { model.showMoreTopLevel() } } label: {
                Text("\(L("loadMore")) (\(remaining))")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(16)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("thread-load-more")
        case .hiddenReplies(let count):
            Button { withAnimation(.snappy) { model.revealHidden() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                    Text("\(L("feedRepliesHidden", ["count": count])) ·")
                    Text(L("feedSensitiveShow")).foregroundStyle(.tint)
                    Spacer()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("thread-hidden-replies")
        }
    }

    private func indent(_ depth: Int) -> CGFloat { CGFloat(min(depth, ThreadViewModel.maxDepth + 1)) * 24 }

    private func depthGuides(_ depth: Int) -> some View {
        ZStack(alignment: .leading) {
            ForEach(0..<max(depth, 0), id: \.self) { level in
                Rectangle()
                    .fill(AppColors.divider)
                    .frame(width: 1.5)
                    .offset(x: CGFloat(level) * 24 + 16 + (level == 0 ? 22 : 17))
            }
        }
        .frame(maxHeight: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }

    private func threadLink(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.footnote.weight(.semibold))
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
        }
        .foregroundStyle(.tint)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var overlay: some View {
        if model.focused == nil {
            if model.failed {
                EmptyStateView(systemImage: "exclamationmark.bubble", title: L("failedToLoadThread"), actionTitle: L("retryText")) {
                    Task { await model.refresh() }
                }
                .accessibilityIdentifier("thread-error")
            } else {
                LoadingView()
            }
        }
    }
}

private extension View {
    func threadRowStyle() -> some View {
        listRowInsets(EdgeInsets()).listRowBackground(AppColors.background)
    }
}

struct ThreadReplyEntryButton: View {
    let note: Note
    @State private var session = Session.shared

    var body: some View {
        Button { Router.shared.compose(.reply(note)) } label: {
            HStack(spacing: 10) {
                if let me = session.pubkey { ProfileAvatar(pubkey: me, size: 28) }
                Text(L("addAReply"))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "arrowshape.turn.up.left")
                    .foregroundStyle(.secondary)
            }
            .font(.body)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityIdentifier("thread-reply-entry")
    }
}

struct FocusedNoteView: View {
    let note: Note
    let quoteCount: Int
    @State private var cache = ProfileCache.shared
    @State private var store = NoteInteractionStore.shared
    @State private var actions = NoteActionHandler()

    var body: some View {
        let model = store.model(for: note)
        VStack(alignment: .leading, spacing: 12) {
            if note.isRepost, let reposter = note.repostedBy {
                NoteRepostHeader(pubkey: reposter, fallbackName: note.repostedByName)
            }
            Button { Router.shared.push(.profile(note.pubkey)) } label: {
                HStack(spacing: 12) {
                    ProfileAvatar(pubkey: note.pubkey, size: 48, fallbackURL: note.authorImage)
                    VStack(alignment: .leading, spacing: 2) {
                        NoteAuthorLine(note: note, name: name, nip05: nil, large: true)
                        if let nip05 = cache.profile(note.pubkey)?.nip05.nilIfEmpty ?? note.authorNip05 {
                            Text(nip05.hasPrefix("_@") ? String(nip05.dropFirst(2)) : nip05)
                                .lineLimit(1)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("thread-focused-author")
            if note.isReply, let target = replyTarget {
                NoteReplyContextLine(pubkey: target)
            }
            NoteContentView(note: note, font: note.content.count > 280 ? .body : .title3, selectable: true, expandedByDefault: true)
            NoteTranslateButton(note: note)
            Text(TimeFormat.full(note.createdAt))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            statsRow(model.counts)
            Divider()
            InteractionBarView(note: note, model: model, actions: actions)
            Divider()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .contextMenu {
            NoteMenuItems(note: note, actions: actions)
        } preview: {
            NoteContextPreview(note: note, authorName: name)
        }
        .noteActionDialogs(actions)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("thread-focused")
    }

    private var name: String {
        cache.profile(note.pubkey)?.bestName ?? note.authorName ?? Profile.shortNpub(note.pubkey)
    }

    private var replyTarget: String? {
        for tag in note.tags where tag.count > 4 && tag[0] == "e" && tag[3] == "reply" && tag[4].count == 64 { return tag[4] }
        return note.tags.first { $0.count > 1 && $0[0] == "p" && $0[1] != note.pubkey }?[1]
    }

    @ViewBuilder
    private func statsRow(_ counts: InteractionCounts) -> some View {
        let items: [(Int, String, Route)] = [
            (counts.reposts, L(counts.reposts == 1 ? "repost" : "reposts"), .noteStatistics(note.id)),
            (quoteCount, L("quotes"), .quotes(note.id)),
            (counts.reactions, L(counts.reactions == 1 ? "reaction" : "reactions"), .noteStatistics(note.id)),
            (counts.zapAmount, L("feedSats"), .noteStatistics(note.id)),
        ].filter { $0.0 > 0 }
        if !items.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { statButtons(items) }
                VStack(alignment: .leading, spacing: 6) { statButtons(items) }
            }
        }
    }

    private func statButtons(_ items: [(Int, String, Route)]) -> some View {
        ForEach(items, id: \.1) { item in
            Button { Router.shared.push(item.2) } label: {
                HStack(spacing: 4) {
                    Text(Sats.compact(item.0)).fontWeight(.semibold).monospacedDigit().foregroundStyle(.primary)
                    Text(item.1).foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("thread-stat-\(item.1)")
        }
    }
}
