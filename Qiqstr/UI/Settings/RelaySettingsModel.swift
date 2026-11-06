import Foundation
import Observation
import QiqstrCore

struct SettingsRelayFlags: Codable, Hashable {
    var read = true
    var write = true
}

struct SettingsRelayStatus: Hashable {
    var status: String
    var latencyMs: Int
    var bytesSent: Int
    var bytesReceived: Int
}

@MainActor
@Observable
final class RelaySettingsModel {
    private(set) var relays: [String] = []
    private(set) var flags: [String: SettingsRelayFlags] = [:]
    private(set) var statuses: [String: SettingsRelayStatus] = [:]
    private(set) var connectedCount = 0
    private(set) var totalCount = 0
    private(set) var isPublishing = false
    private(set) var isFetching = false
    private(set) var broadcastProgress: (sent: Int, total: Int)?
    var gossipMode: GossipMode = RelayConfig.gossipMode {
        didSet {
            guard gossipMode != oldValue else { return }
            RelayConfig.gossipMode = gossipMode
            ToastCenter.shared.show(L("settingsGossipRestart"))
        }
    }
    var showAdd = false
    var newRelayURL = ""
    var showResetConfirm = false
    var pendingBroadcast: [String] = []
    var showBroadcastPrompt = false
    var feedback = 0

    private var statusTask: Task<Void, Never>?
    private static let flagsKey = "relay_flags"

    var totalBytes: Int { statuses.values.reduce(0) { $0 + $1.bytesSent + $1.bytesReceived } }

    func load() {
        relays = RelayConfig.mainRelays
        var stored = Self.storedFlags()
        for relay in relays where stored[relay] == nil { stored[relay] = SettingsRelayFlags() }
        flags = stored
    }

