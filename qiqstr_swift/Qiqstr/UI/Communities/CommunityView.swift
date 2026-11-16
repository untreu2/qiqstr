import PhotosUI
import QiqstrCore
import SwiftUI

@MainActor
@Observable
final class CommunityModel {
    let coordinate: String
    private(set) var community: Community?
    private(set) var posts: [Note] = []
    private(set) var loaded = false
    private(set) var missing = false
    private(set) var isUpdatingMembership = false

    init(coordinate: String) {
        self.coordinate = coordinate
    }

    var isJoined: Bool { community.map(CommunityService.shared.isJoined) ?? false }

    func start() async {
        if community == nil {
            community = await CommunityService.shared.community(coordinate: coordinate)
            if let community { await ProfileCache.shared.load(community.team) }
        }
        guard let community else { missing = true; loaded = true; return }
        posts = await CommunityService.shared.posts(in: community)
        loaded = true
    }

    func toggleMembership() async {
        guard let community, ReadOnlyGate.check(), !isUpdatingMembership else { return }
        isUpdatingMembership = true
        defer { isUpdatingMembership = false }
        do {
            if isJoined { try await CommunityService.shared.leave(community) } else { try await CommunityService.shared.join(community) }
            ToastCenter.shared.show(L(isJoined ? "communityJoinedToast" : "communityLeftToast"), style: .success)
        } catch {
            ToastCenter.shared.show(coreMessage(error), style: .error)
        }
    }
}

struct CommunityView: View {
    @State private var model: CommunityModel
    @State private var bus = DataBus.shared
    @State private var showsComposer = false
    @State private var showsRules = false

