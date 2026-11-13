import Foundation
import QiqstrCore

final class SyncService {
    static let shared = SyncService()
    private var lastSync: [String: Date] = [:]
    private var profileRequests: [String: Date] = [:]
    private var feedTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var realtimeGeneration = 0
    private var feedLastEventTs: Int?
    private var notificationLastEventTs: Int?
    private let minInterval: TimeInterval = 30

    private var bus: DataBus { DataBus.shared }
    private var session: Session { Session.shared }

    func reset() {
        lastSync.removeAll()
        stopRealtime()
        feedLastEventTs = nil
        notificationLastEventTs = nil
    }

    private func shouldSync(_ key: String) -> Bool {
        guard let last = lastSync[key] else { return true }
        return Date().timeIntervalSince(last) > minInterval
    }

    private func since(_ key: String) -> Int? {
        lastSync[key].map { Int($0.timeIntervalSince1970) - 60 }
    }

    private func mark(_ key: String) {
        Task {
            guard await hasConnectedRelays() else { return }
            lastSync[key] = Date()
        }
    }

    func fetchEvents(_ filter: JSONObject, timeout: UInt32 = 10) async -> [JSONObject] {
        JSON.array(try? await QiqstrCore.fetchEvents(filterJson: JSON.string(filter), timeoutSecs: timeout))
    }

    private func fetchAndStore(_ filter: JSONObject) async -> [JSONObject] {
        let now = TimeFormat.now
        let sinceSecs = (filter["since"] as? Int) ?? (now - 86400 * 2)
        if now - sinceSecs <= 86400 {
            var syncFilter = filter
            syncFilter.removeValue(forKey: "limit")
            if let result = JSON.object(try? await syncEvents(filterJson: JSON.string(syncFilter))), result.int("received") > 0 {
                return []
            }
        }
        return await fetchEvents(filter)
    }

    func followingList(_ pubkey: String) async -> [String] {
        (try? await dbGetFollowingList(pubkeyHex: pubkey)) ?? []
    }

    func syncFeed(force: Bool = false) async {
        guard let me = session.pubkey else { return }
        let follows = Array(Set(await followingList(me) + [me])).sorted()
        let key = "feed_\(me)_\(follows.joined().hashValue)"
        guard force || shouldSync(key) else { return }
        let since = since(key) ?? (TimeFormat.now - 86400 * 2)
        async let notes = fetchAndStore(["authors": follows, "kinds": [1, 5, 6, 1068], "since": since, "limit": 100])
        async let articles = fetchAndStore(["kinds": [30023], "authors": follows, "since": since, "limit": 30])
        let (noteEvents, _) = await (notes, articles)
        _ = try? await dbProcessDeletionEvents()
        bus.feedChanged()
        queueMissingRepostOriginals(since)
        if !noteEvents.isEmpty {
            backgroundFollowUps(noteEvents)
        }
        mark(key)
    }

    func syncListFeed(_ pubkeys: [String], force: Bool = false) async {
        guard !pubkeys.isEmpty else { return }
        let key = "list_feed_\(pubkeys.sorted().joined().hashValue)"
        guard force || shouldSync(key) else { return }
        let since = since(key) ?? (TimeFormat.now - 86400 * 2)
        let events = await fetchAndStore(["authors": pubkeys, "kinds": [1, 5, 6, 1068], "since": since, "limit": 100])
        _ = try? await dbProcessDeletionEvents()
        bus.feedChanged()
        queueMissingRepostOriginals(since)
        if !events.isEmpty { backgroundFollowUps(events) }
        mark(key)
    }

    func syncProfile(_ pubkey: String, force: Bool = false) async {
        let key = "profile_\(pubkey)"
        guard force || shouldSync(key) else { return }
        _ = await fetchEvents(["kinds": [0], "authors": [pubkey], "limit": 1])
        bus.profileChanged()
        mark(key)
    }

    func syncProfiles(_ pubkeys: [String]) async {
        guard !pubkeys.isEmpty else { return }
        _ = await fetchEvents(["kinds": [0], "authors": pubkeys, "limit": pubkeys.count])
        bus.profileChanged()
    }

