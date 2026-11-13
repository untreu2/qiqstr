import SwiftUI

struct ReportTarget: Identifiable, Hashable {
    let pubkey: String
    var eventId: String?
    var parentId: String?
    var name: String?

    var id: String { eventId ?? pubkey }

    init(pubkey: String, eventId: String? = nil, parentId: String? = nil, name: String? = nil) {
        self.pubkey = pubkey
        self.eventId = eventId
        self.parentId = parentId
        self.name = name
    }

    init(note: Note) {
        self.init(pubkey: note.pubkey, eventId: note.id, parentId: note.parentId, name: note.authorName)
    }
}

@MainActor
enum Moderation {
    @discardableResult
    static func report(_ target: ReportTarget, reason: NoteReportReason, muteAuthor: Bool) async -> Bool {
        if let eventId = target.eventId { NoteInteractionStore.shared.hide(eventId, parent: target.parentId) }
        if muteAuthor { await mute(target.pubkey) }
        guard Session.shared.canSign else { return false }
        do {
            try await InteractionService.shared.report(pubkey: target.pubkey, noteId: target.eventId, reason: reason.rawValue)
            return true
        } catch {
            return false
        }
    }

    static func mute(_ pubkey: String) async {
        try? await MuteService.shared.mute(pubkey)
        DataBus.shared.feedChanged()
    }
}

struct ReportSheet: View {
    let target: ReportTarget
    var onFinish: ((ReportTarget) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var reason: NoteReportReason?
    @State private var muteAuthor = true
    @State private var isWorking = false
    @State private var cache = ProfileCache.shared

    private var name: String {
        cache.profile(target.pubkey)?.bestName ?? target.name ?? Profile.shortNpub(target.pubkey)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(NoteReportReason.allCases) { item in
                        Button {
                            reason = item
                        } label: {
                            HStack {
                                Text(item.title).foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                if reason == item { Image(systemName: "checkmark").foregroundStyle(AppColors.textPrimary).fontWeight(.semibold) }
                            }
                        }
                        .accessibilityAddTraits(reason == item ? .isSelected : [])
                        .accessibilityIdentifier("report-reason-\(item.rawValue)")
                    }
                } footer: {
                    Text(L("reportUserDescription"))
                }
                Section {
                    Toggle(L("reportAlsoMute"), isOn: $muteAuthor)
                        .accessibilityIdentifier("report-also-mute")
                } footer: {
                    Text(L("muteUserDescription"))
                }
            }
            .navigationTitle(L("reportUser", ["user": name]))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("cancel"), systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("report-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("report")) { submit() }
                        .buttonStyle(.glassProminent)
                        .foregroundStyle(AppColors.background)
                        .disabled(reason == nil || isWorking)
                        .accessibilityIdentifier("report-submit")
                }
            }
        }
    }

    private func submit() {
        guard let reason, !isWorking else { return }
        isWorking = true
        Task {
            let sent = await Moderation.report(target, reason: reason, muteAuthor: muteAuthor)
            isWorking = false
            ToastCenter.shared.show(L(sent ? "reportSentHidden" : "reportHiddenOnly"), style: .success)
            dismiss()
            onFinish?(target)
        }
    }
}

extension View {
    func reportSheet(_ target: Binding<ReportTarget?>, onFinish: ((ReportTarget) -> Void)? = nil) -> some View {
        sheet(item: target) { item in
            ReportSheet(target: item, onFinish: onFinish)
                .presentationDetents([.medium, .large])
        }
    }
}
