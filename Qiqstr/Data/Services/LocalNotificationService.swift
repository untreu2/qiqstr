import Foundation
import Observation
import UIKit
import UserNotifications
import QiqstrCore

enum LocalNotificationType: String, CaseIterable, Sendable {
    case replies, reactions, reposts, zaps, messages

    var key: String { "local_notifications_\(rawValue)" }
    var isEnabled: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

nonisolated struct NotificationPayload: Sendable {
    enum Destination: Sendable { case thread(String), chat(String?), notifications }

    var destination: Destination
    var account: String?

    init(destination: Destination, account: String?) {
        self.destination = destination
        self.account = account
    }

    init(userInfo: [AnyHashable: Any]) {
        account = userInfo["account"] as? String
        let id = userInfo["id"] as? String
        switch userInfo["route"] as? String {
        case "thread": destination = id.map { .thread($0) } ?? .notifications
        case "chat": destination = .chat(id)
        default: destination = .notifications
        }
    }

    var userInfo: [String: String] {
        var info: [String: String] = [:]
        if let account { info["account"] = account }
        switch destination {
        case .thread(let id): info["route"] = "thread"; info["id"] = id
        case .chat(let pubkey): info["route"] = "chat"; info["id"] = pubkey
        case .notifications: info["route"] = "notifications"
        }
        return info
    }
}

private struct ActivityItem {
    enum Kind { case reply, mention, reaction, repost, zap }

    var id: String
    var kind: Kind
    var actor: String
    var target: String?
    var content: String
    var createdAt: Int
    var sats: Int

    var type: LocalNotificationType {
        switch kind {
        case .reply, .mention: .replies
        case .reaction: .reactions
        case .repost: .reposts
        case .zap: .zaps
        }
    }

    init?(event: JSONObject, me: String) {
        guard let id = event.str("id") else { return nil }
        let tags = event.tags()
        let eventTags = tags.filter { $0.count > 1 && $0[0] == "e" }
        self.id = id
        createdAt = event.int("created_at")
        content = (event["content"] as? String) ?? ""
        actor = event.str("pubkey") ?? ""
        sats = 0
        switch event.int("kind") {
        case 1:
            let threadTags = eventTags.filter { $0.count < 4 || $0[3] != "mention" }
            kind = threadTags.isEmpty ? .mention : .reply
            target = (threadTags.first { $0.count > 3 && $0[3] == "root" } ?? threadTags.first)?[1]
        case 6:
            kind = .repost
            target = eventTags.first?[1]
        case 7:
            kind = .reaction
            target = eventTags.last?[1]
            if content.trimmingCharacters(in: .whitespaces) == "-" { return nil }
        case 9735:
            kind = .zap
            target = eventTags.first?[1]
            let request = JSON.object(tags.first { $0.count > 1 && $0[0] == "description" }?[1])
            guard let request, let sender = request.str("pubkey") else { return nil }
            actor = sender
            content = (request["content"] as? String) ?? ""
            let invoice = tags.first { $0.count > 1 && $0[0] == "bolt11" }?[1]
            let requested = (request.tags().first { $0.count > 1 && $0[0] == "amount" }?[1]).flatMap(Int.init) ?? 0
            sats = invoice.flatMap { Bolt11.decode($0)?.amountSats } ?? requested / 1000
        default:
            return nil
        }
        if actor.isEmpty || actor == me { return nil }
    }
}

@MainActor
@Observable
final class LocalNotificationService: NSObject {
    static let shared = LocalNotificationService()

    static let enabledKey = "local_notifications_enabled"
    static let promptedKey = "local_notifications_prompted"
    private static let badgeKey = "local_notifications_badge"
    private static let messagesThread = "messages"
    private static let seenLimit = 1500
    private static let overlap = 120
    private static let giftWrapWindow = 172_800

