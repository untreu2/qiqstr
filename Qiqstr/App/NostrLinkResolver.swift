import Foundation
import QiqstrCore

@MainActor
enum NostrLinkResolver {
    static func open(_ link: NostrLink, router: Router) {
        switch link {
        case .profile(let entity):
            guard let pubkey = Nip19.pubkeyHex(from: entity) else { return }
            router.push(.profile(pubkey))
            let relays = hintRelays(entity)
            guard !relays.isEmpty else { return }
            Task { await prefetchProfile(pubkey, relays: relays) }
        case .event(let entity):
            guard let id = Nip19.decode(entity) else { return }
            let relays = hintRelays(entity)
            Task {
                let kind = await locateEvent(id, relays: relays)
                router.push(kind == 30023 ? .article(id) : .thread(id))
            }
        case .address(let entity):
            let kind = Nip19.decodeTLV(entity)?["kind"] as? Int
            if kind == nil || kind == 30023 || kind == 30024 {
                router.push(.articleAddress(entity))
            } else if let url = URL(string: "https://njump.me/\(entity)") {
                router.sheet = .url(url)
            }
        }
    }

    private static func hintRelays(_ entity: String) -> [String] {
        let relays = (Nip19.decodeTLV(entity)?["relays"] as? [String]) ?? []
        return Array(Set(relays.filter { $0.hasPrefix("wss://") || $0.hasPrefix("ws://") }).prefix(5))
    }

    private static func locateEvent(_ id: String, relays: [String]) async -> Int? {
        if let raw = try? await dbGetEvent(eventId: id), let local = JSON.object(raw) {
            return local["kind"] as? Int
        }
        guard !relays.isEmpty else { return nil }
        let filter = JSON.string(["ids": [id], "limit": 1])
        guard let raw = try? await fetchEventsFromRelays(filterJson: filter, relayUrls: relays, timeoutSecs: 4) else { return nil }
        _ = try? await dbSaveEvents(eventsJson: raw)
        return JSON.array(raw).first?["kind"] as? Int
    }

    private static func prefetchProfile(_ pubkey: String, relays: [String]) async {
        let existing = try? await dbGetProfile(pubkeyHex: pubkey)
        guard existing == nil else { return }
        let filter = JSON.string(["kinds": [0], "authors": [pubkey], "limit": 1])
        guard let raw = try? await fetchEventsFromRelays(filterJson: filter, relayUrls: relays, timeoutSecs: 5),
              let saved = try? await dbSaveEvents(eventsJson: raw), saved > 0 else { return }
        await ProfileCache.shared.refresh(pubkey)
        DataBus.shared.profileChanged()
    }
}