    func startStatus() {
        statusTask?.cancel()
        statusTask = Task {
            while !Task.isCancelled {
                let stream = EventStream.make { sink in try await streamRelayStatus(sink: sink) }
                do {
                    for try await raw in stream {
                        guard !Task.isCancelled else { return }
                        apply(raw)
                    }
                } catch {}
                if let raw = try? await getRelayStatus() { apply(raw) }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopStatus() {
        statusTask?.cancel()
        statusTask = nil
    }

    private func apply(_ raw: String) {
        guard let json = JSON.object(raw) else { return }
        let summary = (json["summary"] as? JSONObject) ?? [:]
        var next: [String: SettingsRelayStatus] = [:]
        for relay in (json["relays"] as? [JSONObject]) ?? [] {
            guard let url = relay.str("url") else { continue }
            next[Self.normalize(url)] = SettingsRelayStatus(
                status: relay.str("status") ?? "disconnected",
                latencyMs: relay.int("latencyMs"),
                bytesSent: relay.int("bytesSent"),
                bytesReceived: relay.int("bytesReceived")
            )
        }
        if next != statuses { statuses = next }
        connectedCount = summary.int("connectedRelays")
        totalCount = summary.int("totalRelays")
    }

    func status(for relay: String) -> SettingsRelayStatus? { statuses[Self.normalize(relay)] }

    func flags(for relay: String) -> SettingsRelayFlags { flags[relay] ?? SettingsRelayFlags() }

    func add() async {
        let url = newRelayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { ToastCenter.shared.show(L("pleaseEnterRelayUrl"), style: .error); return }
        guard Self.isValid(url) else { ToastCenter.shared.show(L("invalidRelayUrl"), style: .error); return }
        let normalized = Self.normalize(url)
        guard !relays.contains(where: { Self.normalize($0) == normalized }) else {
            ToastCenter.shared.show(L("relayAlreadyExistsInCategory"), style: .error)
            return
        }
        newRelayURL = ""
        showAdd = false
        relays.append(normalized)
        flags[normalized] = SettingsRelayFlags()
        persist()
        do {
            _ = try await addRelay(url: normalized)
            Task.detached { try? await connectRelays() }
            feedback += 1
            ToastCenter.shared.show(L("relayAddedToMainList"), style: .success)
            offerBroadcast([normalized])
        } catch {
            ToastCenter.shared.show("\(L("errorAddingRelay")): \(coreErrorMessage(error))", style: .error)
        }
    }

    func remove(_ relay: String) async {
        relays.removeAll { $0 == relay }
        flags[relay] = nil
        persist()
        try? await removeRelay(url: relay)
        feedback += 1
        ToastCenter.shared.show(L("relayRemovedSuccessfully"), style: .success)
    }

    func move(from source: IndexSet, to destination: Int) {
        relays.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func setFlags(_ relay: String, read: Bool, write: Bool) async {
        guard read || write else { return }
        flags[relay] = SettingsRelayFlags(read: read, write: write)
        persist()
        _ = try? await addRelayWithFlags(url: relay, read: read, write: write)
    }

    func resetToDefaults() async {
        let previous = Set(relays.map(Self.normalize))
        let defaults = RelayConfig.defaultMainRelays
        for relay in relays where !defaults.contains(where: { Self.normalize($0) == Self.normalize(relay) }) {
            try? await removeRelay(url: relay)
        }
        RelayConfig.resetRelays()
        relays = defaults
        flags = Dictionary(uniqueKeysWithValues: defaults.map { ($0, SettingsRelayFlags()) })
        persist()
        for relay in defaults { _ = try? await addRelayWithFlags(url: relay, read: true, write: true) }
        Task.detached { try? await connectRelays() }
        feedback += 1
        ToastCenter.shared.show(L("relaysResetToDefaults"), style: .success)
        offerBroadcast(defaults.filter { !previous.contains(Self.normalize($0)) })
    }

    func publish() async {
        guard let key = Session.shared.privateKey else { ToastCenter.shared.show(L("privateKeyNotFound"), style: .error); return }
        isPublishing = true
        defer { isPublishing = false }
        let configs: [String] = relays.compactMap { relay in
            let f = flags(for: relay)
            if f.read && f.write { return relay }
            if f.read { return "\(relay)|read" }
            if f.write { return "\(relay)|write" }
            return nil
        }
        do {
            let event = try createRelayListEventWithMarkers(relayConfigs: configs, privateKeyHex: key)
            try await SyncService.shared.publish(event)
            UserDefaults.standard.set(event, forKey: "published_relay_list")
            feedback += 1
            ToastCenter.shared.show("\(L("relayListPublishedSuccessfully")) (\(configs.count))", style: .success)
        } catch {
            ToastCenter.shared.show("\(L("errorPublishingRelayList")): \(coreErrorMessage(error))", style: .error)
        }
    }

    func fetchFromProfile() async {
        guard let me = Session.shared.pubkey else { return }
        isFetching = true
        defer { isFetching = false }
        let events = await SyncService.shared.fetchEvents(["authors": [me], "kinds": [10002], "limit": 1])
        guard let event = events.max(by: { $0.int("created_at") < $1.int("created_at") }) else {
            ToastCenter.shared.show(L("noRelayListFoundInYourProfile"))
            return
        }
        var urls: [String] = []
        var newFlags: [String: SettingsRelayFlags] = [:]
        for tag in event.tags() where tag.count >= 2 && tag[0] == "r" && Self.isValid(tag[1]) {
            let url = Self.normalize(tag[1])
            guard !urls.contains(url) else { continue }
            let marker = tag.count >= 3 ? tag[2] : ""
            urls.append(url)
            newFlags[url] = marker == "read" ? SettingsRelayFlags(read: true, write: false) : marker == "write" ? SettingsRelayFlags(read: false, write: true) : SettingsRelayFlags()
        }
        guard !urls.isEmpty else {
            ToastCenter.shared.show(L("noRelayListFoundInYourProfile"))
            return
        }
        UserDefaults.standard.set(JSON.string(urls.map { ["url": $0, "marker": newFlags[$0]?.marker ?? ""] }), forKey: "user_relays")
        let previous = Set(relays.map(Self.normalize))
        for relay in relays where !urls.contains(Self.normalize(relay)) { try? await removeRelay(url: relay) }
        relays = urls
        flags = newFlags
        persist()
        for url in urls {
            let f = newFlags[url] ?? SettingsRelayFlags()
            _ = try? await addRelayWithFlags(url: url, read: f.read, write: f.write)
        }
        Task.detached { try? await connectRelays() }
        UserDefaults.standard.set(true, forKey: "using_user_relays")
        feedback += 1
        ToastCenter.shared.show(L("usingPersonalRelays", ["count": urls.count]), style: .success)
        offerBroadcast(urls.filter { !previous.contains($0) })
    }

    private func offerBroadcast(_ urls: [String]) {
        guard !urls.isEmpty else { return }
        pendingBroadcast = urls
        showBroadcastPrompt = true
    }

    func broadcastPending() async {
        let targets = pendingBroadcast
        pendingBroadcast = []
        guard let me = Session.shared.pubkey, !targets.isEmpty, broadcastProgress == nil else { return }
        broadcastProgress = (0, 0)
        defer { broadcastProgress = nil }
        ToastCenter.shared.show(L("fetchingYourEvents"))
        let events = await SyncService.shared.fetchEvents(["authors": [me]], timeout: 30)
        var seen = Set<String>()
        let unique = events.filter { ($0.str("id")).map { seen.insert($0).inserted } ?? false }
        guard !unique.isEmpty else {
            ToastCenter.shared.show(L("noEventsFoundToBroadcast"))
            return
        }
        broadcastProgress = (0, unique.count)
        ToastCenter.shared.show(L("broadcastingEvents", ["count": unique.count, "relayCount": targets.count]))
        let payload = JSON.string(unique)
        let stream = EventStream.make { sink in try await streamBroadcastEvents(eventsJson: payload, relayUrls: targets, sink: sink) }
        var sent = 0
        do {
            for try await raw in stream {
                guard let progress = JSON.object(raw) else { continue }
                sent = progress.int("sent")
                broadcastProgress = (sent + progress.int("failed"), max(unique.count, progress.int("total")))
            }
            if sent > 0 {
                feedback += 1
                ToastCenter.shared.show(L("eventsSuccessfullyBroadcast", ["count": unique.count, "relayCount": targets.count]), style: .success)
            } else {
                ToastCenter.shared.show(L("errorBroadcastingEvents"), style: .error)
            }
        } catch {
            ToastCenter.shared.show("\(L("errorBroadcastingEvents")): \(coreErrorMessage(error))", style: .error)
        }
    }

    private func persist() {
        RelayConfig.mainRelays = relays
        let relevant = flags.filter { relays.contains($0.key) }
        if let data = try? JSONEncoder().encode(relevant) {
            UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: Self.flagsKey)
        }
    }

    private static func storedFlags() -> [String: SettingsRelayFlags] {
        guard let raw = UserDefaults.standard.string(forKey: flagsKey), let data = raw.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: SettingsRelayFlags].self, from: data)) ?? [:]
    }

    static func isValid(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix("wss://") || trimmed.hasPrefix("ws://"),
              let components = URLComponents(string: trimmed), let host = components.host, !host.isEmpty else { return false }
        return host.contains(".") || host == "localhost"
    }

    static func normalize(_ url: String) -> String {
        var trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") && !trimmed.hasSuffix("://") { trimmed.removeLast() }
        return trimmed
    }

    static func host(_ url: String) -> String {
        URLComponents(string: url)?.host ?? url
    }
}

extension SettingsRelayFlags {
    var marker: String {
        if read && write { return "" }
        return read ? "read" : "write"
    }
}
