import Foundation
import QiqstrCore

@MainActor
final class ExploreSafety {
    static let shared = ExploreSafety()

    private static let lifetime: TimeInterval = 1800
    private static let reportWindow: TimeInterval = 180 * 86_400
    private static let chunk = 150

    private var noteReporters: [String: Set<String>] = [:]
    private var authorReporters: [String: Set<String>] = [:]
    private var checkedAt: [String: Date] = [:]

    func reset() {
        noteReporters = [:]
        authorReporters = [:]
        checkedAt = [:]
    }

    func screen(_ notes: [Note]) async -> [Note] {
        let candidates = notes.filter { !ExploreService.isSensitive($0) }
        let trust = WebOfTrustService.shared
        let trusted = trust.isReady ? candidates.filter { note in
            trust.isTrusted(note.pubkey) && (note.repostedBy.map(trust.isTrusted) ?? true)
        } : candidates
        await loadReports(for: trusted)
        let authorLimit = trust.isReady ? 2 : 1
        return trusted.filter { note in
            if reporters(note: note.id) > 0 { return false }
            if reporters(author: note.pubkey) >= authorLimit { return false }
            if let reposter = note.repostedBy, reporters(author: reposter) >= authorLimit { return false }
            return true
        }
    }

    private func loadReports(noteIds: [String], authors: [String]) async {
        let now = Date()
        let isFresh: (String) -> Bool = { [checkedAt] key in
            checkedAt[key].map { now.timeIntervalSince($0) < Self.lifetime } ?? false
        }
        let ids = Array(Set(noteIds.filter { !isFresh("e:\($0)") }))
        let keys = Array(Set(authors.filter { !$0.isEmpty && !isFresh("p:\($0)") }))
        guard !ids.isEmpty || !keys.isEmpty else { return }
        let since = Int(now.timeIntervalSince1970 - Self.reportWindow)
        var filters: [JSONObject] = []
        for start in stride(from: 0, to: ids.count, by: Self.chunk) {
            filters.append(["kinds": [1984], "#e": Array(ids[start..<min(start + Self.chunk, ids.count)]), "since": since, "limit": 500])
        }
        for start in stride(from: 0, to: keys.count, by: Self.chunk) {
            filters.append(["kinds": [1984], "#p": Array(keys[start..<min(start + Self.chunk, keys.count)]), "since": since, "limit": 500])
        }
        guard let raw = try? await fetchEventsMultiFilter(filtersJson: JSON.string(filters), timeoutSecs: 5) else { return }
        ingest(JSON.array(raw), ids: Set(ids), authors: Set(keys))
        ids.forEach { checkedAt["e:\($0)"] = now }
        keys.forEach { checkedAt["p:\($0)"] = now }
    }

    private func loadReports(for notes: [Note]) async {
        var authors = notes.map(\.pubkey)
        authors += notes.compactMap(\.repostedBy)
        await loadReports(noteIds: notes.map(\.id), authors: authors)
    }

    private func ingest(_ events: [JSONObject], ids: Set<String>, authors: Set<String>) {
        let me = Session.shared.pubkey
        let muted = Set(Session.shared.mutedPubkeys)
        for event in events where event.int("kind") == 1984 {
            guard let reporter = event.str("pubkey"), reporter != me, !muted.contains(reporter) else { continue }
            for tag in event.tags() where tag.count > 1 {
                if tag[0] == "e", ids.contains(tag[1]) {
                    noteReporters[tag[1], default: []].insert(reporter)
                } else if tag[0] == "p", authors.contains(tag[1]), tag[1] != reporter {
                    authorReporters[tag[1], default: []].insert(reporter)
                }
            }
        }
    }

    private func reporters(note id: String) -> Int { noteReporters[id]?.count ?? 0 }
    private func reporters(author pubkey: String) -> Int { authorReporters[pubkey]?.count ?? 0 }
}
