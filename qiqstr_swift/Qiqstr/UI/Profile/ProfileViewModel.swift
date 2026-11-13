import Foundation
import Observation

enum ProfileTab: String, CaseIterable, Identifiable {
    case notes, replies, photos, likes
    var id: String { rawValue }
    var title: String { self == .photos ? L("media") : L(rawValue) }
}

struct ProfileMediaEntry: Identifiable, Hashable {
    var item: NoteMediaItem
    var noteId: String
    var author: String? = nil
    var id: String { "\(noteId)|\(item.url)" }
    var url: String { item.url }
    var isVideo: Bool { item.isVideo }
}

@MainActor
@Observable
final class ProfileViewModel {
    let pubkey: String
    private(set) var profile: Profile
    private(set) var nip05Verified = false
    @ObservationIgnored private var checkedNip05: String?
    @ObservationIgnored private var nip05Task: Task<Void, Never>?
    private(set) var followingCount: Int?
    private(set) var followerCount: Int?
    private(set) var followsMe = false
    private(set) var followScore: FollowScore?
    private(set) var mutualFollowers: [String] = []
    private(set) var badges: [ProfileBadge] = []
    private(set) var media: [ProfileMediaEntry] = []

    private(set) var notes: [Note] = []
    private(set) var replies: [Note] = []
    private(set) var likes: [Note] = []
    private(set) var pinned: [Note] = []
    private(set) var pinnedIds: [String] = []

    private(set) var isSyncingNotes = true
    private(set) var hasLoadedNotes = false
    private(set) var hasLoadedLikes = false
    private(set) var canLoadMoreNotes = false
    private(set) var canLoadMoreReplies = false
    private(set) var canLoadMoreLikes = false
    private(set) var isLoadingMore = false
    private(set) var loadMoreCount = 0

    var tab: ProfileTab = .notes

    private var notesLimit = ProfileDataSource.pageSize
    private var repliesLimit = ProfileDataSource.pageSize
    private var reactionLimit = ProfileDataSource.pageSize * 3
    private var requestedLikeIds: Set<String> = []
    private var requestedPinnedIds: Set<String> = []
    private var started = false
    private var likesExhausted = false

    init(pubkey: String) {
        self.pubkey = pubkey
        self.profile = ProfileCache.shared.profile(pubkey) ?? Profile(pubkey: pubkey)
        let counts = ProfileCountsStore.shared.counts(for: pubkey)
        self.followingCount = counts?.following
        self.followerCount = counts?.followers
        self.badges = BadgeService.shared.cached(for: pubkey) ?? []
    }

    var isMe: Bool { Session.shared.pubkey == pubkey }
    var npub: String { Nip19.npub(pubkey) ?? pubkey }
    var profileLink: URL { URL(string: "https://njump.me/\(npub)") ?? URL(string: "https://njump.me")! }
    var isValidPubkey: Bool { pubkey.count == 64 && pubkey.allSatisfy(\.isHexDigit) }

    var displayName: String {
        if !profile.displayName.isEmpty { return profile.displayName }
        if !profile.name.isEmpty { return profile.name }
        if let parts = Nip05Verifier.parts(profile.nip05), parts.name != "_" { return parts.name }
        return L("anonymous")
    }

    var handle: String? {
        guard !profile.name.isEmpty, !profile.displayName.isEmpty, profile.name != profile.displayName else { return nil }
        return "@\(profile.name)"
    }