    func syncProfileNotes(_ pubkey: String, force: Bool = false) async {
        let key = "profile_notes_\(pubkey)"
        guard force || shouldSync(key) else { return }
        let sinceValue = Int64(since(key) ?? -1)
        var pubkeys: Set<String> = [pubkey]
        var repostIds: [String] = []
        var count = 0
        let stream = EventStream.make { sink in
            try await fetchProfileEvents(authorHex: pubkey, kindsStr: "1,5,6", sinceTimestamp: sinceValue, sink: sink)
        }
        do {
            for try await raw in stream {
                guard let event = JSON.object(raw) else { continue }
                if let pk = event.str("pubkey") { pubkeys.insert(pk) }
                if event.int("kind") == 6 {
                    for tag in event.tags() where tag.count > 1 {
                        if tag[0] == "e" { repostIds.append(tag[1]) }
                        if tag[0] == "p" { pubkeys.insert(tag[1]) }
                    }
                }
                count += 1
                if count == 1 || count % 50 == 0 { bus.feedChanged() }
            }
        } catch {}
        _ = try? await dbProcessDeletionEvents()
        bus.feedChanged()
        fetchMissingProfiles(Array(pubkeys))
        fetchRepostOriginals(repostIds)
        mark(key)
    }

    func syncProfileReactions(_ pubkey: String) async {
        let key = "profile_reactions_\(pubkey)"
        guard shouldSync(key) else { return }
        var filter: JSONObject = ["authors": [pubkey], "kinds": [7], "limit": 50]
        if let s = since(key) { filter["since"] = s }
        _ = await fetchEvents(filter)
        bus.interactionsChanged()
        mark(key)
    }

    func syncNotifications(force: Bool = false) async {
        guard let me = session.pubkey else { return }
        let key = "notifications_\(me)"
        guard force || shouldSync(key) else { return }
        let first = lastSync[key] == nil
        let sinceValue = since(key) ?? (TimeFormat.now - 86400 * 30)
        _ = await fetchAndStore(["#p": [me], "kinds": [1, 6, 7, 9735], "since": sinceValue, "limit": first ? 300 : 150])
        bus.notificationsChanged()
        if let missing = try? await dbGetNotificationsMissingProfiles(userPubkeyHex: me, limit: 200), !missing.isEmpty {
            await syncProfiles(missing)
            bus.notificationsChanged()
        }
        mark(key)
    }

    func syncOlderNotifications(before: Int) async -> Int {
        guard let me = session.pubkey, before > 0 else { return 0 }
        let sinceValue = max(0, before - 86400 * 90)
        let events = await fetchEvents(["#p": [me], "kinds": [1, 6, 7, 9735], "until": before - 1, "since": sinceValue, "limit": 100], timeout: 12)
        if !events.isEmpty {
            _ = try? await dbSaveEvents(eventsJson: JSON.string(events))
            bus.notificationsChanged()
            fetchMissingProfiles(Array(Set(events.compactMap { $0.str("pubkey") })))
        }
        return events.count
    }

    func syncFollowingList(_ pubkey: String, force: Bool = false) async {
        let key = "following_\(pubkey)"
        guard force || shouldSync(key) else { return }
        var events = await fetchEvents(["kinds": [3], "authors": [pubkey], "limit": 1])
        if events.isEmpty { events = await fetchIndexedContactLists(of: pubkey) }
        if let event = events.max(by: { $0.int("created_at") < $1.int("created_at") }) {
            try? await dbSaveFollowingListFromEvent(eventJson: JSON.string(event), selfPubkeyHex: pubkey)
        }
        if pubkey == session.pubkey { bus.feedChanged() }
        mark(key)
    }

    func hasConnectedRelays() async -> Bool {
        ((try? await getConnectedRelayCount()) ?? 0) > 0
    }

    func fetchContactLists(of pubkey: String) async -> [JSONObject] {
        await fetchReplaceable(kind: 3, author: pubkey)
    }

    func latestEditableEvent(kind: Int, author pubkey: String, dTag: String? = nil, allowingNew: Bool = false) async throws -> JSONObject? {
        var filter: JSONObject = ["kinds": [kind], "authors": [pubkey]]
        if let dTag { filter["#d"] = [dTag] }
        let cached = JSON.array(try? await dbQueryEvents(filterJson: JSON.string(filter), limit: 5))
        let remote = await fetchReplaceable(kind: kind, author: pubkey, dTag: dTag)
        let matches: (JSONObject) -> Bool = { event in
            event.int("kind") == kind && event.str("pubkey")?.lowercased() == pubkey.lowercased()
                && (dTag == nil || event.tags().contains { $0.count > 1 && $0[0] == "d" && $0[1] == dTag })
        }
        if remote.isEmpty {
            if !cached.filter(matches).isEmpty { throw CoreError(L("noRelayConnection")) }
            if ((try? await getConnectedRelayCount()) ?? 0) == 0 { throw CoreError(L("noRelayConnection")) }
            if allowingNew || Session.shared.isNewAccount || AccountStore.wasCreatedHere(pubkey) { return nil }
            guard await ListConfirmation.startNewList(kind: kind) else { throw ListError.cancelled }
            return nil
        }
        let newest = (cached + remote).filter(matches)
            .max { ($0.int("created_at"), $0.str("id") ?? "") < ($1.int("created_at"), $1.str("id") ?? "") }
        if let newest { _ = try? await dbSaveEvents(eventsJson: JSON.string([newest])) }
        return newest
    }

