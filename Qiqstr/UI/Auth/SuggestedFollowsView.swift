import SwiftUI

@MainActor
@Observable
final class SuggestedFollowsViewModel {
    var interests: Set<FollowInterest>
    private(set) var packs: [FollowPack] = []
    var selected: Set<String> = []
    var expanded: Set<String> = []
    private(set) var isProcessing = false
    private(set) var followedCount = 0
    private(set) var failureCount = 0
    private(set) var deadlinePassed = false
    private var requestedProfiles: Set<String> = []
    private var didPreselectFallback = false

    let minimumSelection: Int
    let preselectsFallback: Bool
    private let service = FollowPackService.shared

    static let maximumPacks = 12
    static let deadline: Duration = .seconds(4)

    init(interests: Set<FollowInterest>, minimumSelection: Int, preselectsFallback: Bool) {
        self.interests = interests
        self.minimumSelection = minimumSelection
        self.preselectsFallback = preselectsFallback
    }

    var showsSkeleton: Bool { packs.isEmpty && !deadlinePassed && !service.hasLoaded }
    var canContinue: Bool { selected.count >= minimumSelection && !isProcessing }
    var remaining: Int { max(minimumSelection - selected.count, 0) }

    private var me: String? { Session.shared.pubkey }

    func load() async {
        service.prefetch()
        await FollowService.shared.refresh()
        refreshPacks()
        async let deadline: Void = waitForDeadline()
        async let loaded: Void = service.waitUntilLoaded()
        _ = await (deadline, loaded)
        refreshPacks()
    }

    func reload() async {
        await service.reload()
        refreshPacks()
    }

    private func waitForDeadline() async {
        try? await Task.sleep(for: Self.deadline)
        deadlinePassed = true
        refreshPacks()
    }

    func refreshPacks() {
        let ranked = Array(service.ranked(for: interests).prefix(Self.maximumPacks))
        guard !ranked.isEmpty || deadlinePassed || service.hasLoaded else {
            packs = []
            return
        }
        packs = ranked + [fallbackPack]
        if ranked.isEmpty { preselectFallback() }
        selected = selected.filter { !FollowService.shared.isFollowing($0) }
        loadProfiles(packs.flatMap { $0.members.prefix(5) })
        expanded.compactMap { id in packs.first { $0.id == id } }.forEach { loadProfiles($0.members) }
    }

    private var fallbackPack: FollowPack {
        FollowPack(
            id: "qiqstr:suggested",
            kind: 0,
            author: "",
            title: L("authPackSuggestedTitle"),
            summary: L("authPackSuggestedSubtitle"),
            image: "",
            members: SuggestedUsers.pubkeys.filter { $0 != me },
            topics: [],
            createdAt: 0
        )
    }

    private func preselectFallback() {
        guard preselectsFallback, !didPreselectFallback, selected.isEmpty else { return }
        didPreselectFallback = true
        selected = Set(candidates(fallbackPack))
    }

    private func loadProfiles(_ pubkeys: [String]) {
        let wanted = Array(Set(pubkeys).subtracting(requestedProfiles).prefix(150))
        guard !wanted.isEmpty else { return }
        requestedProfiles.formUnion(wanted)
        Task {
            let cache = ProfileCache.shared
            await cache.load(wanted, fetchMissing: false)
            let missing = wanted.filter { cache.profile($0) == nil }
            guard !missing.isEmpty else { return }
            await SyncService.shared.syncProfiles(missing)
            await cache.load(missing, fetchMissing: false)
        }
    }

    func toggleInterest(_ interest: FollowInterest) {
        if interests.contains(interest) { interests.remove(interest) } else { interests.insert(interest) }
        FollowInterest.saved = interests
        refreshPacks()
    }

    func candidates(_ pack: FollowPack) -> [String] {
        pack.members.filter { $0 != me && !FollowService.shared.isFollowing($0) }
    }

    func isPackSelected(_ pack: FollowPack) -> Bool {
        let candidates = candidates(pack)
        return !candidates.isEmpty && selected.isSuperset(of: candidates)
    }

    func togglePack(_ pack: FollowPack) {
        guard !isProcessing else { return }
        let candidates = candidates(pack)
        if selected.isSuperset(of: candidates) { selected.subtract(candidates) } else { selected.formUnion(candidates) }
    }

    func toggle(_ pubkey: String) {
        guard !isProcessing, !FollowService.shared.isFollowing(pubkey) else { return }
        if selected.contains(pubkey) { selected.remove(pubkey) } else { selected.insert(pubkey) }
    }

