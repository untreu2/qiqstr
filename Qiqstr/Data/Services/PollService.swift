import Foundation
import Observation
import QiqstrCore

nonisolated struct NotePoll: Hashable, Sendable {
    struct Option: Hashable, Sendable, Identifiable {
        var id: String
        var label: String
    }

    static let kind: UInt16 = 1068
    static let responseKind: UInt16 = 1018

    var id: String
    var options: [Option]
    var multiple: Bool
    var endsAt: Int?
    var relays: [String]

    init?(id: String, tags: [[String]]) {
        var options: [Option] = []
        for tag in tags where tag.count > 2 && tag[0] == "option" && !tag[1].isEmpty && !options.contains(where: { $0.id == tag[1] }) {
            options.append(Option(id: tag[1], label: tag[2]))
        }
        guard options.count >= 2 else { return nil }
        self.id = id
        self.options = options
        let type = tags.first { $0.count > 1 && $0[0] == "polltype" }?[1].lowercased() ?? ""
        multiple = type.hasPrefix("multiple")
        endsAt = tags.first { $0.count > 1 && $0[0] == "endsAt" }.flatMap { Int($0[1]) }
        relays = tags.filter { $0.count > 1 && $0[0] == "relay" && $0[1].hasPrefix("wss://") }.map { $0[1] }
    }

    func isEnded(now: Int = TimeFormat.now) -> Bool {
        guard let endsAt else { return false }
        return now >= endsAt
    }
}

nonisolated struct PollTally: Equatable, Sendable {
    var counts: [String: Int] = [:]
    var voters = 0
    var mine: Set<String> = []

    func share(_ optionId: String) -> Double {
        guard voters > 0 else { return 0 }
        return Double(counts[optionId] ?? 0) / Double(voters)
    }
}

@MainActor
@Observable
final class PollService {
    static let shared = PollService()

    private(set) var tallies: [String: PollTally] = [:]
    private(set) var invalid: Set<String> = []
    @ObservationIgnored private var fetchedAt: [String: Date] = [:]

    func tally(_ pollId: String) -> PollTally? { tallies[pollId] }

    func load(_ poll: NotePoll, force: Bool = false) async {
        if let raw = try? await dbGetEvent(eventId: poll.id), let event = JSON.object(raw), event.int("kind") != Int(NotePoll.kind) {
            invalid.insert(poll.id)
            return
        }
        await recount(poll)
        if !force, let last = fetchedAt[poll.id], Date().timeIntervalSince(last) < 60 { return }
        fetchedAt[poll.id] = Date()
        let filter: JSONObject = ["kinds": [Int(NotePoll.responseKind)], "#e": [poll.id], "limit": 1000]
        var events: [JSONObject]
        if poll.relays.isEmpty {
            events = await SyncService.shared.fetchEvents(filter, timeout: 8)
        } else {
            async let hinted = fetchEventsFromRelays(filterJson: JSON.string(filter), relayUrls: poll.relays, timeoutSecs: 8)
            async let general = SyncService.shared.fetchEvents(filter, timeout: 8)
            events = JSON.array(try? await hinted) + (await general)
        }
        if !events.isEmpty { _ = try? await dbSaveEvents(eventsJson: JSON.string(events)) }
        await recount(poll)
    }

    private func recount(_ poll: NotePoll) async {
        let filter = JSON.string(["kinds": [Int(NotePoll.responseKind)], "#e": [poll.id]])
        let events = JSON.array(try? await dbQueryEvents(filterJson: filter, limit: 5000))
        tallies[poll.id] = Self.count(events, poll: poll, me: Session.shared.pubkey)
    }

    func vote(_ poll: NotePoll, optionIds: [String]) async throws {
        let ids = poll.multiple ? optionIds : Array(optionIds.prefix(1))
        guard !ids.isEmpty, !poll.isEnded() else { return }
        try await InteractionService.shared.publishPollResponse(pollId: poll.id, optionIds: ids, relays: poll.relays)
        await recount(poll)
    }

    static func count(_ events: [JSONObject], poll: NotePoll, me: String?) -> PollTally {
        let valid = Set(poll.options.map(\.id))
        var latest: [String: (createdAt: Int, choices: [String])] = [:]
        for event in events {
            guard event.int("kind") == Int(NotePoll.responseKind), let author = event.str("pubkey") else { continue }
            let createdAt = event.int("created_at")
            if let endsAt = poll.endsAt, createdAt > endsAt { continue }
            if let existing = latest[author], existing.createdAt >= createdAt { continue }
            var choices: [String] = []
            for tag in event.tags() where tag.count > 1 && tag[0] == "response" && valid.contains(tag[1]) && !choices.contains(tag[1]) {
                choices.append(tag[1])
            }
            if !poll.multiple { choices = Array(choices.prefix(1)) }
            guard !choices.isEmpty else { continue }
            latest[author] = (createdAt, choices)
        }
        var tally = PollTally()
        for (author, entry) in latest {
            tally.voters += 1
            for choice in entry.choices { tally.counts[choice, default: 0] += 1 }
            if author == me { tally.mine = Set(entry.choices) }
        }
        return tally
    }
}