    func fetchReplaceable(kind: Int, author pubkey: String, dTag: String? = nil) async -> [JSONObject] {
        var query: JSONObject = ["kinds": [kind], "authors": [pubkey], "limit": 1]
        if let dTag { query["#d"] = [dTag] }
        let filterJson = JSON.string(query)
        let indexers = RelayConfig.indexerRelays
        async let pooled = JSON.array(try? await QiqstrCore.fetchEvents(filterJson: filterJson, timeoutSecs: 6))
        async let indexed = JSON.array(try? await fetchEventsFromRelays(filterJson: filterJson, relayUrls: indexers, timeoutSecs: 6))
        return (await pooled + indexed).filter { $0.int("kind") == kind && $0.str("pubkey")?.lowercased() == pubkey.lowercased() }
    }

    private func fetchIndexedContactLists(of pubkey: String) async -> [JSONObject] {
        let filter = JSON.string(["kinds": [3], "authors": [pubkey], "limit": 1] as JSONObject)
        return JSON.array(try? await fetchEventsFromRelays(filterJson: filter, relayUrls: RelayConfig.indexerRelays, timeoutSecs: 6))
    }

    func syncHashtag(_ tag: String, force: Bool = false) async {
        let key = "hashtag_\(tag)"
        guard force || shouldSync(key) else { return }
        let events = await fetchEvents(["kinds": [1], "#t": [tag.lowercased()], "limit": 100])
        if !events.isEmpty { backgroundFollowUps(events) }
        bus.feedChanged()
        mark(key)
    }

    func syncArticles(authors: [String]? = nil, force: Bool = false) async {
        let key = "articles_\(authors?.count ?? 0)"
        guard force || shouldSync(key) else { return }
        var filter: JSONObject = ["kinds": [30023], "limit": 50]
        if let authors { filter["authors"] = authors }
        let events = await fetchEvents(filter)
        fetchMissingProfiles(Array(Set(events.compactMap { $0.str("pubkey") })))
        bus.feedChanged()
        mark(key)
    }

    func syncNote(_ id: String) async {
        if (try? await dbEventExists(eventId: id)) == true { return }
        _ = try? await fetchEventById(eventId: id, timeoutSecs: 8)
        bus.feedChanged(ids: [id])
    }

    func syncInteractions(for noteIds: [String]) async {
        guard !noteIds.isEmpty else { return }
        _ = await fetchEvents(["#e": noteIds, "kinds": [1, 6, 7, 9735], "limit": 500], timeout: 8)
        bus.interactionsChanged()
    }

    func backgroundFollowUps(_ events: [JSONObject]) {
        let json = JSON.string(events)
        Task {
            if let pubkeys = try? extractPubkeysFromEvents(eventsJson: json) { fetchMissingProfiles(pubkeys) }
            if let ids = try? extractRepostOriginalIds(eventsJson: json) { fetchRepostOriginals(ids) }
            if var replyIds = try? filterReplyEventIds(eventsJson: json), !replyIds.isEmpty {
                replyIds = Array(replyIds.prefix(40))
                if let fetched = try? await fetchThreadAncestors(eventIds: replyIds), fetched > 0 { bus.feedChanged() }
            }
        }
    }

    func fetchMissingProfiles(_ pubkeys: [String]) {
        let now = Date()
        if profileRequests.count > 5_000 { profileRequests = profileRequests.filter { now.timeIntervalSince($0.value) < 600 } }
        let wanted = Array(Set(pubkeys.filter { !$0.isEmpty && profileRequests[$0].map { now.timeIntervalSince($0) >= 600 } ?? true }))
        guard !wanted.isEmpty else { return }
        for pubkey in wanted { profileRequests[pubkey] = now }
        let json = JSON.string(wanted.map { ["pubkey": $0] })
        Task {
            if let found = try? await fetchMissingProfilesForEvents(eventsJson: json), found > 0 {
                bus.profileChanged()
                bus.feedChanged()
            }
        }
    }

    func fetchRepostOriginals(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let json = JSON.string(Array(ids.prefix(50)))
        Task {
            if let n = try? await QiqstrCore.fetchRepostOriginals(repostEventIdsJson: json), n > 0 { bus.feedChanged() }
        }
    }