    var isEnabled: Bool = UserDefaults.standard.bool(forKey: LocalNotificationService.enabledKey) {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { BackgroundRefresh.schedule() } else { BackgroundRefresh.cancel() }
        }
    }
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var backgroundRefreshAvailable = true

    @ObservationIgnored private var pending: NotificationPayload?
    @ObservationIgnored private var seen: [String: Set<String>] = [:]
    @ObservationIgnored private var seenOrder: [String: [String]] = [:]
    @ObservationIgnored private var groups: [String: [String]] = [:]

    var isAuthorized: Bool { authorization == .authorized || authorization == .provisional || authorization == .ephemeral }
    var isDenied: Bool { authorization == .denied }
    var isDelivering: Bool { isEnabled && isAuthorized }
    var shouldOfferPrompt: Bool {
        !isEnabled && authorization == .notDetermined && !UserDefaults.standard.bool(forKey: Self.promptedKey)
    }

    private var center: UNUserNotificationCenter { .current() }

    func activate() {
        center.delegate = self
        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        authorization = await center.notificationSettings().authorizationStatus
        backgroundRefreshAvailable = UIApplication.shared.backgroundRefreshStatus == .available
        if isEnabled, authorization == .denied { BackgroundRefresh.cancel() }
    }

    @discardableResult
    func enable() async -> Bool {
        UserDefaults.standard.set(true, forKey: Self.promptedKey)
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshStatus()
        isEnabled = granted
        if granted, let me = Session.shared.pubkey { setLastCheck(me, TimeFormat.now) }
        return granted
    }

    func dismissPrompt() {
        UserDefaults.standard.set(true, forKey: Self.promptedKey)
    }

    func sessionReady() async {
        await refreshStatus()
        if storedBadge > 0 { NotificationBadge.shared.markUnread() }
        await openPending()
    }

    func enteredBackground() {
        guard isEnabled, let me = Session.shared.pubkey else { return }
        setLastCheck(me, TimeFormat.now)
        persistSeen(me)
        BackgroundRefresh.schedule()
    }

