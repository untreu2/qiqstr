import SwiftUI
import QiqstrCore

struct EventExportFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

@MainActor
@Observable
final class EventManagerModel {
    private(set) var events: [String] = []
    private(set) var countsByKind: [Int: Int] = [:]
    private(set) var isScanning = false
    private(set) var isBroadcasting = false
    private(set) var broadcastSent = 0
    private(set) var broadcastFailed = 0
    private(set) var broadcastTotal = 0
    private(set) var isDeleting = false
    private(set) var isExporting = false
    var exportFile: EventExportFile?
    var showDeleteConfirm = false
    var showFinalConfirm = false
    var confirmText = ""
    var feedback = 0

    private var seen: Set<String> = []
    private var scanTask: Task<Void, Never>?
    private var broadcastTask: Task<Void, Never>?

    var sortedKinds: [Int] { countsByKind.keys.sorted { (countsByKind[$0] ?? 0, $1) > (countsByKind[$1] ?? 0, $0) } }
    var isBusy: Bool { isBroadcasting || isDeleting }
    var confirmWord: String { L("settingsVanishConfirmWord") }

    func scan() {
        guard let me = Session.shared.pubkey else { return }
        scanTask?.cancel()
        events = []
        countsByKind = [:]
        seen = []
        isScanning = true
        scanTask = Task {
            let stream = EventStream.make { sink in try await fetchAllEventsForAuthor(authorHex: me, sink: sink) }
            do {
                for try await raw in stream {
                    guard !Task.isCancelled else { break }
                    guard let event = JSON.object(raw), let id = event.str("id"), seen.insert(id).inserted else { continue }
                    events.append(raw)
                    countsByKind[event.int("kind"), default: 0] += 1
                }
            } catch {
                if !Task.isCancelled { ToastCenter.shared.error(error) }
            }
            if !Task.isCancelled { isScanning = false }
        }
    }

    func stop() {
        scanTask?.cancel()
        broadcastTask?.cancel()
        isScanning = false
    }

    func rebroadcast() {
        guard !events.isEmpty else {
            ToastCenter.shared.show(L("noEventsToRebroadcast"))
            return
        }
        guard !isBroadcasting else { return }
        let payload = "[\(events.joined(separator: ","))]"
        isBroadcasting = true
        broadcastSent = 0
        broadcastFailed = 0
        broadcastTotal = events.count
        broadcastTask = Task {
            let stream = EventStream.make { sink in try await streamBroadcastEvents(eventsJson: payload, relayUrls: nil, sink: sink) }
            var finished = false
            do {
                for try await raw in stream {
                    guard let progress = JSON.object(raw) else { continue }
                    broadcastSent = progress.int("sent")
                    broadcastFailed = progress.int("failed")
                    broadcastTotal = max(broadcastTotal, progress.int("total"))
                    if progress.bool("done") { finished = true }
                }
                if finished {
                    feedback += 1
                    let message = broadcastFailed > 0
                        ? L("broadcastedEventsWithFailed", ["sent": broadcastSent, "failed": broadcastFailed])
                        : L("broadcastedEvents", ["sent": broadcastSent])
                    ToastCenter.shared.show(message, style: .success)
                }
            } catch {
                ToastCenter.shared.show(L("errorRebroadcastingEventsDetail", ["error": coreErrorMessage(error)]), style: .error)
            }
            isBroadcasting = false
        }
    }

    var broadcastProgress: Double {
        guard broadcastTotal > 0 else { return 0 }
        return Double(broadcastSent + broadcastFailed) / Double(broadcastTotal)
    }

