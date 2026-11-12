import PhotosUI
import QiqstrCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class OnboardingProfileViewModel {
    enum Field: Hashable { case name, about, picture, lud16, website }

    var name = ""
    var about = ""
    var picture = ""
    var banner = ""
    var lud16 = ""
    var website = ""
    var isUploadingPicture = false
    var isUploadingBanner = false
    var isSaving = false
    var showErrors = false
    var savedCount = 0
    var failureCount = 0

    var isBusy: Bool { isSaving || isUploadingPicture || isUploadingBanner }

    func error(for field: Field) -> String? {
        switch field {
        case .name:
            return name.authTrimmed.count > 50 ? L("usernameTooLong") : nil
        case .about:
            return about.authTrimmed.count > 300 ? L("bioTooLong") : nil
        case .picture:
            let value = picture.authTrimmed
            guard !value.isEmpty else { return nil }
            return URL(string: value)?.scheme?.hasPrefix("http") == true ? nil : L("pleaseEnterValidWebsiteUrl")
        case .lud16:
            let value = lud16.authTrimmed
            guard !value.isEmpty else { return nil }
            let parts = value.split(separator: "@", omittingEmptySubsequences: false)
            return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty ? nil : L("invalidLightningAddress")
        case .website:
            let value = website.authTrimmed
            guard !value.isEmpty else { return nil }
            return value.contains(".") && !value.contains(" ") ? nil : L("pleaseEnterValidWebsiteUrl")
        }
    }

    var isValid: Bool { [Field.name, .about, .picture, .lud16, .website].allSatisfy { error(for: $0) == nil } }

    func upload(_ item: PhotosPickerItem, isPicture: Bool) async {
        if isPicture { isUploadingPicture = true } else { isUploadingBanner = true }
        defer { if isPicture { isUploadingPicture = false } else { isUploadingBanner = false } }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else { return }
            let (data, mime) = Self.prepare(raw, type: item.supportedContentTypes.first)
            let url = try await MediaUploadService.shared.upload(data: data, mimeType: mime)
            guard !url.isEmpty else { throw CoreError(L("authUploadNoUrl")) }
            if isPicture { picture = url } else { banner = url }
            ToastCenter.shared.show(L(isPicture ? "profileImageUploadedSuccessfully" : "bannerUploadedSuccessfully"), style: .success)
        } catch {
            ToastCenter.shared.show(L("uploadFailed", ["message": coreMessage(error)]), style: .error)
        }
    }

    func save() async -> Bool {
        showErrors = true
        guard isValid, !isBusy else {
            failureCount += 1
            return false
        }
        guard let me = Session.shared.pubkey, let key = Session.shared.privateKey else {
            ToastCenter.shared.show(L("privateKeyNotFound"), style: .error)
            return false
        }
        isSaving = true
        defer { isSaving = false }
        let profile = Profile(
            pubkey: me,
            name: name.authTrimmed,
            about: about.authTrimmed,
            picture: picture.authTrimmed,
            banner: banner.authTrimmed,
            lud16: lud16.authTrimmed,
            website: website.authTrimmed
        )
        do {
            let event = try createProfileEvent(profileJson: profile.metadataJSON, privateKeyHex: key)
            try await SyncService.shared.publish(event)
            ProfileCache.shared.set(profile)
            DataBus.shared.profileChanged()
            savedCount += 1
            return true
        } catch {
            failureCount += 1
            ToastCenter.shared.error(error)
            return false
        }
    }

    private static func prepare(_ data: Data, type: UTType?) -> (Data, String) {
        if type?.conforms(to: .gif) == true { return (data, "image/gif") }
        if let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) { return (jpeg, "image/jpeg") }
        return (data, type?.preferredMIMEType ?? "image/jpeg")
    }
}