    func isExpanded(_ pack: FollowPack) -> Bool { expanded.contains(pack.id) }

    func setExpanded(_ pack: FollowPack, _ value: Bool) {
        if value {
            expanded.insert(pack.id)
            loadProfiles(pack.members)
        } else {
            expanded.remove(pack.id)
        }
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
    @State private var follows = FollowService.shared
    @State private var packService = FollowPackService.shared
    @Environment(\.dismiss) private var dismiss

    init(interests: Set<FollowInterest> = [], onFinish: (() -> Void)?) {
        self.onFinish = onFinish
        let isOnboarding = onFinish != nil
        _model = State(initialValue: SuggestedFollowsViewModel(
            interests: interests.isEmpty ? FollowInterest.saved : interests,
            minimumSelection: isOnboarding ? 3 : 1,
            preselectsFallback: isOnboarding
        ))
    }

    private var isOnboarding: Bool { onFinish != nil }

    var body: some View {
        list
            .navigationTitle(isOnboarding ? "" : L("suggestedFollows"))
            .navigationBarTitleDisplayMode(isOnboarding ? .inline : .large)
            .toolbar {
                if isOnboarding {
                    ToolbarItem(placement: .principal) { OnboardingStepIndicator(current: 4) }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L("skip")) { onFinish?() }
                            .disabled(model.isProcessing)
                            .accessibilityIdentifier("suggested-skip")
                    }
                }
            }
            .task { await model.load() }
            .onChange(of: packService.packs) { model.refreshPacks() }
            .onChange(of: follows.following) { model.refreshPacks() }
            .sensoryFeedback(.selection, trigger: model.selected)
            .sensoryFeedback(.selection, trigger: model.interests)
            .sensoryFeedback(.success, trigger: model.followedCount)
            .sensoryFeedback(.error, trigger: model.failureCount)
    }

    private var list: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 8, trailing: 4))
                interestsRow
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            if model.showsSkeleton {
                ForEach(0..<3, id: \.self) { _ in
                    Section { FollowPackSkeleton() }
                }
                .accessibilityIdentifier("suggested-loading")
            } else {
                ForEach(model.packs) { pack in
                    packSection(pack)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(16)
        .animation(.snappy, value: model.packs.map(\.id))
        .refreshable { await model.reload() }
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
            .background(.bar)
        }
    }

    @ViewBuilder
    private var header: some View {
        if isOnboarding {
            AuthHeader(title: L("authPacksTitle"), subtitle: L("authPacksSubtitle"))
        } else {
            Text(L("authSuggestedBrowseSubtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var interestsRow: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(orderedInterests) { interest in
                        InterestChip(interest: interest, isSelected: model.interests.contains(interest), compact: true) {
                            withAnimation(.snappy) { model.toggleInterest(interest) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("suggested-interests")
    }

    private var orderedInterests: [FollowInterest] {
        FollowInterest.allCases.filter { model.interests.contains($0) } + FollowInterest.allCases.filter { !model.interests.contains($0) }
    }

    private func packSection(_ pack: FollowPack) -> some View {
        Section {
            FollowPackHeader(pack: pack, isSelected: model.isPackSelected(pack), isDisabled: model.isProcessing || model.candidates(pack).isEmpty) {
                withAnimation(.snappy) { model.togglePack(pack) }
            }
            DisclosureGroup(isExpanded: Binding(get: { model.isExpanded(pack) }, set: { value in withAnimation(.snappy) { model.setExpanded(pack, value) } })) {
                ForEach(pack.members, id: \.self) { pubkey in
                    FollowPackMemberRow(
                        pubkey: pubkey,
                        isSelected: model.selected.contains(pubkey),
                        alreadyFollowing: follows.isFollowing(pubkey)
                    ) {
                        model.toggle(pubkey)
                    }
                    .disabled(model.isProcessing)
                }
            } label: {
                Text(L("authPackPeople", ["count": selectedCount(in: pack)]))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("pack-expand")
        }
    }

    private func selectedCount(in pack: FollowPack) -> Int {
        pack.members.filter { model.selected.contains($0) }.count
    }

    private var continueTitle: String {
        if isOnboarding {
            return model.remaining > 0 ? L("authSelectMore", ["count": model.remaining]) : L("authFollowAndContinue", ["count": model.selected.count])
        }
        return model.selected.isEmpty ? L("follow") : L("authFollowSelected", ["count": model.selected.count])
    }
}