    func export() async {
        guard !events.isEmpty else {
            ToastCenter.shared.show(L("noEventsToExport"))
            return
        }
        isExporting = true
        defer { isExporting = false }
        let me = Session.shared.pubkey ?? "unknown"
        let snapshot = events
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                let objects = snapshot.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) }
                let data = try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .withoutEscapingSlashes])
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("nostr-export-\(me.prefix(8))-\(stamp).json")
                try data.write(to: url, options: .atomic)
                return url
            }.value
            exportFile = EventExportFile(url: url)
        } catch {
            ToastCenter.shared.show(L("exportFailed", ["error": coreErrorMessage(error)]), style: .error)
        }
    }

    func beginDelete() {
        guard !events.isEmpty else {
            ToastCenter.shared.show(L("noEventsFoundToDelete"), style: .error)
            return
        }
        showDeleteConfirm = true
    }

    func askFinalConfirmation() {
        confirmText = ""
        showFinalConfirm = true
    }

    var canConfirmVanish: Bool {
        confirmText.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(confirmWord) == .orderedSame
    }

    func deleteAccount() async {
        guard canConfirmVanish, !isDeleting else { return }
        let ids = events.compactMap { JSON.object($0)?.str("id") }
        guard !ids.isEmpty else {
            ToastCenter.shared.show(L("noValidEventIds"), style: .error)
            return
        }
        isDeleting = true
        defer { isDeleting = false }
        let reason = "User requested account deletion"
        do {
            let deletion = JSON.object(try await deleteEvents(eventIds: ids, reason: reason)) ?? [:]
            let deleteSuccess = deletion.int("totalSuccess")
            if deleteSuccess > 0 {
                let key = deleteSuccess == 1 ? "deletionRequestSent" : "deletionRequestSentPlural"
                ToastCenter.shared.show(L(key, ["count": ids.count, "relays": deleteSuccess]), style: .success)
            }
            try? await Task.sleep(for: .milliseconds(500))
            let vanish = JSON.object(try await requestToVanish(relayUrls: ["ALL_RELAYS"], reason: reason)) ?? [:]
            let vanishSuccess = vanish.int("totalSuccess")
            if vanishSuccess > 0 {
                let key = vanishSuccess == 1 ? "accountDeletionRequestSent" : "accountDeletionRequestSentPlural"
                ToastCenter.shared.show(L(key, ["relays": vanishSuccess]), style: .success)
                feedback += 1
                try? await Task.sleep(for: .seconds(2))
                stop()
                await Session.shared.logout()
            } else {
                let failed = vanish.int("totalFailed")
                let key = failed == 1 ? "vanishRequestFailed" : "vanishRequestFailedPlural"
                ToastCenter.shared.show(L(key, ["relays": failed]), style: .error)
            }
        } catch {
            ToastCenter.shared.show(L("errorDeletingAccount", ["error": coreErrorMessage(error)]), style: .error)
        }
    }

    static func kindName(_ kind: Int) -> String {
        switch kind {
        case 0: L("kindProfileMetadata")
        case 1: L("kindTextNote")
        case 3: L("kindFollows")
        case 4: L("kindEncryptedDM")
        case 5: L("kindEventDeletion")
        case 6: L("kindRepost")
        case 7: L("kindReaction")
        case 9735: L("kindZap")
        case 10000: L("kindMuteList")
        case 10002: L("kindRelayList")
        case 10001...10010: L("kindList", ["kind": kind])
        default: L("kindUnknown", ["kind": kind])
        }
    }

    static func kindIcon(_ kind: Int) -> String {
        switch kind {
        case 0: "person"
        case 1: "doc.text"
        case 3: "person.2"
        case 4: "lock"
        case 5: "trash"
        case 6: "arrow.2.squarepath"
        case 7: "heart"
        case 9735: "bolt"
        case 10000: "bell.slash"
        case 10002: "point.3.connected.trianglepath.dotted"
        default: "doc"
        }
    }
}

