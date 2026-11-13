import Foundation
import Observation
import PhotosUI
import QiqstrCore
import SwiftUI
import UniformTypeIdentifiers

struct ProfileDraft: Equatable {
    var name = ""
    var displayName = ""
    var about = ""
    var picture = ""
    var banner = ""
    var nip05 = ""
    var lud16 = ""
    var website = ""
    var location = ""

    init() {}

    init(metadata m: JSONObject) {
        func text(_ keys: String...) -> String {
            for key in keys { if let s = m[key] as? String, !s.isEmpty { return s } }
            return ""
        }
        name = text("name", "username")
        displayName = text("display_name", "displayName")
        about = text("about")
        picture = text("picture", "image")
        banner = text("banner")
        nip05 = text("nip05")
        lud16 = text("lud16")
        website = text("website")
        location = text("location")
    }

    var trimmed: ProfileDraft {
        var d = self
        d.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        d.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        d.about = about.trimmingCharacters(in: .whitespacesAndNewlines)
        d.picture = picture.trimmingCharacters(in: .whitespacesAndNewlines)
        d.banner = banner.trimmingCharacters(in: .whitespacesAndNewlines)
        d.nip05 = nip05.trimmingCharacters(in: .whitespacesAndNewlines)
        d.lud16 = lud16.trimmingCharacters(in: .whitespacesAndNewlines)
        d.website = website.trimmingCharacters(in: .whitespacesAndNewlines)
        d.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        return d
    }

    func merged(into base: JSONObject, changedFrom original: ProfileDraft) -> JSONObject {
        var m = base
        let d = trimmed
        let o = original.trimmed
        func put(_ key: String, _ value: String, _ old: String) {
            guard value != old else { return }
            if value.isEmpty { m.removeValue(forKey: key) } else { m[key] = value }
        }
        put("name", d.name, o.name)
        put("display_name", d.displayName, o.displayName)
        if m["displayName"] != nil { put("displayName", d.displayName, o.displayName) }
        if m["username"] != nil { put("username", d.name, o.name) }
        put("about", d.about, o.about)
        put("picture", d.picture, o.picture)
        if m["image"] != nil { put("image", d.picture, o.picture) }
        put("banner", d.banner, o.banner)
        put("nip05", d.nip05, o.nip05)
        put("lud16", d.lud16, o.lud16)
        put("website", d.website, o.website)
        put("location", d.location, o.location)
        return m
    }
}

enum ProfileField: Hashable {
    case name, displayName, about, picture, banner, nip05, lud16, website, location
}

enum MediaTarget { case picture, banner }

@MainActor
@Observable
final class EditProfileViewModel {
    var draft = ProfileDraft()
    private(set) var original = ProfileDraft()
    private(set) var isLoading = true
    private(set) var isSaving = false
    private(set) var uploadingPicture = false
    private(set) var uploadingBanner = false
    private(set) var savedCount = 0
    private var metadata: JSONObject = [:]

    var isDirty: Bool { draft.trimmed != original.trimmed }
    var isUploading: Bool { uploadingPicture || uploadingBanner }

    var errors: [ProfileField: String] {
        var e: [ProfileField: String] = [:]
        let d = draft.trimmed
        if d.name.count > 50 { e[.name] = L("profileNameTooLong") }
        if d.displayName.count > 50 { e[.displayName] = L("profileNameTooLong") }
        if d.about.count > 1000 { e[.about] = L("profileAboutTooLong") }
        if d.location.count > 100 { e[.location] = L("locationTooLong") }
        if !d.nip05.isEmpty, !Nip05Verifier.isValid(d.nip05) { e[.nip05] = L("profileInvalidNip05") }
        if !d.lud16.isEmpty, !Self.isLightningAddress(d.lud16) { e[.lud16] = L("profileInvalidLightningAddress") }
        if !d.website.isEmpty, !Self.isWebsite(d.website) { e[.website] = L("profileInvalidWebsite") }
        if !d.picture.isEmpty, !Self.isHTTP(d.picture) { e[.picture] = L("profileInvalidImageUrl") }
        if !d.banner.isEmpty, !Self.isHTTP(d.banner) { e[.banner] = L("profileInvalidImageUrl") }
        return e
    }

