import SwiftUI

enum NoteStatisticsTab: String, CaseIterable, Identifiable {
    case reactions, reposts, zaps
    var id: String { rawValue }
    var title: String {
        switch self {
        case .reactions: L("reactions")
        case .reposts: L("reposts")
        case .zaps: L("zaps")
        }
    }
}

struct NoteReactionGroup: Identifiable {
    var id: String { emoji }
    var emoji: String
    var items: [NoteInteractionDetail]
}

@MainActor
@Observable
final class NoteStatisticsViewModel {
    let noteId: String
    private(set) var details: [NoteInteractionDetail] = []
    private(set) var isLoading = true

    init(noteId: String) { self.noteId = noteId }

    var reactions: [NoteInteractionDetail] { details.filter { $0.kind == .reaction } }
    var reposts: [NoteInteractionDetail] { details.filter { $0.kind == .repost }.sorted { $0.createdAt > $1.createdAt } }
    var zaps: [NoteInteractionDetail] { details.filter { $0.kind == .zap }.sorted { $0.zapAmount > $1.zapAmount } }
    var totalZapped: Int { zaps.reduce(0) { $0 + $1.zapAmount } }

    var reactionGroups: [NoteReactionGroup] {
        var map: [String: [NoteInteractionDetail]] = [:]
        for item in reactions { map[Self.emoji(item.content), default: []].append(item) }
        return map.map { NoteReactionGroup(emoji: $0.key, items: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.items.count == $1.items.count ? $0.emoji < $1.emoji : $0.items.count > $1.items.count }
    }

    static func emoji(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "+" { return "❤️" }
        if trimmed == "-" { return "👎" }
        if trimmed.hasPrefix(":") && trimmed.hasSuffix(":") { return trimmed }
        return String(trimmed.prefix(4))
    }

    func load() async {
        apply(await InteractionService.shared.detailedInteractions(noteId))
        await SyncService.shared.syncInteractions(for: [noteId])
        apply(await InteractionService.shared.detailedInteractions(noteId))
        isLoading = false
    }

    private func apply(_ items: [NoteInteractionDetail]) {
        var seen: Set<String> = []
        details = items.filter { seen.insert($0.id).inserted }
        if !details.isEmpty { isLoading = false }
        let pubkeys = Array(Set(details.map(\.pubkey))).filter { ProfileCache.shared.profile($0) == nil }
        if !pubkeys.isEmpty { Task { await ProfileCache.shared.load(pubkeys) } }
    }
}

struct NoteStatisticsView: View {
    let noteId: String
    @State private var model: NoteStatisticsViewModel
    @State private var tab: NoteStatisticsTab = .reactions

    init(noteId: String) {
        self.noteId = noteId
        _model = State(initialValue: NoteStatisticsViewModel(noteId: noteId))
    }

    var body: some View {
        List {
            switch tab {
            case .reactions:
                ForEach(model.reactionGroups) { group in
                    Section {
                        ForEach(group.items) { item in
                            NoteInteractionUserRow(detail: item, trailing: AnyView(Text(group.emoji).font(.title3)))
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Text(group.emoji)
                            Text("\(group.items.count)").monospacedDigit()
                        }
                    }
                }
            case .reposts:
                Section {
                    ForEach(model.reposts) { item in
                        NoteInteractionUserRow(detail: item, trailing: AnyView(Image(systemName: "arrow.2.squarepath").foregroundStyle(AppColors.repost)))
                    }
                }
            case .zaps:
                Section {
                    ForEach(model.zaps) { item in
                        NoteInteractionUserRow(detail: item, trailing: AnyView(zapAmount(item.zapAmount)))
                    }
                } header: {
                    if model.totalZapped > 0 {
                        Label {
                            Text("\(Sats.format(model.totalZapped)) \(L("feedSats"))").monospacedDigit()
                        } icon: {
                            Image(systemName: "bolt.fill").foregroundStyle(AppColors.zap)
                        }
                    }
                }
            }
        }
        .safeAreaBar(edge: .top) {
            Picker(L("statistics"), selection: $tab) {
                ForEach(NoteStatisticsTab.allCases) { tab in
                    Text("\(tab.title) \(count(tab))").tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityIdentifier("statistics-tabs")
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("statistics-list")
        .overlay {
            if isEmpty {
                if model.isLoading {
                    ProgressView().controlSize(.large)
                } else {
                    EmptyStateView(systemImage: "chart.bar", title: L("noInteractionsYet"))
                        .accessibilityIdentifier("statistics-empty")
                }
            }
        }
        .refreshable { await model.load() }
        .navigationTitle(L("interactions"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .sensoryFeedback(.selection, trigger: tab)
    }

    private var isEmpty: Bool {
        switch tab {
        case .reactions: model.reactions.isEmpty
        case .reposts: model.reposts.isEmpty
        case .zaps: model.zaps.isEmpty
        }
    }

    private func count(_ tab: NoteStatisticsTab) -> String {
        let n: Int
        switch tab {
        case .reactions: n = model.reactions.count
        case .reposts: n = model.reposts.count
        case .zaps: n = model.zaps.count
        }
        return n > 0 ? "\(n)" : ""
    }

    private func zapAmount(_ sats: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill").foregroundStyle(AppColors.zap)
            Text(Sats.format(sats)).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }
}

struct NoteInteractionUserRow: View {
    let detail: NoteInteractionDetail
    var trailing: AnyView
    @State private var cache = ProfileCache.shared

    var body: some View {
        Button { Router.shared.push(.profile(detail.pubkey)) } label: {
            HStack(spacing: 12) {
                ProfileAvatar(pubkey: detail.pubkey, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(cache.profile(detail.pubkey)?.bestName ?? Profile.shortNpub(detail.pubkey))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    if detail.kind == .zap, !detail.content.isEmpty {
                        Text(detail.content).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    } else {
                        Text(TimeFormat.relative(detail.createdAt)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                trailing
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("statistics-user-row")
    }
}