struct EventManagerSettingsView: View {
    @State private var model = EventManagerModel()

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Label {
                        Text(model.isScanning ? L("scanningEventsFound", ["count": model.events.count]) : L("eventsOnRelays", ["count": model.events.count]))
                            .contentTransition(.numericText())
                    } icon: {
                        if model.isScanning {
                            ProgressView()
                        } else {
                            SettingsIcon(systemImage: "checkmark", tint: AppColors.success)
                        }
                    }
                    Spacer()
                    if !model.isScanning {
                        Button(L("retry"), systemImage: "arrow.clockwise") { model.scan() }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("events-rescan")
                    }
                }
                .accessibilityIdentifier("events-summary")
                if model.isBroadcasting {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: model.broadcastProgress).tint(AppColors.textPrimary)
                        Text(L("broadcastProgress", ["sent": model.broadcastSent, "total": model.broadcastTotal]))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("events-broadcast-progress")
                }
            } footer: {
                Text(L("yourDataOnRelaysDescription"))
            }
            Section {
                Button { model.rebroadcast() } label: {
                    SettingsRowLabel(title: model.isBroadcasting ? L("broadcastProgress", ["sent": model.broadcastSent, "total": model.broadcastTotal]) : L("rebroadcast"), systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(model.isBusy || model.events.isEmpty)
                .accessibilityIdentifier("events-rebroadcast")
                Button { Task { await model.export() } } label: {
                    HStack {
                        SettingsRowLabel(title: model.isExporting ? L("exporting") : L("exportData"), systemImage: "square.and.arrow.up")
                        Spacer()
                        if model.isExporting { ProgressView() }
                    }
                }
                .disabled(model.isExporting || model.events.isEmpty)
                .accessibilityIdentifier("events-export")
            }
            if !model.sortedKinds.isEmpty {
                Section {
                    ForEach(model.sortedKinds, id: \.self) { kind in
                        LabeledContent {
                            Text(Sats.compact(model.countsByKind[kind] ?? 0))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        } label: {
                            Label {
                                Text(EventManagerModel.kindName(kind))
                                Text(verbatim: "kind \(kind)").font(.footnote.monospaced())
                            } icon: {
                                SettingsIcon(systemImage: EventManagerModel.kindIcon(kind))
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("events-kind-\(kind)")
                    }
                }
            }
            Section {
                Button(role: .destructive) { model.beginDelete() } label: {
                    HStack(spacing: 8) {
                        Spacer()
                        Text(L("deleteAccount"))
                        if model.isDeleting { ProgressView() }
                        Spacer()
                    }
                }
                .disabled(model.isBusy || model.isScanning)
                .accessibilityIdentifier("events-delete-account")
            } footer: {
                Text(L("settingsVanishFooter"))
            }
        }
        .settingsListStyle()
        .navigationTitle(L("yourDataOnRelays"))
        .navigationBarTitleDisplayMode(.large)
        .animation(.snappy, value: model.sortedKinds)
        .onAppear { if model.events.isEmpty && !model.isScanning { model.scan() } }
        .onDisappear { if !model.isBroadcasting && !model.isDeleting { model.stop() } }
        .sheet(item: $model.exportFile) { file in
            EventExportSheet(file: file)
                .presentationDetents([.medium])
        }
        .confirmationDialog(L("deleteAccountTitle"), isPresented: $model.showDeleteConfirm, titleVisibility: .visible) {
            Button(L("delete"), role: .destructive) { model.askFinalConfirmation() }
                .accessibilityIdentifier("events-delete-continue")
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(L("deleteAccountConfirmation"))
        }
        .alert(L("deleteAccountTitle"), isPresented: $model.showFinalConfirm) {
            TextField(model.confirmWord, text: $model.confirmText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityIdentifier("events-delete-confirm-field")
            Button(L("cancel"), role: .cancel) {}
            Button(L("deleteAccount"), role: .destructive) { Task { await model.deleteAccount() } }
                .disabled(!model.canConfirmVanish)
                .accessibilityIdentifier("events-delete-confirm")
        } message: {
            Text(L("settingsVanishTypeToConfirm", ["word": model.confirmWord]))
        }
        .sensoryFeedback(.success, trigger: model.feedback)
    }
}

struct EventExportSheet: View {
    let file: EventExportFile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text(file.url.lastPathComponent)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.secondary)
                    } icon: {
                        SettingsIcon(systemImage: "doc.badge.arrow.up")
                    }
                }
                Section {
                    ShareLink(item: file.url) {
                        Label(L("exportData"), systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("events-export-share")
                }
            }
            .navigationTitle(L("exportData"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}