    private func queueMissingRepostOriginals(_ since: Int) {
        Task {
            if let missing = try? await QiqstrCore.queueMissingRepostOriginals(sinceTimestamp: Int64(since)) { fetchRepostOriginals(missing) }
        }
    }

    @discardableResult
    func publish(_ eventJson: String, to relays: [String]? = nil) async throws -> JSONObject {
        guard let event = JSON.object(eventJson) else { throw CoreError("Invalid event") }
        if let me = session.pubkey, event.str("pubkey") != me { throw CoreError("Event signer does not match the active account") }
        let raw: String
        do {
            if let relays { raw = try await sendEventTo(eventJson: eventJson, relayUrls: relays) } else { raw = try await sendEvent(eventJson: eventJson) }
        } catch {
            if coreErrorMessage(error).contains("No relay accepted") || coreErrorMessage(error).contains("No publication relays") {
                throw CoreError(L("publishNoRelayAccepted"))
            }
            throw error
        }
        let result = JSON.object(raw) ?? [:]
        let success = (result["success"] as? [Any]) ?? []
        if success.isEmpty {
            throw CoreError(L("publishNoRelayAccepted"))
        }
        _ = try? await dbSaveEvents(eventsJson: "[\(eventJson)]")
        bus.feedChanged(ids: [event.str("id") ?? ""])
        bus.interactionsChanged()
        return event
    }

    func startRealtime() {
        guard let me = session.pubkey else { return }
        stopRealtime()
        realtimeGeneration += 1
        let generation = realtimeGeneration
        feedTask = Task { await runFeedSubscription(me, generation: generation) }
        notificationTask = Task { await runNotificationSubscription(me, generation: generation) }
    }

    func stopRealtime() {
        realtimeGeneration += 1
        feedTask?.cancel(); feedTask = nil
        notificationTask?.cancel(); notificationTask = nil
    }

    private func runFeedSubscription(_ me: String, generation: Int) async {
        var attempts = 0
        while !Task.isCancelled, generation == realtimeGeneration {
            let follows = Array(Set(await followingList(me) + [me]))
            let since = feedLastEventTs.map { $0 - 1 } ?? (TimeFormat.now - 60)
            let filter = JSON.string(["kinds": [1, 5, 6, 1068], "authors": follows, "since": since])
            let stream = EventStream.make { sink in try await subscribeToEvents(filterJson: filter, sink: sink) }
            do {
                for try await raw in stream {
                    guard generation == realtimeGeneration, let event = JSON.object(raw) else { break }
                    attempts = 0
                    let created = event.int("created_at")
                    if created > (feedLastEventTs ?? 0) { feedLastEventTs = created }
                    let id = event.str("id") ?? ""
                    if !id.isEmpty, !isEventNewAndTrack(eventId: id) { continue }
                    _ = try? await dbSaveEvents(eventsJson: "[\(raw)]")
                    if event.int("kind") == 5 { _ = try? await dbProcessDeletionEvents() }
                    bus.feedChanged(ids: [id])
                    backgroundFollowUps([event])
                }
            } catch {}
            attempts += 1
            try? await Task.sleep(for: .seconds(min(30, 2 * attempts)))
        }
    }

    private func runNotificationSubscription(_ me: String, generation: Int) async {
        var attempts = 0
        while !Task.isCancelled, generation == realtimeGeneration {
            let since = notificationLastEventTs.map { $0 - 1 } ?? (TimeFormat.now - 60)
            let filter = JSON.string(["kinds": [1, 6, 7, 9735], "#p": [me], "since": since])
            let stream = EventStream.make { sink in try await subscribeToEvents(filterJson: filter, sink: sink) }
            do {
                for try await raw in stream {
                    guard generation == realtimeGeneration, let event = JSON.object(raw) else { break }
                    attempts = 0
                    let created = event.int("created_at")
                    if created > (notificationLastEventTs ?? 0) { notificationLastEventTs = created }
                    _ = try? await dbSaveEvents(eventsJson: "[\(raw)]")
                    if let from = event.str("pubkey"), from != me, LocalNotificationService.shared.shouldBadge(event, me: me) {
                        NotificationBadge.shared.markUnread(from: ProfileCache.shared.profile(from)?.bestName)
                    }
                    LocalNotificationService.shared.handleRealtime(event, me: me)
                    bus.notificationsChanged()
                    fetchMissingProfiles([event.str("pubkey") ?? ""].filter { !$0.isEmpty })
                }
            } catch {}
            attempts += 1
            try? await Task.sleep(for: .seconds(min(30, 2 * attempts)))
        }
    }
}
