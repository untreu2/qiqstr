import SwiftUI

struct ThreadView: View {
    let noteId: String
    @State private var model: ThreadViewModel
    @State private var bus = DataBus.shared
    @State private var store = NoteInteractionStore.shared

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
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private var replies: some View {
        if model.focused != nil {
            if model.rows.isEmpty {
                Group {
                    if model.repliesSynced {
                        Text(L("noRepliesFound"))
                            .font(.system(size: 15))
                            .foregroundStyle(AppColors.textSecondary)
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
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
            .padding(16)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("thread-load-more")
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
            Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
            Text(title).font(.system(size: 14, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(AppColors.accent)
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
                if let me = session.pubkey { ProfileAvatar(pubkey: me, size: 30) }
                Text(L("addAReply"))
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Image(systemName: "photo").foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
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
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill").font(.system(size: 12))
                                Text(nip05.hasPrefix("_@") ? String(nip05.dropFirst(2)) : nip05).lineLimit(1)
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("thread-focused-author")
            if note.isReply, let target = replyTarget {
                NoteReplyContextLine(pubkey: target)
            }
            NoteContentView(note: note, fontSize: 18, selectable: true, expandedByDefault: true)
            Text(TimeFormat.full(note.createdAt))
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
            statsRow(model.counts)
            Divider().overlay(AppColors.divider)
            InteractionBarView(note: note, model: model, actions: actions)
            Divider().overlay(AppColors.divider)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .contextMenu { NoteMenuItems(note: note, actions: actions) }
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
            (counts.reposts, L("reposts"), .noteStatistics(note.id)),
            (quoteCount, L("quotes"), .quotes(note.id)),
            (counts.reactions, L("reactions"), .noteStatistics(note.id)),
            (counts.zapAmount, L("feedSats"), .noteStatistics(note.id)),
        ].filter { $0.0 > 0 }
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(items, id: \.1) { item in
                        Button { Router.shared.push(item.2) } label: {
                            HStack(spacing: 4) {
                                Text(Sats.compact(item.0)).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(AppColors.textPrimary)
                                Text(item.1).font(.system(size: 15)).foregroundStyle(AppColors.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("thread-stat-\(item.1)")
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