private extension String {
    var authTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct OnboardingProfileView: View {
    let onDone: () -> Void

    @State private var model = OnboardingProfileViewModel()
    @State private var pictureItem: PhotosPickerItem?
    @State private var bannerItem: PhotosPickerItem?
    @FocusState private var focus: OnboardingProfileViewModel.Field?

    var body: some View {
        Form {
            Section {
                AuthHeader(title: L("setUpProfile"), subtitle: L("profileSetupSubtitle"))
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 4))
            Section {
                media
            }
            .listRowInsets(EdgeInsets())
            Section(L("profile")) {
                field(.name, placeholder: L("username"), text: $model.name, identifier: "onboarding-name", autocapitalize: true)
                field(.about, placeholder: L("bio"), text: $model.about, identifier: "onboarding-about", axis: .vertical, autocapitalize: true)
            }
            .disabled(model.isSaving)
            Section(L("details")) {
                field(.picture, placeholder: L("authPictureUrlOptional"), text: $model.picture, identifier: "onboarding-picture-url", keyboard: .URL)
                field(.lud16, placeholder: L("lightningAddressOptional"), text: $model.lud16, identifier: "onboarding-lud16", keyboard: .emailAddress)
                field(.website, placeholder: L("websiteOptional"), text: $model.website, identifier: "onboarding-website", keyboard: .URL)
            }
            .disabled(model.isSaving)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColors.background)
        .safeAreaInset(edge: .bottom) {
            if focus == nil {
                PrimaryButton(title: L("continueButton"), isLoading: model.isSaving, isEnabled: !model.isUploadingPicture && !model.isUploadingBanner) {
                    Task { if await model.save() { onDone() } }
                }
                .accessibilityIdentifier("onboarding-profile-continue")
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(AppColors.background)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) { OnboardingStepIndicator(current: 2) }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("done")) { focus = nil }
                    .accessibilityIdentifier("onboarding-keyboard-done")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pictureItem) { _, item in
            guard let item else { return }
            pictureItem = nil
            Task { await model.upload(item, isPicture: true) }
        }
        .onChange(of: bannerItem) { _, item in
            guard let item else { return }
            bannerItem = nil
            Task { await model.upload(item, isPicture: false) }
        }
        .sensoryFeedback(.success, trigger: model.savedCount)
        .sensoryFeedback(.error, trigger: model.failureCount)
        .animation(.snappy, value: model.showErrors)
    }

    private var media: some View {
        let bannerURL = model.banner.nilIfEmpty
        let pictureURL = model.picture.nilIfEmpty
        let uploadingBanner = model.isUploadingBanner
        let uploadingPicture = model.isUploadingPicture
        return VStack(alignment: .leading, spacing: 0) {
            PhotosPicker(selection: $bannerItem, matching: .images) {
                ZStack {
                    Rectangle().fill(AppColors.overlayLight)
                    RemoteImage(url: bannerURL, maxPixel: 1200) { Color.clear }
                    Color.black.opacity(0.25)
                    if uploadingBanner {
                        ProgressView().tint(.white)
                    } else {
                        cameraBadge(size: 48)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(10 / 3.5, contentMode: .fit)
                .clipped()
            }
            .buttonStyle(.plain)
            .disabled(model.isUploadingBanner)
            .accessibilityLabel(L("banner"))
            .accessibilityIdentifier("onboarding-banner-picker")

            PhotosPicker(selection: $pictureItem, matching: .images) {
                ZStack {
                    if pictureURL == nil {
                        Circle().fill(AppColors.avatarPlaceholder)
                    } else {
                        AvatarView(url: pictureURL, size: 84)
                        Circle().fill(Color.black.opacity(0.3))
                    }
                    if uploadingPicture {
                        ProgressView().tint(.white)
                    } else {
                        cameraBadge(size: 36)
                    }
                }
                .frame(width: 84, height: 84)
                .padding(4)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.isUploadingPicture)
            .accessibilityLabel(L("profileImage"))
            .accessibilityIdentifier("onboarding-avatar-picker")
            .padding(.leading, 16)
            .offset(y: -28)
            .padding(.bottom, -16)
        }
    }

    private func cameraBadge(size: CGFloat) -> some View {
        Image(systemName: "camera")
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .glassEffect(.regular, in: .circle)
    }

    private func field(_ field: OnboardingProfileViewModel.Field, placeholder: String, text: Binding<String>, identifier: String, axis: Axis = .horizontal, keyboard: UIKeyboardType = .default, autocapitalize: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(placeholder, text: text, axis: axis)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocapitalize ? .sentences : .never)
                .autocorrectionDisabled(!autocapitalize)
                .lineLimit(axis == .vertical ? 3...6 : 1...1)
                .focused($focus, equals: field)
                .accessibilityIdentifier(identifier)
            if model.showErrors, let message = model.error(for: field) {
                Text(message)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }
        }
    }
}
