import PhotosUI
import SwiftUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = EditProfileViewModel()
    @State private var pictureItem: PhotosPickerItem?
    @State private var bannerItem: PhotosPickerItem?
    @State private var confirmDiscard = false
    @FocusState private var focus: ProfileField?

    var body: some View {
        Form {
            Section {
                mediaHeader
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                field(.picture, L("profileImage"), text: $model.draft.picture, prompt: "https://", keyboard: .URL, id: "edit-picture-url")
                field(.banner, L("banner"), text: $model.draft.banner, prompt: "https://", keyboard: .URL, id: "edit-banner-url")
            } header: {
                Text(L("profileImageLinks"))
            }
            Section {
                field(.displayName, L("profileDisplayName"), text: $model.draft.displayName, id: "edit-display-name")
                field(.name, L("username"), text: $model.draft.name, id: "edit-name")
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("bio")).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    TextField(L("profileAboutPlaceholder"), text: $model.draft.about, axis: .vertical)
                        .lineLimit(3...10)
                        .focused($focus, equals: .about)
                        .accessibilityIdentifier("edit-about")
                    errorText(.about)
                }
            } header: {
                Text(L("profile"))
            }
            Section {
                field(.nip05, L("nip05"), text: $model.draft.nip05, prompt: "name@example.com", keyboard: .emailAddress, id: "edit-nip05")
                field(.lud16, L("lightningAddress"), text: $model.draft.lud16, prompt: "name@wallet.com", keyboard: .emailAddress, id: "edit-lud16")
                field(.website, L("website"), text: $model.draft.website, prompt: "example.com", keyboard: .URL, id: "edit-website")
                field(.location, L("profileLocation"), text: $model.draft.location, capitalize: true, id: "edit-location")
            } header: {
                Text(L("profileDetails"))
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(model.isLoading)
        .overlay { if model.isLoading { LoadingView() } }
        .navigationTitle(L("editProfile"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .interactiveDismissDisabled(model.isDirty)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L("cancel")) {
                    if model.isDirty { confirmDiscard = true } else { dismiss() }
                }
                .accessibilityIdentifier("edit-profile-cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                if model.isSaving {
                    ProgressView()
                } else {
                    Button(L("save")) { save() }
                        .buttonStyle(.glassProminent)
                        .foregroundStyle(AppColors.background)
                        .disabled(!model.canSave)
                        .accessibilityIdentifier("edit-profile-save")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("done")) { focus = nil }
            }
        }
        .confirmationDialog(L("profileDiscardChanges"), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(L("profileDiscard"), role: .destructive) { dismiss() }
                .accessibilityIdentifier("edit-profile-discard")
            Button(L("profileKeepEditing"), role: .cancel) {}
        }
        .sensoryFeedback(.success, trigger: model.savedCount)
        .onChange(of: pictureItem) { _, item in
            guard let item else { return }
            Task {
                await model.upload(item, target: .picture)
                pictureItem = nil
            }
        }
        .onChange(of: bannerItem) { _, item in
            guard let item else { return }
            Task {
                await model.upload(item, target: .banner)
                bannerItem = nil
            }
        }
        .task { await model.load() }
        .accessibilityIdentifier("edit-profile-form")
    }

    private var mediaHeader: some View {
        let banner = model.draft.banner
        let picture = model.draft.picture
        let uploadingBanner = model.uploadingBanner
        let uploadingPicture = model.uploadingPicture
        return VStack(alignment: .leading, spacing: 0) {
            PhotosPicker(selection: $bannerItem, matching: .images) {
                ZStack {
                    Rectangle().fill(AppColors.tile)
                    if !banner.isEmpty {
                        RemoteImage(url: banner, maxPixel: 1400) { Rectangle().fill(AppColors.tile) }
                    }
                    Rectangle().fill(.black.opacity(0.25))
                    MediaBadge(uploading: uploadingBanner)
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isUploading)
            .accessibilityLabel(L("banner"))
            .accessibilityIdentifier("edit-banner-picker")
            HStack(alignment: .bottom) {
                PhotosPicker(selection: $pictureItem, matching: .images) {
                    ZStack {
                        AvatarView(url: picture.nilIfEmpty, size: 88)
                        Circle().fill(.black.opacity(0.25)).frame(width: 88, height: 88)
                        MediaBadge(uploading: uploadingPicture)
                    }
                    .padding(4)
                    .background(AppColors.background, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(model.isUploading)
                .accessibilityLabel(L("profileImage"))
                .accessibilityIdentifier("edit-picture-picker")
                Spacer()
                if !model.draft.picture.isEmpty || !model.draft.banner.isEmpty {
                    Menu {
                        if !model.draft.picture.isEmpty {
                            Button(role: .destructive) { model.draft.picture = "" } label: { Label(L("profileRemoveImage"), systemImage: "person.crop.circle.badge.minus") }
                        }
                        if !model.draft.banner.isEmpty {
                            Button(role: .destructive) { model.draft.banner = "" } label: { Label(L("profileRemoveBanner"), systemImage: "photo.badge.minus") }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("edit-media-menu")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, -48)
        }
        .padding(.bottom, 4)
    }

    private func field(_ key: ProfileField, _ label: String, text: Binding<String>, prompt: String? = nil, keyboard: UIKeyboardType = .default, capitalize: Bool = false, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            TextField(prompt ?? label, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalize ? .words : .never)
                .autocorrectionDisabled(!capitalize)
                .focused($focus, equals: key)
                .submitLabel(.next)
                .accessibilityIdentifier(id)
            errorText(key)
        }
    }

    @ViewBuilder
    private func errorText(_ key: ProfileField) -> some View {
        if let message = model.errors[key] {
            Text(message).font(.caption).foregroundStyle(.red)
        }
    }

    private func save() {
        focus = nil
        Task {
            if await model.save() { dismiss() }
        }
    }
}

private struct MediaBadge: View {
    let uploading: Bool

    var body: some View {
        Group {
            if uploading {
                ProgressView().tint(.white)
            } else {
                Image(systemName: "camera.fill").font(.body.weight(.semibold)).foregroundStyle(.primary)
            }
        }
        .frame(width: 40, height: 40)
        .glassEffect(.regular, in: .circle)
    }
}
