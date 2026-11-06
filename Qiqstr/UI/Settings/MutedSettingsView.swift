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
    @FocusState private var wordFocused: Bool

    var body: some View {
        List {
            SettingsPageHeader(subtitle: L("mutedSubtitle"))
            Section {
                Picker("", selection: $model.tab) {
                    ForEach(MutedSettingsModel.Tab.allCases) { tab in
                        Text("\(tab.title) (\(tab == .users ? service.mutedPubkeys.count : service.mutedWords.count))").tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("muted-tab")
            }
            switch model.tab {
            case .users: usersSection
            case .words: wordsSection
            }
        }
        .settingsListStyle()
        .navigationTitle(L("mutedTitle"))
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
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if service.mutedPubkeys.isEmpty {
                VStack(spacing: 6) {
                    Text(L("noMutedUsers")).font(.system(size: 16, weight: .semibold))
                    Text(L("youHaventMutedAnyUsersYet")).font(.system(size: 14)).foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .accessibilityIdentifier("muted-users-empty")
            } else {
                ForEach(service.mutedPubkeys, id: \.self) { pubkey in
                    MutedUserRow(pubkey: pubkey, isBusy: model.isBusy(pubkey)) {
                        Task { await model.unmute(pubkey) }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(L("unmute")) { Task { await model.unmute(pubkey) } }
                            .tint(AppColors.textPrimary)
                    }
                }
            }
        }
        .accessibilityIdentifier("muted-users-list")
    }

    @ViewBuilder
    private var wordsSection: some View {
        Section {
            HStack(spacing: 10) {
                TextField(L("addWordToMuteHint"), text: $model.newWord)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($wordFocused)
                    .onSubmit { Task { await model.addWord() } }
                    .accessibilityIdentifier("muted-word-field")
                Button {
                    Task { await model.addWord() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(AppColors.textPrimary)
                .disabled(model.newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(L("settingsAddWord"))
                .accessibilityIdentifier("muted-word-add")
            }
        }
        Section {
            if service.mutedWords.isEmpty {
                Text(L("settingsNoMutedWords"))
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("muted-words-empty")
            } else {
                ForEach(service.mutedWords, id: \.self) { word in
                    HStack {
                        Image(systemName: "text.badge.minus").foregroundStyle(AppColors.textSecondary)
                        Text(word).font(.system(size: 16))
                        Spacer()
                        if model.isBusy("word:\(word)") { ProgressView() }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(L("delete"), role: .destructive) { Task { await model.removeWord(word) } }
                    }
                    .contextMenu {
                        Button(L("delete"), systemImage: "trash", role: .destructive) { Task { await model.removeWord(word) } }
                    }
                    .accessibilityIdentifier("muted-word-\(word)")
                }
            }
        }
    }
}

struct MutedUserRow: View {
    let pubkey: String
    let isBusy: Bool
    let onUnmute: () -> Void
    @State private var cache = ProfileCache.shared

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: Route.profile(pubkey)) {
                HStack(spacing: 12) {
                    ProfileAvatar(pubkey: pubkey, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cache.profile(pubkey)?.bestName ?? Profile.shortNpub(pubkey))
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                        Text(cache.profile(pubkey)?.nip05.nilIfEmpty ?? Profile.shortNpub(pubkey))
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Button(action: onUnmute) {
                ZStack {
                    Text(L("unmute")).opacity(isBusy ? 0 : 1)
                    if isBusy { ProgressView().controlSize(.small) }
                }
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 6)
            }
            .buttonStyle(.glass)
            .disabled(isBusy)
            .accessibilityIdentifier("muted-unmute-\(pubkey)")
        }
        .padding(.vertical, 2)
    }
}
