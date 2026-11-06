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
                    if model.contentWarningEnabled {
                        ComposeContentWarningField(reason: $model.contentWarningReason)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
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
                Button {
                    withAnimation(.snappy(duration: 0.25)) { model.contentWarningEnabled.toggle() }
                } label: {
                    Image(systemName: model.contentWarningEnabled ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(model.contentWarningEnabled ? AppColors.link : AppColors.textPrimary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel(L("feedContentWarning"))
                .accessibilityValue(model.contentWarningEnabled ? L("feedOn") : L("feedOff"))
                .accessibilityAddTraits(model.contentWarningEnabled ? .isSelected : [])
                .accessibilityIdentifier("compose-content-warning")
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
                    .noteSensitiveCover(note.id, reason: content.contentWarning, compact: true)
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
    @State private var editingAlt: ComposeAttachment?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.attachments) { attachment in
                    ComposeAttachmentTile(attachment: attachment, onRemove: { withAnimation(.snappy) { model.remove(attachment) } }, onRetry: { model.retry(attachment) }, onEditAlt: { editingAlt = attachment })
                }
            }
            .padding(.leading, 52)
        }
        .sheet(item: $editingAlt) { attachment in
            ComposeAltTextSheet(attachment: attachment)
        }
    }
}

struct ComposeContentWarningField: View {
    @Binding var reason: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(L("feedContentWarningReason"), text: $reason)
                .font(.body)
                .submitLabel(.done)
                .accessibilityLabel(L("feedContentWarning"))
                .accessibilityIdentifier("compose-content-warning-reason")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppColors.inputFill, in: .rect(cornerRadius: 14, style: .continuous))
        .padding(.leading, 52)
    }
}

struct ComposeAltTextSheet: View {
    @Bindable var attachment: ComposeAttachment
    @State private var draft = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let preview = attachment.preview {
                    Section {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 220)
                            .clipShape(.rect(cornerRadius: 12, style: .continuous))
                            .accessibilityHidden(true)
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    TextField(L("feedAltTextPlaceholder"), text: $draft, axis: .vertical)
                        .lineLimit(3...10)
                        .focused($focused)
                        .accessibilityIdentifier("compose-alt-text-field")
                } footer: {
                    Text(L("feedAltTextFooter"))
                }
            }
            .navigationTitle(L("feedAltTextTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("cancel"), systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("compose-alt-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("done"), systemImage: "checkmark") {
                        attachment.altText = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                    .foregroundStyle(AppColors.background)
                    .accessibilityIdentifier("compose-alt-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            draft = attachment.altText
            focused = true
        }
    }
}

struct ComposeAttachmentTile: View {
    @Bindable var attachment: ComposeAttachment
    let onRemove: () -> Void
    let onRetry: () -> Void
    let onEditAlt: () -> Void

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
        .overlay(alignment: .bottomLeading) {
            if !attachment.isVideo {
                Button(action: onEditAlt) {
                    HStack(spacing: 3) {
                        if attachment.trimmedAlt != nil {
                            Image(systemName: "checkmark").font(.caption2.weight(.semibold))
                        }
                        Text(L("feedAltButton")).font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(6)
                .accessibilityLabel(attachment.trimmedAlt == nil ? L("feedAddAltText") : L("feedAltTextTitle"))
                .accessibilityValue(attachment.trimmedAlt ?? "")
                .accessibilityIdentifier("compose-attachment-alt")
            }
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
