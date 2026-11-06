import SwiftUI

@MainActor
@Observable
final class SuggestedFollowsViewModel {
    enum Phase: Equatable { case loading, loaded, failed(String) }

    private(set) var phase: Phase = .loading
    private(set) var pubkeys: [String] = []
    var selected: Set<String> = []
    private(set) var isProcessing = false
    private(set) var followedCount = 0
    private(set) var failureCount = 0

    let minimumSelection: Int

    init(minimumSelection: Int) { self.minimumSelection = minimumSelection }

    var canContinue: Bool { selected.count >= minimumSelection && !isProcessing }

    func load() async {
        let me = Session.shared.pubkey
        let candidates = SuggestedUsers.pubkeys.filter { $0 != me }
        guard !candidates.isEmpty else {
            phase = .failed(L("authNoSuggested"))
            return
        }
        if pubkeys.isEmpty { phase = .loading }
        async let localProfiles: Void = ProfileCache.shared.load(candidates, fetchMissing: false)
        async let localFollows: Void = FollowService.shared.refresh()
        _ = await (localProfiles, localFollows)
        if candidates.allSatisfy({ ProfileCache.shared.profile($0) != nil }) { present(candidates) }
        await SyncService.shared.syncProfiles(candidates)
        for pubkey in candidates { await ProfileCache.shared.refresh(pubkey) }
        present(candidates)
    }

    private func present(_ candidates: [String]) {
        if pubkeys.isEmpty {
            selected = Set(candidates.filter { !FollowService.shared.isFollowing($0) })
        } else {
            selected = selected.filter { !FollowService.shared.isFollowing($0) }
        }
        pubkeys = candidates
        phase = .loaded
    }

    func toggle(_ pubkey: String) {
        guard !isProcessing, !FollowService.shared.isFollowing(pubkey) else { return }
        if selected.contains(pubkey) { selected.remove(pubkey) } else { selected.insert(pubkey) }
    }

    func followSelected() async -> Bool {
        guard canContinue else { return false }
        isProcessing = true
        defer { isProcessing = false }
        let targets = Array(selected)
        do {
            try await FollowService.shared.follow(many: targets)
            followedCount += 1
            ToastCenter.shared.show(L("authFollowedPeople", ["count": targets.count]), style: .success)
            selected.removeAll()
            return true
        } catch {
            failureCount += 1
            ToastCenter.shared.error(error)
            return false
        }
    }
}

struct SuggestedFollowsView: View {
    var onFinish: (() -> Void)?

    @State private var model: SuggestedFollowsViewModel
    @State private var cache = ProfileCache.shared
    @State private var follows = FollowService.shared
    @Environment(\.dismiss) private var dismiss

    init(onFinish: (() -> Void)?) {
        self.onFinish = onFinish
        _model = State(initialValue: SuggestedFollowsViewModel(minimumSelection: onFinish == nil ? 1 : 3))
    }

    private var isOnboarding: Bool { onFinish != nil }

    var body: some View {
        content
            .background(AppColors.background)
            .navigationTitle(isOnboarding ? "" : L("suggestedFollows"))
            .navigationBarTitleDisplayMode(isOnboarding ? .inline : .large)
            .toolbar {
                if isOnboarding {
                    ToolbarItem(placement: .principal) { OnboardingStepIndicator(current: 3) }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L("skip")) { onFinish?() }
                            .disabled(model.isProcessing)
                            .accessibilityIdentifier("suggested-skip")
                    }
                }
            }
            .task { await model.load() }
            .sensoryFeedback(.selection, trigger: model.selected)
            .sensoryFeedback(.success, trigger: model.followedCount)
            .sensoryFeedback(.error, trigger: model.failureCount)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            VStack(spacing: 18) {
                ProgressView().controlSize(.large)
                Text(L("authLoadingSuggested"))
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("suggested-loading")
        case .failed(let message):
            EmptyStateView(systemImage: "person.2.slash", title: L("failedToLoadSuggestedUsers"), message: message, actionTitle: L("retry")) {
                Task { await model.load() }
            }
            .frame(maxHeight: .infinity)
        case .loaded:
            list
        }
    }

    private var list: some View {
        List {
            Section {
                header
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 12, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(model.pubkeys, id: \.self) { pubkey in
                    row(pubkey)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load() }
        .accessibilityIdentifier("suggested-list")
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: continueTitle, isLoading: model.isProcessing, isEnabled: model.canContinue) {
                Task {
                    if await model.followSelected() {
                        if let onFinish { onFinish() } else { dismiss() }
                    }
                }
            }
            .accessibilityIdentifier("suggested-continue")
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(AppColors.background)
        }
    }

    @ViewBuilder
    private var header: some View {
        if isOnboarding {
            AuthHeader(title: L("suggestedFollows"), subtitle: L("authSuggestedSubtitle"))
        } else {
            Text(L("authSuggestedBrowseSubtitle"))
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private var continueTitle: String {
        if isOnboarding { return L("continueButton") }
        return model.selected.isEmpty ? L("follow") : L("authFollowSelected", ["count": model.selected.count])
    }

    private func row(_ pubkey: String) -> some View {
        let profile = cache.profile(pubkey)
        let alreadyFollowing = follows.isFollowing(pubkey)
        let isSelected = alreadyFollowing || model.selected.contains(pubkey)
        return Button {
            model.toggle(pubkey)
        } label: {
            HStack(spacing: 12) {
                ProfileAvatar(pubkey: pubkey, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile?.bestName ?? Profile.shortNpub(pubkey))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    if let nip05 = profile?.nip05.nilIfEmpty {
                        Text(nip05)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                    if let about = profile?.about.nilIfEmpty {
                        Text(about)
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                if alreadyFollowing {
                    Text(L("following"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.border)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(alreadyFollowing || model.isProcessing)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
        .contextMenu {
            if !isOnboarding {
                Button {
                    Router.shared.push(.profile(pubkey))
                } label: {
                    Label(L("profile"), systemImage: "person")
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("suggested-user-\(pubkey.prefix(8))")
    }
}