    var canSave: Bool { isDirty && errors.isEmpty && !isSaving && !isUploading && !isLoading }

    func load() async {
        guard let me = Session.shared.pubkey else { isLoading = false; return }
        apply(await ProfileDataSource.rawMetadata(me))
        isLoading = false
        await SyncService.shared.syncProfile(me, force: true)
        let fresh = await ProfileDataSource.rawMetadata(me)
        if !isDirty, !isSaving, ProfileDraft(metadata: fresh) != original { apply(fresh) }
        else if !isDirty { metadata = fresh }
    }

    private func apply(_ m: JSONObject) {
        metadata = m
        let draft = ProfileDraft(metadata: m)
        original = draft
        self.draft = draft
    }

    func upload(_ item: PhotosPickerItem, target: MediaTarget) async {
        setUploading(target, true)
        defer { setUploading(target, false) }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else { throw CoreError(L("errorSelectingMedia")) }
            let type = item.supportedContentTypes.first { $0.conforms(to: .image) }
            let maxPixel: CGFloat = target == .picture ? 1024 : 2048
            let (data, mime) = await Task.detached(priority: .userInitiated) { () -> (Data, String) in
                if type?.conforms(to: .gif) == true { return (raw, "image/gif") }
                guard let image = ImagePipeline.downsample(raw, maxPixel: maxPixel), let jpeg = image.jpegData(compressionQuality: 0.88) else {
                    return (raw, type?.preferredMIMEType ?? "image/jpeg")
                }
                return (jpeg, "image/jpeg")
            }.value
            let url = try await MediaUploadService.shared.upload(data: data, mimeType: mime)
            guard !url.isEmpty else { throw CoreError(L("uploadFailed", ["message": ""])) }
            switch target {
            case .picture: draft.picture = url
            case .banner: draft.banner = url
            }
        } catch {
            ToastCenter.shared.show(L("uploadFailed", ["message": coreMessage(error)]), style: .error)
        }
    }

    private func setUploading(_ target: MediaTarget, _ value: Bool) {
        switch target {
        case .picture: uploadingPicture = value
        case .banner: uploadingBanner = value
        }
    }

    func save() async -> Bool {
        guard canSave, let me = Session.shared.pubkey else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let base = try await SyncService.shared.latestEditableEvent(kind: 0, author: me, allowingNew: true)
            let latest = base.flatMap { JSON.object($0["content"] as? String) } ?? [:]
            if base != nil, latest.isEmpty { throw CoreError(L("noRelayConnection")) }
            let content = draft.merged(into: latest, changedFrom: original)
            try await ProfileDataSource.publishMetadata(content)
            metadata = content
            original = draft.trimmed
            draft = original
            ProfileCache.shared.set(Profile(json: content, fallbackPubkey: me))
            DataBus.shared.profileChanged()
            savedCount += 1
            ToastCenter.shared.show(L("profileSaved"), style: .success)
            return true
        } catch {
            ToastCenter.shared.show(L("profileSaveFailed", ["message": coreMessage(error)]), style: .error)
            return false
        }
    }

    static func isLightningAddress(_ s: String) -> Bool {
        let parts = s.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !parts[1].hasSuffix(".")
    }

    static func isWebsite(_ s: String) -> Bool {
        let full = s.hasPrefix("http://") || s.hasPrefix("https://") ? s : "https://\(s)"
        guard let url = URL(string: full), let host = url.host() else { return false }
        return host.contains(".") && !s.contains(" ")
    }

    static func isHTTP(_ s: String) -> Bool {
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "https" || scheme == "http") && url.host() != nil
    }
}