    var websiteURL: URL? {
        let raw = profile.website.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw.hasPrefix("http://") || raw.hasPrefix("https://") ? raw : "https://\(raw)")
    }

    private func rebuildMedia() {
        let own = (notes + replies).filter { !$0.isRepost && $0.pubkey == pubkey }.sorted { $0.createdAt > $1.createdAt }
        var seen = Set<String>()
        var result: [ProfileMediaEntry] = []
        for note in own where note.contentWarning == nil || WebOfTrustService.showsSensitiveContent || SensitiveContentStore.shared.isRevealed(note.id) {
            for item in NoteContentCache.content(for: note).media where seen.insert(item.url).inserted {
                result.append(ProfileMediaEntry(item: item, noteId: note.id))
            }
        }
        if result != media { media = result }
    }

    var visibleNotes: [Note] {
        let pinnedSet = Set(pinned.map(\.id))
        return notes.filter { $0.isRepost || !pinnedSet.contains($0.id) }
    }

    func start() async {
        guard !started, isValidPubkey else { return }
        started = true
        await reloadProfile()
        async let notes: Void = reloadNotes()
        async let pinned: Void = loadPinned(remote: false)
        async let following: Void = loadFollowing(sync: false)
        async let badges: Void = loadBadges(remote: false)
        _ = await (notes, pinned, following, badges)
        Task { await syncAll(force: false) }
        Task { await ZapperDirectory.shared.verify(pubkey) }
    }

    func refresh() async {
        guard isValidPubkey else { return }
        let sync = Task { await syncAll(force: true) }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await sync.value }
            group.addTask { try? await Task.sleep(for: .seconds(4)) }
            await group.next()
            group.cancelAll()
        }
    }

    private func syncAll(force: Bool) async {
        async let profileSync: Void = syncProfile(force: force)
        async let notesSync: Void = syncNotes(force: force)
        async let reactions: Void = syncLikes()
        async let pinnedSync: Void = loadPinned(remote: true)
        async let counts: Void = loadCounts(force: force)
        async let score: Void = loadFollowScore()
        async let badgeSync: Void = loadBadges(remote: true)
        _ = await (profileSync, notesSync, reactions, pinnedSync, counts, score, badgeSync)
    }

    private func syncProfile(force: Bool) async {
        await SyncService.shared.syncProfile(pubkey, force: force)
        await reloadProfile()
    }

    private func syncNotes(force: Bool) async {
        isSyncingNotes = true
        await SyncService.shared.syncProfileNotes(pubkey, force: force)
        await reloadNotes()
        isSyncingNotes = false
    }

    private func syncLikes() async {
        await SyncService.shared.syncProfileReactions(pubkey)
        await reloadLikes()
    }

    func reloadProfile() async {
        if let fresh = await ProfileDataSource.profile(pubkey) {
            if fresh != profile { profile = fresh }
            if ProfileCache.shared.profile(pubkey) != fresh { ProfileCache.shared.set(fresh) }
        }
        scheduleNip05Check()
    }

    private func scheduleNip05Check() {
        let nip05 = profile.nip05
        guard nip05 != checkedNip05 else { return }
        checkedNip05 = nip05
        nip05Task?.cancel()
        nip05Task = Task { await verifyNip05() }
    }

    private func verifyNip05() async {
        let nip05 = profile.nip05
        guard !nip05.isEmpty else { nip05Verified = false; return }
        let ok = await Nip05Verifier.shared.verify(nip05: nip05, pubkey: pubkey)
        if profile.nip05 == nip05 { nip05Verified = ok }
    }

    func reloadNotes() async {
        async let n = ProfileDataSource.notes(pubkey, limit: notesLimit)
        async let r = ProfileDataSource.replies(pubkey, limit: repliesLimit)
        let (newNotes, newReplies) = await (n, r)
        if newNotes != notes { notes = newNotes }
        if newReplies != replies { replies = newReplies }
        rebuildMedia()
        canLoadMoreNotes = newNotes.count >= notesLimit
        canLoadMoreReplies = newReplies.count >= repliesLimit
        hasLoadedNotes = true
        preloadAuthors(newNotes + newReplies)
    }

    func reloadLikes() async {
        let loaded = await ProfileDataSource.likes(pubkey, reactionLimit: reactionLimit)
        if loaded != likes { likes = loaded }
        hasLoadedLikes = true
        preloadAuthors(loaded)
        let ids = await ProfileDataSource.likedNoteIds(pubkey, reactionLimit: reactionLimit)
        canLoadMoreLikes = !likesExhausted && !ids.isEmpty
        let have = Set(loaded.map(\.id))
        let missing = ids.filter { !have.contains($0) && !requestedLikeIds.contains($0) }
        guard !missing.isEmpty else { return }
        requestedLikeIds.formUnion(missing)
        if await ProfileDataSource.fetchMissingNotes(missing) {
            let refreshed = await ProfileDataSource.likes(pubkey, reactionLimit: reactionLimit)
            if refreshed != likes { likes = refreshed }
            preloadAuthors(refreshed)
        }
    }

    func loadPinned(remote: Bool) async {
        let service = PinnedNotesService.shared
        let ids = remote ? await service.load(for: pubkey) : await service.cachedIds(for: pubkey)
        await applyPinned(ids)
    }

    func pinnedChanged() async {
        guard isMe else { return }
        await applyPinned(PinnedNotesService.shared.pinnedIds)
    }

    private func applyPinned(_ ids: [String]) async {
        pinnedIds = ids
        guard !ids.isEmpty else { pinned = []; return }
        var found = await ProfileDataSource.notes(ids: ids, owner: pubkey)
        let missing = ids.filter { id in !found.contains { $0.id == id } && !requestedPinnedIds.contains(id) }
        if !missing.isEmpty {
            requestedPinnedIds.formUnion(missing)
            if await ProfileDataSource.fetchMissingNotes(missing) { found = await ProfileDataSource.notes(ids: ids, owner: pubkey) }
        }
        guard pinnedIds == ids else { return }
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        let sorted = found.filter { order[$0.id] != nil }.sorted { (order[$0.id] ?? 0) > (order[$1.id] ?? 0) }
        if sorted != pinned { pinned = sorted }
        preloadAuthors(sorted)
    }

    func loadFollowing(sync: Bool) async {
        if sync { await SyncService.shared.syncFollowingList(pubkey, force: true) }
        let list = await ProfileDataSource.following(pubkey)
        if !list.isEmpty || sync {
            followingCount = list.count
            ProfileCountsStore.shared.update(pubkey, following: list.count)
        }
        if let me = Session.shared.pubkey, me != pubkey { followsMe = list.contains(me) }
    }

    private func loadCounts(force: Bool) async {
        async let followers: Void = loadFollowerCount()
        async let following: Void = loadFollowingThenSync()
        _ = await (followers, following)
    }

    private func loadFollowerCount() async {
        guard let count = await ProfileDataSource.followerCount(pubkey) else { return }
        followerCount = count
        ProfileCountsStore.shared.update(pubkey, followers: count)
    }

    private func loadFollowingThenSync() async {
        await loadFollowing(sync: false)
        await loadFollowing(sync: true)
    }

    func loadFollowScore() async {
        guard !isMe else { followScore = nil; return }
        let score = await ProfileDataSource.followScore(target: pubkey)
        if score != followScore { followScore = score }
        guard let score, score.count > 0 else { mutualFollowers = []; return }
        let mutuals = await ProfileDataSource.mutualFollowers(target: pubkey)
        if mutuals != mutualFollowers { mutualFollowers = mutuals }
        let missing = mutuals.prefix(40).filter { ProfileCache.shared.profile($0) == nil }
        if !missing.isEmpty { await ProfileCache.shared.load(Array(missing)) }
    }

    func loadBadges(remote: Bool) async {
        let loaded = remote ? await BadgeService.shared.refresh(for: pubkey) : await BadgeService.shared.local(for: pubkey)
        guard remote || !loaded.isEmpty else { return }
        if loaded != badges { badges = loaded }
    }

    private func fetchOlderFromRelays(before list: [Note]) async -> Bool {
        let oldest = list.map(\.displayTimestamp).filter { $0 > 0 }.min() ?? TimeFormat.now
        return await NoteRepository.fetchOlder(authors: [pubkey], until: oldest) > 0
    }

    func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer {
            isLoadingMore = false
            loadMoreCount += 1
        }
        let page = ProfileDataSource.pageSize
        switch tab {
        case .notes, .photos:
            guard canLoadMoreNotes else { return }
            notesLimit += page
            let previous = notes.count
            await reloadNotes()
            if notes.count <= previous, await fetchOlderFromRelays(before: notes) { await reloadNotes() }
            if notes.count <= previous { canLoadMoreNotes = false }
        case .replies:
            guard canLoadMoreReplies else { return }
            repliesLimit += page
            let previous = replies.count
            await reloadNotes()
            if replies.count <= previous, await fetchOlderFromRelays(before: replies) { await reloadNotes() }
            if replies.count <= previous { canLoadMoreReplies = false }
        case .likes:
            guard canLoadMoreLikes else { return }
            let oldest = await ProfileDataSource.oldestReactionTimestamp(pubkey, reactionLimit: reactionLimit)
            reactionLimit += page * 3
            let localIds = await ProfileDataSource.likedNoteIds(pubkey, reactionLimit: reactionLimit)
            if localIds.count < reactionLimit, await ProfileDataSource.syncOlderReactions(pubkey, before: oldest) == 0 {
                likesExhausted = true
            }
            await reloadLikes()
        }
    }

    var canLoadMoreCurrent: Bool {
        switch tab {
        case .notes, .photos: canLoadMoreNotes
        case .replies: canLoadMoreReplies
        case .likes: canLoadMoreLikes
        }
    }

    private func preloadAuthors(_ notes: [Note]) {
        let pubkeys = Array(Set(notes.flatMap { [$0.pubkey, $0.repostedBy ?? ""] }.filter { !$0.isEmpty && ProfileCache.shared.profile($0) == nil }))
        guard !pubkeys.isEmpty else { return }
        Task { await ProfileCache.shared.load(pubkeys) }
    }
}
