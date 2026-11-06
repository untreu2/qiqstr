import Foundation
import Observation
import QiqstrCore

@MainActor
enum UserSearchService {
    static func pubkey(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let stripped = trimmed.replacingOccurrences(of: "https://njump.me/", with: "")
        if let hex = Nip19.pubkeyHex(from: stripped) { return hex }
        if let tlv = Nip19.decodeTLV(stripped), tlv.str("type") == "nprofile" { return tlv.str("pubkey") }
        return nil
    }

    static func local(_ query: String, limit: Int = 30) async -> [Profile] {
        JSON.array(try? await dbSearchProfiles(query: query, limit: UInt32(limit))).map { Profile(json: $0) }.filter { !$0.pubkey.isEmpty }
    }

    static func suggestions(limit: Int = 25) async -> [Profile] {
        let me = Session.shared.pubkey
        return JSON.array(try? await dbGetRandomProfiles(limit: UInt32(limit))).map { Profile(json: $0) }.filter { !$0.pubkey.isEmpty && $0.pubkey != me }
    }

    static func profile(for pubkey: String) async -> Profile {
        let cache = ProfileCache.shared
        await cache.refresh(pubkey)
        if cache.profile(pubkey) == nil {
            await SyncService.shared.syncProfile(pubkey, force: true)
            await cache.refresh(pubkey)
        }
        return cache.profile(pubkey) ?? Profile(pubkey: pubkey)
    }

    static func remote(_ query: String, limit: Int = 20) async -> [Profile] {
        guard let url = URL(string: RelayConfig.vertexRelayUrl) else { return [] }
        let socket = URLSession.shared.webSocketTask(with: url)
        socket.resume()
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(9))
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer {
            watchdog.cancel()
            socket.cancel(with: .normalClosure, reason: nil)
        }
        let subscription = "qs_\(Int(Date().timeIntervalSince1970 * 1000))"
        let request: [Any] = ["REQ", subscription, ["kinds": [0], "search": query, "limit": limit]]
        do { try await socket.send(.string(JSON.string(request))) } catch { return [] }
        var results: [Profile] = []
        var seen = Set<String>()
        while results.count < limit, !Task.isCancelled {
            guard let message = try? await socket.receive() else { break }
            guard case .string(let raw) = message, let frame = JSON.any(raw) as? [Any], let type = frame.first as? String else { continue }
            if type == "EOSE" || type == "CLOSED" { break }
            guard type == "EVENT", frame.count >= 3, let event = frame[2] as? JSONObject, event.int("kind") == 0,
                  let pubkey = event.str("pubkey"), seen.insert(pubkey).inserted,
                  let metadata = JSON.object(event["content"] as? String) else { continue }
            var profile = Profile(json: metadata, fallbackPubkey: pubkey)
            profile.pubkey = pubkey
            results.append(profile)
        }
        try? await socket.send(.string(JSON.string(["CLOSE", subscription])))
        return results
    }
}

@MainActor
@Observable
final class UserSearchModel {
    var query = "" { didSet { if query != oldValue { schedule() } } }
    private(set) var results: [Profile] = []
    private(set) var suggestions: [Profile] = []
    private(set) var resolvedPubkey: String?
    private(set) var isSearching = false
    private(set) var hasSearched = false
    var includesRemote = true
    var resultLimit = 40

    private var task: Task<Void, Never>?

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    func loadSuggestions() async {
        guard suggestions.isEmpty else { return }
        suggestions = await UserSearchService.suggestions()
    }

    func retry() { schedule(debounce: false) }

    func clear() {
        task?.cancel()
        query = ""
        results = []
        resolvedPubkey = nil
        isSearching = false
        hasSearched = false
    }

    private func schedule(debounce: Bool = true) {
        task?.cancel()
        let text = trimmedQuery
        guard !text.isEmpty else {
            results = []
            resolvedPubkey = nil
            isSearching = false
            hasSearched = false
            return
        }
        isSearching = true
        task = Task { [weak self] in
            if debounce { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await self?.run(text)
        }
    }

    private func run(_ text: String) async {
        if let pubkey = UserSearchService.pubkey(from: text) {
            resolvedPubkey = pubkey
            let profile = await UserSearchService.profile(for: pubkey)
            guard !Task.isCancelled else { return }
            results = [profile]
            finish()
            return
        }
        resolvedPubkey = nil
        let local = await UserSearchService.local(text, limit: resultLimit)
        guard !Task.isCancelled else { return }
        results = local
        hasSearched = true
        guard includesRemote else { finish(); return }
        let remote = await UserSearchService.remote(text)
        guard !Task.isCancelled else { return }
        var seen = Set(results.map(\.pubkey))
        let extra = remote.filter { seen.insert($0.pubkey).inserted }
        for profile in extra where ProfileCache.shared.profile(profile.pubkey) == nil { ProfileCache.shared.set(profile) }
        results = Array((results + extra).prefix(resultLimit))
        finish()
    }

    private func finish() {
        isSearching = false
        hasSearched = true
    }
}
