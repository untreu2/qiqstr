import SwiftUI
import QiqstrCore

struct DatabaseKindStat: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    let count: Int
}

@MainActor
@Observable
final class DatabaseSettingsModel {
    private(set) var stats: [DatabaseKindStat] = []
    private(set) var totalEvents = 0
    private(set) var sizeMB = 0
    private(set) var isLoading = false
    private(set) var isCleaning = false
    private(set) var isWiping = false
    private(set) var hasLoaded = false
    var showWipeConfirm = false
    var showCleanupConfirm = false
    var feedback = 0

    func load() async {
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            let json = JSON.object(try await dbGetDatabaseStats()) ?? [:]
            sizeMB = Int((try? await getDatabaseSizeMb()) ?? 0)
            totalEvents = json.int("totalEvents")
            stats = [
                DatabaseKindStat(id: "textNotes", title: L("textNotes"), systemImage: "text.alignleft", count: json.int("textNotes")),
                DatabaseKindStat(id: "metadata", title: L("profiles"), systemImage: "person", count: json.int("metadata")),
                DatabaseKindStat(id: "contacts", title: L("contactLists"), systemImage: "person.2", count: json.int("contacts")),
                DatabaseKindStat(id: "reactions", title: L("reactions"), systemImage: "heart", count: json.int("reactions")),
                DatabaseKindStat(id: "reposts", title: L("reposts"), systemImage: "arrow.2.squarepath", count: json.int("reposts")),
                DatabaseKindStat(id: "zaps", title: L("zaps"), systemImage: "bolt", count: json.int("zaps")),
                DatabaseKindStat(id: "articles", title: L("articles"), systemImage: "doc.richtext", count: json.int("articles")),
            ]
        } catch {
            ToastCenter.shared.error(error)
        }
    }

    func smartCleanup() async {
        guard let me = Session.shared.pubkey, !isCleaning else { return }
        isCleaning = true
        defer { isCleaning = false }
        do {
            let result = JSON.object(try await dbSmartCleanup(ownPubkeyHex: me, interactionDays: 7, noteDays: 7)) ?? [:]
            feedback += 1
            ToastCenter.shared.show(L("settingsCleanupResult", ["count": result.int("totalDeleted")]), style: .success)
            DataBus.shared.everythingChanged()
            await load()
        } catch {
            ToastCenter.shared.error(error)
        }
    }

    func wipe() async {
        guard !isWiping else { return }
        isWiping = true
        defer { isWiping = false }
        do {
            do { try await dbWipeDirectory() } catch { try await dbWipe() }
            feedback += 1
            ToastCenter.shared.show("\(L("cleanupCompleted")) — \(L("eventsDeleted"))", style: .success)
            await load()
            DataBus.shared.everythingChanged()
            Task { await Self.resync() }
        } catch {
            ToastCenter.shared.error(error)
        }
    }

    private static func resync() async {
        guard let me = Session.shared.pubkey else { return }
        let sync = SyncService.shared
        async let following: Void = sync.syncFollowingList(me, force: true)
        async let profile: Void = sync.syncProfile(me, force: true)
        _ = await (following, profile)
        await sync.syncFeed(force: true)
        await sync.syncNotifications(force: true)
    }
}

struct DatabaseSettingsView: View {
    @State private var model = DatabaseSettingsModel()

    var body: some View {
        List {
            Section {
                stat(title: L("databaseSize"), systemImage: "internaldrive", value: "\(model.sizeMB) MB", identifier: "database-size")
                stat(title: L("totalEvents"), systemImage: "square.stack.3d.up", value: Sats.compact(model.totalEvents), identifier: "database-total")
            } footer: {
                Text(L("databaseCacheSubtitle"))
            }
            .redacted(reason: model.hasLoaded ? [] : .placeholder)
            Section {
                ForEach(model.stats) { item in
                    stat(title: item.title, systemImage: item.systemImage, value: Sats.compact(item.count), identifier: "database-stat-\(item.id)")
                }
            }
            Section {
                Button { model.showCleanupConfirm = true } label: {
                    HStack {
                        SettingsRowLabel(title: L("settingsSmartCleanup"), systemImage: "sparkles")
                        Spacer()
                        if model.isCleaning { ProgressView() }
                    }
                }
                .disabled(model.isCleaning || model.isWiping)
                .accessibilityIdentifier("database-smart-cleanup")
            } footer: {
                Text(L("settingsSmartCleanupFooter"))
            }
            Section {
                Button(role: .destructive) { model.showWipeConfirm = true } label: {
                    HStack(spacing: 8) {
                        Spacer()
                        Text(L("cleanupDatabase"))
                        if model.isWiping { ProgressView() }
                        Spacer()
                    }
                }
                .disabled(model.isCleaning || model.isWiping)
                .accessibilityIdentifier("database-wipe")
            } footer: {
                Text(L("settingsWipeFooter"))
            }
        }
        .settingsListStyle()
        .navigationTitle(L("databaseCache"))
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await model.load() }
        .task { await model.load() }
        .confirmationDialog(L("settingsSmartCleanup"), isPresented: $model.showCleanupConfirm, titleVisibility: .visible) {
            Button(L("cleanup")) { Task { await model.smartCleanup() } }
                .accessibilityIdentifier("database-smart-cleanup-confirm")
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(L("settingsSmartCleanupFooter"))
        }
        .confirmationDialog(L("cleanupDatabase"), isPresented: $model.showWipeConfirm, titleVisibility: .visible) {
            Button(L("settingsWipeAction"), role: .destructive) { Task { await model.wipe() } }
                .accessibilityIdentifier("database-wipe-confirm")
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(L("settingsWipeConfirm"))
        }
        .sensoryFeedback(.success, trigger: model.feedback)
    }

    private func stat(title: String, systemImage: String, value: String, identifier: String) -> some View {
        LabeledContent {
            Text(value)
                .monospacedDigit()
                .contentTransition(.numericText())
        } label: {
            SettingsRowLabel(title: title, systemImage: systemImage)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
