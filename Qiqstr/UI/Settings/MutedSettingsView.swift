import SwiftUI

@MainActor
@Observable
final class MutedSettingsModel {
    enum Tab: String, CaseIterable, Identifiable {
        case users, words
        var id: String { rawValue }
        var title: String { self == .users ? L("mutedUsersTitle") : L("mutedWordsTitle") }
    }

    var tab: Tab = .users
    var newWord = ""
    var showAddWord = false
    private(set) var busy: Set<String> = []
    private(set) var isRefreshing = false
    var feedback = 0

    private var service: MuteService { MuteService.shared }
    var pubkeys: [String] { service.mutedPubkeys }
    var words: [String] { service.mutedWords }
    var isLoaded: Bool { service.isLoaded }

    func appear() async {
        if !service.isLoaded { await service.load() }
        await ProfileCache.shared.load(service.mutedPubkeys)
    }

    func refresh() async {
        isRefreshing = true
        await service.load()
        let pubkeys = service.mutedPubkeys
        if !pubkeys.isEmpty { await SyncService.shared.syncProfiles(pubkeys) }
        await ProfileCache.shared.load(pubkeys, fetchMissing: false)
        for pk in pubkeys { await ProfileCache.shared.refresh(pk) }
        isRefreshing = false
    }

    func unmute(_ pubkey: String) async {
        guard busy.insert(pubkey).inserted else { return }
        defer { busy.remove(pubkey) }
        do {
            try await service.unmute(pubkey)
            feedback += 1
            ToastCenter.shared.show(L("userUnmuted"), style: .success)
        } catch {
            ToastCenter.shared.error(error)
        }
    }

    func addWord() async {
        let word = newWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !word.isEmpty else { return }
        guard !service.mutedWords.contains(word) else { newWord = ""; return }
        newWord = ""
        busy.insert("word:\(word)")
        defer { busy.remove("word:\(word)") }
        do {
            try await service.addWord(word)
            feedback += 1
        } catch {
            newWord = word
            ToastCenter.shared.error(error)
        }
    }

    func removeWord(_ word: String) async {
        let key = "word:\(word)"
        guard busy.insert(key).inserted else { return }
        defer { busy.remove(key) }
        do {
            try await service.removeWord(word)
            feedback += 1
        } catch {
            ToastCenter.shared.error(error)
        }
    }

    func isBusy(_ key: String) -> Bool { busy.contains(key) }
}

struct MutedSettingsView: View {
    @State private var model = MutedSettingsModel()
    @State private var service = MuteService.shared

    var body: some View {
        List {
            Section {
                Picker(L("mutedTitle"), selection: $model.tab) {
                    ForEach(MutedSettingsModel.Tab.allCases) { tab in
                        Text("\(tab.title) (\(tab == .users ? service.mutedPubkeys.count : service.mutedWords.count))").tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("muted-tab")
            } footer: {
                Text(L("mutedSubtitle"))
            }
            switch model.tab {
            case .users: usersSection
            case .words: wordsSection
            }
        }
        .settingsListStyle()
        .navigationTitle(L("mutedTitle"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if model.tab == .words {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("settingsAddWord"), systemImage: "plus") {
                        model.newWord = ""
                        model.showAddWord = true
                    }
                    .accessibilityIdentifier("muted-word-add")
                }
            }
        }
        .alert(L("settingsAddWord"), isPresented: $model.showAddWord) {
            TextField(L("addWordToMuteHint"), text: $model.newWord)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("muted-word-field")
            Button(L("cancel"), role: .cancel) { model.newWord = "" }
            Button(L("settingsAdd")) { Task { await model.addWord() } }
                .disabled(model.newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("muted-word-add-confirm")
        }
        .refreshable { await model.refresh() }
        .task { await model.appear() }
        .sensoryFeedback(.success, trigger: model.feedback)
        .animation(.snappy, value: service.mutedPubkeys)
        .animation(.snappy, value: service.mutedWords)
    }

    @ViewBuilder
    private var usersSection: some View {
        Section {
            if !service.isLoaded {
                ForEach(0..<3, id: \.self) { _ in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "Placeholder name").font(.body.weight(.semibold))
                            Text(verbatim: "npub1placeholder").font(.subheadline)
                        }
                    } icon: {
                        Circle().fill(AppColors.tile).frame(width: 40, height: 40)
                    }
                    .redacted(reason: .placeholder)
                }
            } else if service.mutedPubkeys.isEmpty {
                ContentUnavailableView(L("noMutedUsers"), systemImage: "person.slash", description: Text(L("youHaventMutedAnyUsersYet")))
                    .accessibilityIdentifier("muted-users-empty")
            } else {
                ForEach(service.mutedPubkeys, id: \.self) { pubkey in
                    MutedUserRow(pubkey: pubkey, isBusy: model.isBusy(pubkey))
                        .swipeActions(edge: .trailing) {
                            Button(L("unmute"), systemImage: "speaker.wave.2", role: .destructive) { Task { await model.unmute(pubkey) } }
                                .accessibilityIdentifier("muted-unmute-\(pubkey)")
                        }
                        .contextMenu {
                            Button(L("unmute"), systemImage: "speaker.wave.2") { Task { await model.unmute(pubkey) } }
                        }
                }
            }
        }
        .accessibilityIdentifier("muted-users-list")
    }

    @ViewBuilder
    private var wordsSection: some View {
        Section {
            if service.mutedWords.isEmpty {
                ContentUnavailableView(L("settingsNoMutedWords"), systemImage: "text.badge.minus")
                    .accessibilityIdentifier("muted-words-empty")
            } else {
                ForEach(service.mutedWords, id: \.self) { word in
                    HStack {
                        Label(word, systemImage: "text.badge.minus")
                        Spacer()
                        if model.isBusy("word:\(word)") { ProgressView() }
                    }
                    .contextMenu {
                        Button(L("delete"), systemImage: "trash", role: .destructive) { Task { await model.removeWord(word) } }
                    }
                    .accessibilityIdentifier("muted-word-\(word)")
                }
                .onDelete { offsets in
                    let targets = offsets.map { service.mutedWords[$0] }
                    Task { for word in targets { await model.removeWord(word) } }
                }
            }
        }
    }
}

struct MutedUserRow: View {
    let pubkey: String
    let isBusy: Bool
    @State private var cache = ProfileCache.shared
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 40

    var body: some View {
        NavigationLink(value: Route.profile(pubkey)) {
            HStack(spacing: 12) {
                ProfileAvatar(pubkey: pubkey, size: avatarSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cache.profile(pubkey)?.bestName ?? Profile.shortNpub(pubkey))
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(cache.profile(pubkey)?.nip05.nilIfEmpty ?? Profile.shortNpub(pubkey))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isBusy { ProgressView() }
            }
        }
    }
}