    init(coordinate: String) {
        _model = State(initialValue: CommunityModel(coordinate: coordinate))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let community = model.community {
                    header(community)
                    Divider().overlay(AppColors.divider)
                }
                if model.missing {
                    EmptyStateView(systemImage: "person.3", title: L("communityNotFound"))
                        .padding(.top, 48)
                } else if !model.loaded {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 48)
                } else if model.posts.isEmpty {
                    EmptyStateView(systemImage: "text.bubble", title: L("communityNoPosts"))
                        .padding(.top, 24)
                        .accessibilityIdentifier("community-posts-empty")
                } else {
                    ForEach(model.posts, id: \.listId) { note in
                        VStack(spacing: 0) {
                            NoteRowView(note: note)
                            Divider().overlay(AppColors.divider)
                        }
                        .accessibilityIdentifier("community-post-row")
                    }
                }
            }
        }
        .background(AppColors.background)
        .navigationTitle(model.community?.displayName ?? L("communityCommunity"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.start() }
        .toolbar {
            if let community = model.community {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard ReadOnlyGate.check() else { return }
                        showsComposer = true
                    } label: { Label(L("communityNewPost"), systemImage: "square.and.pencil") }
                    .accessibilityIdentifier("community-new-post")
                }
                if let naddr = community.naddr {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: "nostr:\(naddr)") { Label(L("share"), systemImage: "square.and.arrow.up") }
                    }
                }
            }
        }
        .sheet(isPresented: $showsComposer) {
            if let community = model.community {
                CommunityPostSheet(community: community) { Task { await model.start() } }
            }
        }
        .sheet(isPresented: $showsRules) {
            if let community = model.community {
                NavigationStack {
                    ScrollView { Text(community.rules).padding(20).frame(maxWidth: .infinity, alignment: .leading) }
                        .navigationTitle(L("communityRules"))
                        .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
            }
        }
        .task { await model.start() }
        .task(id: bus.feedVersion) {
            guard model.loaded, !model.missing else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await model.start()
        }
    }

    private func header(_ community: Community) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                CommunityIcon(picture: community.image, systemImage: "person.3", size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(community.displayName)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                    Text(L("communityModerators", ["count": community.team.count]))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if !community.summary.isEmpty {
                Text(community.summary)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: -8) {
                    ForEach(community.team.prefix(12), id: \.self) { pubkey in
                        Button { Router.shared.push(.profile(pubkey)) } label: {
                            ProfileAvatar(pubkey: pubkey, size: 30)
                                .overlay(Circle().stroke(AppColors.background, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 10) {
                Button { Task { await model.toggleMembership() } } label: {
                    Text(model.isJoined ? L("communityLeave") : L("communityJoin"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isJoined ? AppColors.inputFill : AppColors.textPrimary)
                .foregroundStyle(model.isJoined ? AppColors.textPrimary : AppColors.background)
                .disabled(model.isUpdatingMembership)
                .accessibilityIdentifier("community-membership")
                if !community.rules.isEmpty {
                    Button { showsRules = true } label: {
                        Label(L("communityRules"), systemImage: "list.bullet.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.textPrimary)
                }
            }
            .controlSize(.large)
        }
        .padding(16)
    }
}

struct CommunityPostSheet: View {
    let community: Community
    let onPosted: () -> Void
    @State private var text = ""
    @State private var images: [String] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var isPosting = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var canPost: Bool {
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty) && !isUploading && !isPosting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("communityPostPlaceholder"), text: $text, axis: .vertical)
                        .lineLimit(6...16)
                        .focused($focused)
                        .accessibilityIdentifier("community-post-text")
                } footer: {
                    Text(L("communityPostFooter", ["name": community.displayName]))
                }
                Section {
                    ForEach(images, id: \.self) { url in
                        HStack {
                            RemoteImage(url: url, maxPixel: 200) { Rectangle().fill(.quaternary) }
                                .frame(width: 56, height: 56)
                                .clipShape(.rect(cornerRadius: 8))
                            Spacer()
                            Button(L("delete"), systemImage: "trash", role: .destructive) { images.removeAll { $0 == url } }
                                .labelStyle(.iconOnly)
                        }
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        HStack {
                            Label(L("articleInsertImage"), systemImage: "photo")
                            Spacer()
                            if isUploading { ProgressView() }
                        }
                    }
                    .disabled(isUploading || images.count >= 4)
                }
            }
            .navigationTitle(L("communityNewPost"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("cancel")) { dismiss() }.disabled(isPosting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPosting {
                        ProgressView()
                    } else {
                        Button(L("communityPost")) { post() }
                            .fontWeight(.semibold)
                            .disabled(!canPost)
                            .accessibilityIdentifier("community-post-send")
                    }
                }
            }
            .onAppear { focused = true }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                pickerItem = nil
                Task { await upload(item) }
            }
        }
        .interactiveDismissDisabled(isPosting || !text.isEmpty)
    }

    private func upload(_ item: PhotosPickerItem) async {
        isUploading = true
        defer { isUploading = false }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else { throw CoreError(L("errorSelectingMedia")) }
            let type = item.supportedContentTypes.first { $0.conforms(to: .image) }
            let (data, mime) = await Task.detached(priority: .userInitiated) { () -> (Data, String) in
                if type?.conforms(to: .gif) == true { return (raw, "image/gif") }
                guard let image = ImagePipeline.downsample(raw, maxPixel: 2048), let jpeg = image.jpegData(compressionQuality: 0.88) else {
                    return (raw, type?.preferredMIMEType ?? "image/jpeg")
                }
                return (jpeg, "image/jpeg")
            }.value
            let url = try await MediaUploadService.shared.upload(data: data, mimeType: mime)
            if !url.isEmpty { images.append(url) }
        } catch {
            ToastCenter.shared.show(L("uploadFailed", ["message": coreMessage(error)]), style: .error)
        }
    }

    private func post() {
        guard canPost else { return }
        isPosting = true
        Task {
            defer { isPosting = false }
            do {
                try await CommunityService.shared.post(text, imageURLs: images, to: community)
                ToastCenter.shared.show(L("communityPosted"), style: .success)
                onPosted()
                dismiss()
            } catch {
                ToastCenter.shared.show(coreMessage(error), style: .error)
            }
        }
    }
}