    func clearBadge() {
        groups.removeAll()
        UserDefaults.standard.set(0, forKey: Self.badgeKey)
        center.setBadgeCount(0) { _ in }
        Task {
            let delivered = await center.deliveredNotifications()
            let ids = delivered.filter { $0.request.content.threadIdentifier != Self.messagesThread }.map(\.request.identifier)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    func clearMessages() {
        Task {
            let delivered = await center.deliveredNotifications()
            let ids = delivered.filter { $0.request.content.threadIdentifier == Self.messagesThread }.map(\.request.identifier)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    func handleRealtime(_ event: JSONObject, me: String) {
        guard let id = event.str("id") else { return }
        guard isEnabled, UIApplication.shared.applicationState == .background, let last = lastCheck(me) else {
            _ = insertSeen(id, me: me)
            return
        }
        Task { await deliver(events: [event], me: me, since: last - Self.overlap) }
    }

    func checkForNewActivity(me: String) async {
        guard isEnabled else { return }
        let now = TimeFormat.now
        guard let last = lastCheck(me) else {
            setLastCheck(me, now)
            return
        }
        let wantsActivity = LocalNotificationType.allCases.contains { $0 != .messages && $0.isEnabled }
        async let activity = wantsActivity ? fetchActivity(me: me, since: last - Self.overlap) : []
        async let wraps = fetchGiftWraps(me: me, since: last - Self.giftWrapWindow)
        async let mutes: Void = ensureMutesLoaded()
        async let trust: Void = WebOfTrustService.shared.load(for: me)
        let (events, giftWraps, _, _) = await (activity, wraps, mutes, trust)
        guard Session.shared.pubkey == me else { return }
        setLastCheck(me, now)
        await deliver(events: events, me: me, since: last - Self.overlap)
        await deliverMessages(giftWraps, me: me, since: last)
        persistSeen(me)
    }

    private func fetchActivity(me: String, since: Int) async -> [JSONObject] {
        let events = await SyncService.shared.fetchEvents(["kinds": [1, 6, 7, 9735], "#p": [me], "since": since, "limit": 200], timeout: 8)
        if !events.isEmpty {
            _ = try? await dbSaveEvents(eventsJson: JSON.string(events))
            DataBus.shared.notificationsChanged()
        }
        return events
    }

    private func fetchGiftWraps(me: String, since: Int) async -> [JSONObject] {
        guard LocalNotificationType.messages.isEnabled, Session.shared.canSign else { return [] }
        return await SyncService.shared.fetchEvents(["kinds": [1059], "#p": [me], "since": since, "limit": 100], timeout: 8)
    }

    private func ensureMutesLoaded() async {
        guard Session.shared.mutedPubkeys.isEmpty, !MuteService.shared.isLoaded else { return }
        await MuteService.shared.load()
    }

    private var mutedPubkeys: Set<String> {
        Set(Session.shared.mutedPubkeys).union(MuteService.shared.mutedPubkeys)
    }

    private var mutedWords: [String] {
        Array(Set(Session.shared.mutedWords).union(MuteService.shared.mutedWords)).map { $0.lowercased() }.filter { !$0.isEmpty }
    }

    private func accepts(_ pubkey: String, muted: Set<String>) -> Bool {
        if muted.contains(pubkey) { return false }
        return !WebOfTrustService.filtersNotifications || WebOfTrustService.shared.isTrusted(pubkey)
    }

    private func deliver(events: [JSONObject], me: String, since: Int) async {
        let muted = mutedPubkeys
        let words = mutedWords
        let items = events
            .compactMap { ActivityItem(event: $0, me: me) }
            .filter { item in
                guard item.createdAt > since, item.type.isEnabled, accepts(item.actor, muted: muted) else { return false }
                if item.kind == .reply || item.kind == .mention {
                    let text = item.content.lowercased()
                    if words.contains(where: text.contains) { return false }
                }
                return insertSeen(item.id, me: me)
            }
            .sorted { $0.createdAt < $1.createdAt }
        guard !items.isEmpty, Session.shared.pubkey == me else { return }

        let names = await displayNames(Array(Set(items.map(\.actor))))
        let targets = await noteSnippets(Array(Set(items.filter { $0.kind != .reply && $0.kind != .mention }.compactMap(\.target))))

        for item in items {
            switch item.kind {
            case .reply, .mention:
                let name = names[item.actor] ?? Profile.shortNpub(item.actor)
                let title = item.kind == .reply ? L("localNotifyReplied", ["name": name]) : L("localNotifyMentioned", ["name": name])
                await post(id: "activity-\(item.id)", title: title, body: Self.snippet(item.content), thread: "thread-\(item.target ?? item.id)", payload: NotificationPayload(destination: .thread(item.id), account: me))
            case .reaction, .repost:
                guard let target = item.target else { continue }
                let key = "\(item.kind == .reaction ? "reactions" : "reposts")-\(target)"
                var actors = groups[key] ?? []
                actors.removeAll { $0 == item.actor }
                actors.insert(item.actor, at: 0)
                groups[key] = actors
                let title = groupTitle(item, actors: actors, names: names)
                await post(id: key, title: title, body: targets[target] ?? "", thread: "thread-\(target)", payload: NotificationPayload(destination: .thread(target), account: me), silent: actors.count > 1)
            case .zap:
                let name = names[item.actor] ?? Profile.shortNpub(item.actor)
                let title = item.sats > 0
                    ? L("localNotifyZap", ["amount": item.sats.formatted(), "count": item.sats, "name": name])
                    : L("localNotifyZapNoAmount", ["name": name])
                let comment = Self.snippet(item.content)
                let body = comment.isEmpty ? (item.target.flatMap { targets[$0] } ?? "") : comment
                await post(id: "zap-\(item.id)", title: title, body: body, thread: "zaps", payload: NotificationPayload(destination: .notifications, account: me))
            }
        }
        let badge = storedBadge + items.count
        UserDefaults.standard.set(badge, forKey: Self.badgeKey)
        try? await center.setBadgeCount(badge)
        NotificationBadge.shared.markUnread()
    }

    private func deliverMessages(_ wraps: [JSONObject], me: String, since: Int) async {
        guard !wraps.isEmpty, let key = Session.shared.privateKey else { return }
        let fresh = wraps.filter { ($0.str("id")).map { !(seen[me]?.contains($0) ?? false) } ?? false }
        guard !fresh.isEmpty else { return }
        let raws = fresh.map { JSON.string($0) }
        let messages = await Task.detached(priority: .utility) {
            raws.compactMap { raw -> DMMessage? in
                (try? unwrapGiftWrapDm(receiverPrivateKeyHex: key, giftWrapJson: raw, currentUserPubkeyHex: me))
                    .flatMap(JSON.object)
                    .flatMap(DMMessage.init(json:))
            }
        }.value
        fresh.compactMap { $0.str("id") }.forEach { _ = insertSeen($0, me: me) }
        let muted = mutedPubkeys
        let incoming = messages.filter { !$0.isMine && $0.createdAt > since && accepts($0.sender, muted: muted) && insertSeen("dm-\($0.id)", me: me) }
        guard !incoming.isEmpty, Session.shared.pubkey == me else { return }
        let bySender = Dictionary(grouping: incoming, by: \.sender)
        let names = await displayNames(Array(bySender.keys))
        for (sender, list) in bySender {
            let name = names[sender] ?? Profile.shortNpub(sender)
            let body = list.count == 1 ? L("localNotifyNewMessage") : L("localNotifyNewMessages", ["count": list.count])
            await post(id: "chat-\(sender)", title: name, body: body, thread: Self.messagesThread, payload: NotificationPayload(destination: .chat(sender), account: me))
        }
        NotificationBadge.shared.hasUnreadMessages = true
    }

    private func groupTitle(_ item: ActivityItem, actors: [String], names: [String: String]) -> String {
        let first = names[actors[0]] ?? Profile.shortNpub(actors[0])
        let isReaction = item.kind == .reaction
        switch actors.count {
        case 1:
            let reaction = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if isReaction, !reaction.isEmpty, reaction != "+", !reaction.contains(":") {
                return L("localNotifyReacted", ["name": first, "reaction": reaction])
            }
            return L(isReaction ? "localNotifyLikedOne" : "localNotifyRepostedOne", ["name": first])
        case 2:
            let other = names[actors[1]] ?? Profile.shortNpub(actors[1])
            return L(isReaction ? "localNotifyLikedTwo" : "localNotifyRepostedTwo", ["name": first, "other": other])
        default:
            return L(isReaction ? "localNotifyLikedMany" : "localNotifyRepostedMany", ["count": actors.count])
        }
    }

    private func post(id: String, title: String, body: String, thread: String, payload: NotificationPayload, silent: Bool = false) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = thread
        content.userInfo = payload.userInfo
        content.sound = silent ? nil : .default
        content.relevanceScore = thread == Self.messagesThread ? 1 : 0.5
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    private func displayNames(_ pubkeys: [String]) async -> [String: String] {
        let cache = ProfileCache.shared
        await cache.load(pubkeys, fetchMissing: false)
        var names: [String: String] = [:]
        for pubkey in pubkeys {
            if let profile = cache.profile(pubkey) { names[pubkey] = profile.bestName }
        }
        let missing = pubkeys.filter { names[$0] == nil }
        guard !missing.isEmpty else { return names }
        let metadata = await SyncService.shared.fetchEvents(["kinds": [0], "authors": missing, "limit": missing.count * 2], timeout: 5)
        if !metadata.isEmpty { _ = try? await dbSaveEvents(eventsJson: JSON.string(metadata)) }
        for event in metadata.sorted(by: { $0.int("created_at") < $1.int("created_at") }) {
            guard let pubkey = event.str("pubkey"), let json = JSON.object(event.str("content")) else { continue }
            names[pubkey] = Profile(json: json, fallbackPubkey: pubkey).bestName
        }
        return names
    }

    private func noteSnippets(_ ids: [String]) async -> [String: String] {
        var snippets: [String: String] = [:]
        for id in ids {
            if let raw = try? await dbGetEvent(eventId: id), let event = JSON.object(raw) {
                snippets[id] = Self.snippet((event["content"] as? String) ?? "")
            }
        }
        let missing = ids.filter { snippets[$0] == nil }
        guard !missing.isEmpty else { return snippets }
        for event in await SyncService.shared.fetchEvents(["ids": missing, "limit": missing.count], timeout: 4) {
            guard let id = event.str("id") else { continue }
            snippets[id] = Self.snippet((event["content"] as? String) ?? "")
        }
        return snippets
    }

    private static func snippet(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: #"nostr:[a-z0-9]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"https?://\S+\.(jpe?g|png|gif|webp|heic|mp4|mov|webm)(\?\S*)?"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.count > 240 ? String(cleaned.prefix(239)) + "…" : cleaned
    }

    private var storedBadge: Int { UserDefaults.standard.integer(forKey: Self.badgeKey) }

    private func lastCheckKey(_ me: String) -> String { "local_notifications_last_\(me)" }
    private func seenKey(_ me: String) -> String { "local_notifications_seen_\(me)" }

    private func lastCheck(_ me: String) -> Int? {
        UserDefaults.standard.object(forKey: lastCheckKey(me)) as? Int
    }

    private func setLastCheck(_ me: String, _ value: Int) {
        UserDefaults.standard.set(max(value, lastCheck(me) ?? 0), forKey: lastCheckKey(me))
    }

    private func loadSeen(_ me: String) {
        guard seen[me] == nil else { return }
        let stored = UserDefaults.standard.stringArray(forKey: seenKey(me)) ?? []
        seenOrder[me] = stored
        seen[me] = Set(stored)
    }

    private func insertSeen(_ id: String, me: String) -> Bool {
        loadSeen(me)
        guard seen[me]?.insert(id).inserted == true else { return false }
        var order = seenOrder[me] ?? []
        order.append(id)
        if order.count > Self.seenLimit {
            let dropped = order.prefix(order.count - Self.seenLimit)
            seen[me]?.subtract(dropped)
            order.removeFirst(dropped.count)
        }
        seenOrder[me] = order
        return true
    }

    private func persistSeen(_ me: String) {
        guard let order = seenOrder[me] else { return }
        UserDefaults.standard.set(order, forKey: seenKey(me))
    }

    func open(_ payload: NotificationPayload) async {
        pending = payload
        await openPending()
    }

    private func openPending() async {
        guard let payload = pending, Session.shared.phase == .ready else { return }
        pending = nil
        let session = Session.shared
        if let account = payload.account, account != session.pubkey {
            guard let stored = session.accounts.first(where: { $0.pubkeyHex == account }) else { return }
            try? await session.switchAccount(stored.npub)
            guard session.phase == .ready, session.pubkey == account else { return }
        }
        let router = Router.shared
        router.sheet = nil
        router.showSidebar = false
        switch payload.destination {
        case .thread(let id):
            router.selectedTab = .notifications
            router.popToRoot(.notifications)
            router.push(.thread(id))
        case .chat(let pubkey):
            router.selectedTab = .dm
            router.popToRoot(.dm)
            if let pubkey { router.push(.dmChat(pubkey)) }
        case .notifications:
            router.selectedTab = .notifications
            router.popToRoot(.notifications)
        }
    }
}

extension LocalNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let payload = NotificationPayload(userInfo: response.notification.request.content.userInfo)
        Task { @MainActor in await LocalNotificationService.shared.open(payload) }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.list])
    }
}
