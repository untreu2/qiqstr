import Foundation

@MainActor
enum ServiceRegistry {
    private static var registered = false

    static func register() {
        guard !registered else { return }
        registered = true
        SessionHooks.onTeardown {
            FollowService.shared.reset()
            MuteService.shared.reset()
            BookmarkService.shared.reset()
            PinnedNotesService.shared.reset()
            DMService.shared.reset()
            WalletService.shared.reset()
            FollowSetService.shared.reset()
            HashtagFollowService.shared.reset()
            WebOfTrustService.shared.reset()
            Router.shared.reset()
            LiveService.shared.reset()
            ReadOnlyGate.shared.reset()
        }
        SessionHooks.onBootstrap { pubkey in
            async let follows: Void = FollowService.shared.load()
            async let mutes: Void = MuteService.shared.load()
            async let bookmarks: Void = BookmarkService.shared.load()
            async let pinned = PinnedNotesService.shared.load(for: pubkey)
            async let sets: Void = FollowSetService.shared.load()
            _ = await (follows, mutes, bookmarks, pinned, sets)
            Session.shared.mutedPubkeys = MuteService.shared.mutedPubkeys
            Session.shared.mutedWords = MuteService.shared.mutedWords
            Task { await DMService.shared.start() }
            Task { await WalletService.shared.load() }
            Task { await HashtagFollowService.shared.load() }
            Task { await WebOfTrustService.shared.load(for: pubkey) }
        }
    }
}
