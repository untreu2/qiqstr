import SwiftUI

struct ProfileView: View {
    let pubkey: String
    @State private var model: ProfileViewModel
    @State private var bus = DataBus.shared
    @State private var pins = PinnedNotesService.shared
    @State private var mutes = MuteService.shared
    @State private var identityBottom: CGFloat = .infinity
    @State private var viewerImage: ViewableImage?
    @State private var mediaSelection: ProfileMediaSelection?
    @State private var confirmMute = false
    @State private var showReport = false

    init(pubkey: String) {
        let hex = Nip19.pubkeyHex(from: pubkey) ?? pubkey
        self.pubkey = hex
        _model = State(initialValue: ProfileViewModel(pubkey: hex))
    }

    var body: some View {
        Group {
            if model.isValidPubkey {
                content
            } else {
                EmptyStateView(systemImage: "person.crop.circle.badge.exclamationmark", title: L("errorLoadingUserProfile"))
            }
        }
        .background(AppColors.background)
        .navigationTitle(model.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewerImage) { ProfileImageViewer(url: $0.url) }
        .fullScreenCover(item: $mediaSelection) { selection in
            ProfileMediaPager(entries: model.media, startIndex: selection.index)
        }
    }

    private var content: some View {
        GeometryReader { outer in
            let topInset = outer.safeAreaInsets.top
            let bannerHeight = min(max(outer.size.width * 0.3, 110), 160)
            let titleVisible = identityBottom <= topInset
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ProfileHeaderView(model: model, topInset: topInset, bannerHeight: bannerHeight) { url in
                        viewerImage = ViewableImage(url: url)
                    } onIdentityPositionChange: { identityBottom = $0 }
                    tabPicker
                    tabContent
                    footer
                }
                .padding(.bottom, 24)
            }
            .coordinateSpace(name: "profile-viewport")
            .ignoresSafeArea(edges: .top)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .refreshable { await model.refresh() }
            .accessibilityIdentifier("profile-scroll")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        AvatarView(url: model.profile.picture.nilIfEmpty, size: 26)
                        Text(model.displayName).font(.body.weight(.semibold)).lineLimit(1)
                    }
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible ? 0 : 8)
                    .animation(.smooth(duration: 0.25), value: titleVisible)
                    .accessibilityHidden(!titleVisible)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileMenu(model: model, confirmMute: $confirmMute, showReport: $showReport)
                }
            }
            .toolbarBackgroundVisibility(titleVisible ? .visible : .hidden, for: .navigationBar)
            .animation(.smooth(duration: 0.25), value: titleVisible)
        }
        .modifier(ProfileModerationModifier(model: model, confirmMute: $confirmMute, showReport: $showReport))
        .sensoryFeedback(.selection, trigger: model.tab)
        .task { await model.start() }
        .task(id: bus.feedVersion) {
            guard model.hasLoadedNotes else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await model.reloadNotes()
        }
        .task(id: bus.profileVersion) {
            guard model.hasLoadedNotes else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await model.reloadProfile()
        }
        .task(id: bus.interactionVersion) {
            guard model.hasLoadedLikes else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await model.reloadLikes()
        }
        .task(id: pins.version) {
            guard model.hasLoadedNotes else { return }
            await model.pinnedChanged()
        }
        .task(id: mutes.mutedPubkeys.count) {
            guard model.hasLoadedNotes else { return }
            await model.reloadNotes()
        }
    }

    private var tabPicker: some View {
        Picker(L("notes"), selection: $model.tab) {
            ForEach(ProfileTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .accessibilityIdentifier("profile-tabs")
    }

    @ViewBuilder
    private var tabContent: some View {
        switch model.tab {
        case .notes:
            if !model.pinned.isEmpty {
                ForEach(model.pinned) { note in
                    PinnedNoteRow(note: note, isMine: model.isMe)
                }
            }
            noteRows(model.visibleNotes, empty: L("noNotesFromThisUser"), systemImage: "text.bubble", id: "profile-notes")
        case .replies:
            noteRows(model.replies, empty: L("noRepliesFound"), systemImage: "arrowshape.turn.up.left", id: "profile-replies")
        case .photos:
            photoGrid
        case .likes:
            if model.likes.isEmpty, !model.hasLoadedLikes {
                loadingRow
            } else {
                noteRows(model.likes, empty: L("profileNoLikes"), systemImage: "heart", id: "profile-likes")
            }
        }
    }

    @ViewBuilder
    private func noteRows(_ notes: [Note], empty: String, systemImage: String, id: String) -> some View {
        if notes.isEmpty {
            if model.isSyncingNotes || !model.hasLoadedNotes {
                loadingRow
            } else if model.tab != .notes || model.pinned.isEmpty {
                EmptyStateView(systemImage: systemImage, title: empty)
                    .padding(.top, 12)
                    .accessibilityIdentifier("\(id)-empty")
            }
        } else {
            ForEach(notes, id: \.listId) { note in
                VStack(spacing: 0) {
                    NoteRowView(note: note)
                    Divider().overlay(AppColors.divider)
                }
                .accessibilityIdentifier("\(id)-row")
            }
        }
    }

    @ViewBuilder
    private var photoGrid: some View {
        if model.media.isEmpty {
            if model.isSyncingNotes || !model.hasLoadedNotes {
                loadingRow
            } else {
                EmptyStateView(systemImage: "photo.on.rectangle", title: L("profileNoMedia"))
                    .padding(.top, 12)
                    .accessibilityIdentifier("profile-photos-empty")
            }
        } else {
            ProfileMediaGrid(entries: model.media) { mediaSelection = ProfileMediaSelection(index: $0) }
        }
    }

    @ViewBuilder
    private var footer: some View {
        let hasItems: Bool = {
            switch model.tab {
            case .notes: !model.notes.isEmpty
            case .replies: !model.replies.isEmpty
            case .photos: !model.media.isEmpty
            case .likes: !model.likes.isEmpty
            }
        }()
        if hasItems && model.canLoadMoreCurrent {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(24)
                .onAppear { Task { await model.loadMore() } }
                .id("\(model.tab.rawValue)-\(model.loadMoreCount)")
                .accessibilityIdentifier("profile-load-more")
        }
    }

    private var loadingRow: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
    }
}

private struct PinnedNoteRow: View {
    let note: Note
    let isMine: Bool
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "pin.fill").font(.caption2.weight(.semibold))
                Text(L("pinnedNotes")).font(.footnote.weight(.semibold))
                Spacer()
                if isMine {
                    Menu {
                        Button(role: .destructive) { Task { await unpin() } } label: {
                            Label(L("unpinNote"), systemImage: "pin.slash")
                        }
                        .accessibilityIdentifier("unpin-note")
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 32, height: 24)
                            .contentShape(Rectangle())
                    }
                    .disabled(working)
                    .accessibilityLabel(L("unpinNote"))
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            NoteRowView(note: note)
            Divider().overlay(AppColors.divider)
        }
        .accessibilityIdentifier("profile-pinned-row")
    }

    private func unpin() async {
        working = true
        defer { working = false }
        do {
            try await PinnedNotesService.shared.toggle(note.id)
            ToastCenter.shared.show(L("noteUnpinned"), style: .success)
        } catch {
            ToastCenter.shared.error(error)
        }
    }
}
