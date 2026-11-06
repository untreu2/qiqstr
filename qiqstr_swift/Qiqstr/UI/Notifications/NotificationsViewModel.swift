import Foundation
import Observation
import QiqstrCore

enum NotificationFilter: String, CaseIterable, Identifiable {
    case all, replies, reactions, reposts, zaps
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L("notificationFilterAll")
        case .replies: L("notificationFilterReplies")
        case .reactions: L("reactions")
        case .reposts: L("reposts")
        case .zaps: L("zaps")
        }
    }

    func includes(_ kind: NotificationKind) -> Bool {
        switch self {
        case .all: true
        case .replies: kind == .reply || kind == .mention || kind == .quote
        case .reactions: kind == .reaction
        case .reposts: kind == .repost
        case .zaps: kind == .zap
        }
    }
}

struct NotificationGroup: Identifiable, Hashable {
    var id: String
    var kind: NotificationKind
    var items: [NotificationItem]
    var authors: [String]
    var targetNoteId: String?
    var createdAt: Int
    var totalZapAmount: Int

    var lead: NotificationItem { items[0] }
    var isGrouped: Bool { items.count > 1 }

    var focusedNoteId: String? {
        switch kind {
        case .reply, .mention, .quote: lead.id.nilIfEmpty ?? targetNoteId
        default: targetNoteId ?? lead.id.nilIfEmpty
        }
    }
}

@MainActor
@Observable
final class NotificationsViewModel {
    private(set) var live: [NotificationItem] = []
    private(set) var older: [NotificationItem] = []
    private(set) var isLoaded = false
    private(set) var isLoadingMore = false
    private(set) var hasReachedEnd = false
    private(set) var errorMessage: String?
    private(set) var lastSeen = 0
    var filter: NotificationFilter = .all
    var onlyTrusted = true {
        didSet { if onlyTrusted != oldValue { revealsHidden = false } }
    }
    var revealsHidden = false

    private var olderIds: Set<String> = []
    private var didInitialSync = false
    private static let liveLimit: UInt32 = 200
    private static let pageSize: UInt32 = 100

    private var me: String? { Session.shared.pubkey }

    var all: [NotificationItem] {
        let liveIds = Set(live.map(\.id))
        let merged = live + older.filter { !liveIds.contains($0.id) }
        return merged
            .filter { $0.fromPubkey != me && $0.kind != .unknown }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var visible: (groups: [NotificationGroup], hidden: Int) {
        let items = all.filter { filter.includes($0.kind) }
        guard onlyTrusted, !revealsHidden, WebOfTrustService.shared.isReady else { return (Self.group(items), 0) }
        let trust = WebOfTrustService.shared
        let trusted = items.filter { trust.isTrusted($0.fromPubkey) }
        return (Self.group(trusted), items.count - trusted.count)
    }

    var groups: [NotificationGroup] { visible.groups }

    func revealHidden() {
        revealsHidden = true
    }

    func isUnread(_ group: NotificationGroup) -> Bool {
        lastSeen > 0 && group.createdAt > lastSeen
    }

    func markSeen() {
        guard let me else { return }
        let key = "notif_last_seen_\(me)"
        lastSeen = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(TimeFormat.now, forKey: key)
    }

    func reload() async {
        guard let me else { return }
        do {
            let raw = try await dbGetHydratedNotifications(userPubkeyHex: me, limit: Self.liveLimit, mutedPubkeys: Session.shared.mutedPubkeys, mutedWords: Session.shared.mutedWords)
            guard me == self.me else { return }
            live = JSON.array(raw).map(NotificationItem.init(json:))
            errorMessage = nil
        } catch {
            if !isLoaded { errorMessage = coreErrorMessage(error) }
        }
        isLoaded = true
        await ProfileCache.shared.load(Array(Set(all.map(\.fromPubkey))))
        if !didInitialSync {
            didInitialSync = true
            Task { await SyncService.shared.syncNotifications() }
        }
    }

    func refresh() async {
        await SyncService.shared.syncNotifications(force: true)
        await reload()
    }

    func loadMoreIfNeeded(_ group: NotificationGroup) async {
        guard let last = groups.last, last.id == group.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard let me, isLoaded, !isLoadingMore, !hasReachedEnd else { return }
        guard let oldest = all.last?.createdAt, oldest > 0 else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        var added = await appendOlder(before: oldest)
        var remoteCount = 0
        if !added {
            remoteCount = await SyncService.shared.syncOlderNotifications(before: oldest)
            guard me == self.me else { return }
            added = await appendOlder(before: oldest)
        }
        if !added && remoteCount == 0 { hasReachedEnd = true }
    }

    private func appendOlder(before timestamp: Int) async -> Bool {
        guard let me else { return false }
        let raw = try? await dbGetHydratedNotificationsBefore(userPubkeyHex: me, beforeTimestamp: UInt64(timestamp), limit: Self.pageSize, mutedPubkeys: Session.shared.mutedPubkeys, mutedWords: Session.shared.mutedWords)
        guard me == self.me else { return false }
        var added = false
        for item in JSON.array(raw).map(NotificationItem.init(json:)) where !item.id.isEmpty {
            if olderIds.insert(item.id).inserted {
                older.append(item)
                added = true
            }
        }
        if added { await ProfileCache.shared.load(Array(Set(older.map(\.fromPubkey)))) }
        return added
    }

    func mute(_ pubkey: String) async {
        do {
            try await MuteService.shared.mute(pubkey)
            ToastCenter.shared.show(L("userMuted"), style: .success)
        } catch {
            ToastCenter.shared.error(error)
        }
    }

    static func group(_ items: [NotificationItem]) -> [NotificationGroup] {
        let groupable: Set<NotificationKind> = [.reaction, .repost, .zap]
        var order: [(key: String, index: Int)] = []
        var buckets: [String: [NotificationItem]] = [:]
        var singles: [(NotificationItem, Int)] = []
        for (i, item) in items.enumerated() {
            if groupable.contains(item.kind), let target = item.targetNoteId, !target.isEmpty {
                let key = "\(item.kind.rawValue):\(target)"
                if buckets[key] == nil { order.append((key, i)) }
                buckets[key, default: []].append(item)
            } else {
                singles.append((item, i))
            }
        }
        var result: [(NotificationGroup, Int)] = singles.map { (make([$0.0], id: $0.0.id), $0.1) }
        for entry in order {
            let bucket = (buckets[entry.key] ?? []).sorted { $0.createdAt > $1.createdAt }
            result.append((make(bucket, id: entry.key), entry.index))
        }
        return result.sorted { $0.1 < $1.1 }.map(\.0)
    }

    private static func make(_ items: [NotificationItem], id: String) -> NotificationGroup {
        var seen = Set<String>()
        let authors = items.map(\.fromPubkey).filter { !$0.isEmpty && seen.insert($0).inserted }
        return NotificationGroup(
            id: id,
            kind: items[0].kind,
            items: items,
            authors: authors,
            targetNoteId: items[0].targetNoteId,
            createdAt: items[0].createdAt,
            totalZapAmount: items.reduce(0) { $0 + $1.zapAmount }
        )
    }
}
