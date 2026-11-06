import SwiftUI

struct ProfileView: View {
    let pubkey: String
    @State private var model: ProfileViewModel
    @State private var bus = DataBus.shared
    @State private var pins = PinnedNotesService.shared
    @State private var mutes = MuteService.shared
    @State private var scrollOffset: CGFloat = 0
    @State private var viewerImage: ViewableImage?
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
    }

    private var content: some View {
        GeometryReader { outer in
            let topInset = outer.safeAreaInsets.top
            let bannerHeight = min(max(outer.size.width * 0.35, 120), 200)
            let titleVisible = scrollOffset > bannerHeight + 70
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ProfileHeaderView(model: model, topInset: topInset, bannerHeight: bannerHeight) { url in
                        viewerImage = ViewableImage(url: url)
                    }
                    tabPicker
                    tabContent
                    footer
                }
                .padding(.bottom, 24)
            }
            .ignoresSafeArea(edges: .top)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, value in
                scrollOffset = value
            }
            .refreshable { await model.refresh() }
            .accessibilityIdentifier("profile-scroll")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        AvatarView(url: model.profile.picture.nilIfEmpty, size: 26)
                        Text(model.displayName).font(.system(size: 16, weight: .semibold)).lineLimit(1)
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
        let photos = model.photos
        if photos.isEmpty {
            if model.isSyncingNotes || !model.hasLoadedNotes {
                loadingRow
            } else {
                EmptyStateView(systemImage: "photo.on.rectangle", title: L("noPhotosYet"))
                    .padding(.top, 12)
                    .accessibilityIdentifier("profile-photos-empty")
            }
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                ForEach(photos) { photo in
                    PhotoTile(photo: photo) { viewerImage = ViewableImage(url: photo.url) }
                }
            }
            .padding(.horizontal, 2)
            .accessibilityIdentifier("profile-photos")
        }
    }

    @ViewBuilder
    private var footer: some View {
        let hasItems: Bool = {
            switch model.tab {
            case .notes: !model.notes.isEmpty
            case .replies: !model.replies.isEmpty
            case .photos: !model.photos.isEmpty
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
                Image(systemName: "pin.fill").font(.system(size: 11, weight: .semibold))
                Text(L("pinnedNotes")).font(.system(size: 13, weight: .semibold))
                Spacer()
                if isMine {
                    Menu {
                        Button(role: .destructive) { Task { await unpin() } } label: {
                            Label(L("unpinNote"), systemImage: "pin.slash")
                        }
                        .accessibilityIdentifier("unpin-note")
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 32, height: 24)
                            .contentShape(Rectangle())
                    }
                    .disabled(working)
                    .accessibilityLabel(L("unpinNote"))
                }
            }
            .foregroundStyle(AppColors.textSecondary)
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

private struct PhotoTile: View {
    let photo: PhotoEntry
    var onView: () -> Void

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                RemoteImage(url: photo.url, maxPixel: 500) {
                    Rectangle().fill(AppColors.tile)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { Router.shared.push(.thread(photo.noteId)) }
            .contextMenu {
                Button(action: onView) { Label(L("profileViewImage"), systemImage: "arrow.up.left.and.arrow.down.right") }
                Button { Router.shared.push(.thread(photo.noteId)) } label: { Label(L("profileOpenNote"), systemImage: "text.bubble") }
            }
            .accessibilityIdentifier("profile-photo-tile")
    }
}
