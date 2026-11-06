import PhotosUI
import SwiftUI

struct ComposeView: View {
    let context: ComposeContext
    @State private var model: ComposeViewModel
    @State private var session = Session.shared
    @State private var confirmDiscard = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(context: ComposeContext) {
        self.context = context
        _model = State(initialValue: ComposeViewModel(context: context))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if case .reply(let note) = context {
                        ReplyTargetPreview(note: note)
                    }
                    editor
                    if !model.attachments.isEmpty {
                        ComposeAttachmentStrip(model: model)
                    }
                    if case .quote(let note) = context {
                        NoteQuoteCard(noteId: note.id, preloaded: note)
                            .allowsHitTesting(false)
                            .padding(.leading, 52)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("cancel"), systemImage: "xmark") {
                        if model.hasContent { confirmDiscard = true } else { dismiss() }
                    }
                    .accessibilityIdentifier("compose-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { if await model.post() { dismiss() } }
                    } label: {
                        if model.isPosting {
                            ProgressView()
                        } else {
                            Text(context == .newNote ? L("feedPost") : (model.title))
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .foregroundStyle(AppColors.background)
                    .disabled(!model.canPost)
                    .accessibilityIdentifier("compose-post")
                }
            }
            .confirmationDialog(L("feedDiscardDraft"), isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button(L("feedDiscard"), role: .destructive) { dismiss() }
                    .accessibilityIdentifier("compose-discard")
                Button(L("feedKeepEditing"), role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(model.hasContent)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: model.didPost)
        .onChange(of: model.pickerItems) { Task { await model.handlePicked() } }
        .onAppear { focused = true }
    }

    private var editor: some View {
        HStack(alignment: .top, spacing: 12) {
            if let me = session.pubkey { ProfileAvatar(pubkey: me, size: 40) }
            ZStack(alignment: .topLeading) {
                if model.text.isEmpty {
                    Text(model.placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $model.text, selection: $model.selection)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .frame(minHeight: 140)
                    .focused($focused)
                    .accessibilityLabel(L("composeYourNote"))
                    .accessibilityIdentifier("compose-text")
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if !model.suggestions.isEmpty {
                ComposeMentionSuggestions(profiles: model.suggestions) { model.insertMention($0) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 12) {
                PhotosPicker(selection: $model.pickerItems, maxSelectionCount: max(1, ComposeViewModel.maxAttachments - model.attachments.count), matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
                    Image(systemName: "photo.on.rectangle.angled")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .disabled(model.attachments.count >= ComposeViewModel.maxAttachments)
                .accessibilityLabel(L("addMediaText"))
                .accessibilityIdentifier("compose-media")
                if model.isUploading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(L("uploadingDotDotDot")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(model.text.count)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("compose-count")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .animation(.snappy(duration: 0.2), value: model.suggestions.isEmpty)
    }
}

struct ReplyTargetPreview: View {
    let note: Note
    @State private var cache = ProfileCache.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                ProfileAvatar(pubkey: note.pubkey, size: 40, fallbackURL: note.authorImage)
                Rectangle().fill(AppColors.divider).frame(width: 2).frame(maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: 4) {
                NoteAuthorLine(note: note, name: cache.profile(note.pubkey)?.bestName ?? note.authorName ?? Profile.shortNpub(note.pubkey), nip05: note.authorNip05)
                let content = NoteContentCache.content(for: note)
                Text(content.attributed(content.truncatedSegments ?? content.segments, font: .subheadline, cache: cache))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                HStack(spacing: 4) {
                    Text(L("replyingTo"))
                    Text("@\(cache.profile(note.pubkey)?.bestName ?? note.authorName ?? Profile.shortNpub(note.pubkey))")
                        .foregroundStyle(AppColors.link)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("compose-reply-target")
    }
}

struct ComposeAttachmentStrip: View {
    let model: ComposeViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.attachments) { attachment in
                    ComposeAttachmentTile(attachment: attachment, onRemove: { withAnimation(.snappy) { model.remove(attachment) } }, onRetry: { model.retry(attachment) })
                }
            }
            .padding(.leading, 52)
        }
    }
}

struct ComposeAttachmentTile: View {
    @Bindable var attachment: ComposeAttachment
    let onRemove: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Group {
                if let preview = attachment.preview {
                    Image(uiImage: preview).resizable().scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(AppColors.tile)
                        Image(systemName: attachment.isVideo ? "video.fill" : "photo").font(.title2).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 110, height: 110)
            .clipped()
            switch attachment.status {
            case .uploading:
                ZStack {
                    Color.black.opacity(0.35)
                    ProgressView().tint(.white)
                }
            case .failed:
                Button(action: onRetry) {
                    ZStack {
                        Color.black.opacity(0.45)
                        Image(systemName: "arrow.clockwise").font(.title3.weight(.semibold)).foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("retry"))
                .accessibilityIdentifier("compose-attachment-retry")
            case .uploaded:
                if attachment.isVideo {
                    Image(systemName: "play.circle.fill").font(.title).foregroundStyle(.white).shadow(radius: 4)
                }
            }
        }
        .frame(width: 110, height: 110)
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .padding(6)
            .accessibilityLabel(L("removeThisMediaFile"))
            .accessibilityIdentifier("compose-attachment-remove")
        }
    }
}

struct ComposeMentionSuggestions: View {
    let profiles: [Profile]
    let onSelect: (Profile) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(profiles) { profile in
                        Button { onSelect(profile) } label: {
                            HStack(spacing: 8) {
                                AvatarView(url: profile.picture.nilIfEmpty, size: 28)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(profile.bestName).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    if !profile.nip05.isEmpty {
                                        Text(profile.nip05).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.leading, 6)
                            .padding(.trailing, 12)
                            .padding(.vertical, 6)
                            .frame(minHeight: 42)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .accessibilityLabel("\(L("mention")) \(profile.bestName)")
                        .accessibilityIdentifier("compose-mention-suggestion")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .accessibilityIdentifier("compose-mentions")
    }
}
