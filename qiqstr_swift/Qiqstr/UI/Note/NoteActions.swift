import SwiftUI
import Translation
import UIKit

@MainActor
@Observable
final class NoteActionHandler {
    var pendingDelete: Note?
    var pendingMute: Note?
    var reportTarget: Note?
    var translateTarget: Note?

    static func shareURL(_ note: Note) -> URL {
        let bech = Nip19.nevent(note.id, author: note.pubkey) ?? Nip19.note(note.id) ?? note.id
        return URL(string: "https://njump.me/\(bech)")!
    }

    func copyText(_ note: Note) {
        UIPasteboard.general.string = note.content
        ToastCenter.shared.show(L("copiedToClipboard"), style: .success)
    }

    func copyId(_ note: Note) {
        UIPasteboard.general.string = Nip19.note(note.id) ?? note.id
        ToastCenter.shared.show(L("copiedToClipboard"), style: .success)
    }

    func verify(_ note: Note) {
        Task {
            let result = await InteractionService.shared.verify(note)
            if !result.event {
                ToastCenter.shared.show(L("eventSignatureVerificationFailed"), style: .error)
            } else if result.profile {
                ToastCenter.shared.show(L("eventAndAuthorProfileSignaturesVerified"), style: .success)
            } else {
                ToastCenter.shared.show(L("eventSignatureVerified"), style: .success)
            }
        }
    }

    func toggleBookmark(_ note: Note) {
        let wasBookmarked = BookmarkService.shared.isBookmarked(note.id)
        Task {
            do {
                try await BookmarkService.shared.toggle(note.id)
                ToastCenter.shared.show(wasBookmarked ? L("bookmarkRemoved") : L("bookmarkAdded"), style: .success)
            } catch {
                ToastCenter.shared.error(error)
            }
        }
    }

    func togglePin(_ note: Note) {
        let wasPinned = PinnedNotesService.shared.isPinned(note.id)
        Task {
            do {
                try await PinnedNotesService.shared.toggle(note.id)
                ToastCenter.shared.show(wasPinned ? L("noteUnpinned") : L("notePinned"), style: .success)
                DataBus.shared.listsChanged()
            } catch {
                ToastCenter.shared.error(error)
            }
        }
    }

    func confirmMute(_ note: Note) {
        let pubkey = note.pubkey
        Task {
            await Moderation.mute(pubkey)
            ToastCenter.shared.show(L("feedUserMuted"), style: .success)
        }
    }

    func confirmDelete(_ note: Note) {
        NoteInteractionStore.shared.markDeleted(note.id, parent: note.parentId)
        Task {
            do {
                try await InteractionService.shared.delete(note)
                ToastCenter.shared.show(L("feedNoteDeleted"), style: .success)
            } catch {
                NoteInteractionStore.shared.unmarkDeleted(note.id, parent: note.parentId)
                ToastCenter.shared.error(error)
            }
        }
    }

}

struct NoteMenuItems: View {
    let note: Note
    let actions: NoteActionHandler
    @State private var bookmarks = BookmarkService.shared
    @State private var pinned = PinnedNotesService.shared

    private var isMine: Bool { note.pubkey == Session.shared.pubkey }

    var body: some View {
        Section {
            if NoteLanguage.needsTranslation(note) {
                Button(L("feedTranslate"), systemImage: "translate") { actions.translateTarget = note }
            }
            Button(L("feedCopyText"), systemImage: "doc.on.doc") { actions.copyText(note) }
            Button(L("feedCopyNoteId"), systemImage: "number") { actions.copyId(note) }
            ShareLink(item: NoteActionHandler.shareURL(note)) { Label(L("share"), systemImage: "square.and.arrow.up") }
        }
        Section {
            let bookmarked = bookmarks.isBookmarked(note.id)
            Button(bookmarked ? L("feedRemoveBookmark") : L("addBookmark"), systemImage: bookmarked ? "bookmark.slash" : "bookmark") { actions.toggleBookmark(note) }
            if isMine {
                let isPinned = pinned.isPinned(note.id)
                Button(isPinned ? L("unpinNote") : L("pinNote"), systemImage: isPinned ? "pin.slash" : "pin") { actions.togglePin(note) }
            }
            Button(L("statistics"), systemImage: "chart.bar") { Router.shared.push(.noteStatistics(note.id)) }
            Button(L("quotes"), systemImage: "quote.bubble") { Router.shared.push(.quotes(note.id)) }
            Button(L("verifySignature"), systemImage: "checkmark.shield") { actions.verify(note) }
        }
        Section {
            if isMine {
                Button(L("delete"), systemImage: "trash", role: .destructive) { actions.pendingDelete = note }
            } else {
                Button(L("feedMuteAuthor"), systemImage: "speaker.slash") { actions.pendingMute = note }
                Button(L("report"), systemImage: "flag", role: .destructive) { actions.reportTarget = note }
            }
        }
    }
}

struct NoteActionDialogs: ViewModifier {
    @Bindable var actions: NoteActionHandler
    @State private var cache = ProfileCache.shared

    func body(content: Content) -> some View {
        content
            .confirmationDialog(L("deleteThisPost"), isPresented: Binding(get: { actions.pendingDelete != nil }, set: { if !$0 { actions.pendingDelete = nil } }), titleVisibility: .visible, presenting: actions.pendingDelete) { note in
                Button(L("delete"), role: .destructive) { actions.confirmDelete(note) }
                    .accessibilityIdentifier("note-delete-confirm")
                Button(L("cancel"), role: .cancel) {}
            }
            .confirmationDialog(muteTitle, isPresented: Binding(get: { actions.pendingMute != nil }, set: { if !$0 { actions.pendingMute = nil } }), titleVisibility: .visible, presenting: actions.pendingMute) { note in
                Button(L("mute"), role: .destructive) { actions.confirmMute(note) }
                    .accessibilityIdentifier("note-mute-confirm")
                Button(L("cancel"), role: .cancel) {}
            } message: { _ in
                Text(L("muteUserDescription"))
            }
            .translationPresentation(isPresented: Binding(get: { actions.translateTarget != nil }, set: { if !$0 { actions.translateTarget = nil } }), text: actions.translateTarget.map(NoteLanguage.text(for:)) ?? "")
            .sheet(item: $actions.reportTarget) { note in
                ReportSheet(target: ReportTarget(note: note))
                    .presentationDetents([.medium, .large])
            }
    }

    private var muteTitle: String {
        guard let note = actions.pendingMute else { return L("mute") }
        return L("muteUser", ["user": displayName(note)])
    }

    private func displayName(_ note: Note) -> String {
        cache.profile(note.pubkey)?.bestName ?? note.authorName ?? Profile.shortNpub(note.pubkey)
    }
}

extension View {
    func noteActionDialogs(_ actions: NoteActionHandler) -> some View { modifier(NoteActionDialogs(actions: actions)) }
}
