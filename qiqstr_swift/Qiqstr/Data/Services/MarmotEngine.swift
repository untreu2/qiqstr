import Foundation
import QiqstrCore

nonisolated struct MarmotGroup: Hashable, Sendable {
    var id: String
    var nostrGroupId: String
    var name: String
    var state: String
    var members: [String]
    var relays: [String]
    var lastMessageAt: Int

    var isActive: Bool { state == "active" }

    init?(json j: JSONObject) {
        guard let id = j.str("id"), let nostrGroupId = j.str("nostrGroupId") else { return nil }
        self.id = id
        self.nostrGroupId = nostrGroupId
        name = (j["name"] as? String) ?? ""
        state = (j["state"] as? String) ?? ""
        members = j.strings("members")
        relays = j.strings("relays")
        lastMessageAt = j.int("lastMessageAt")
    }

    func peer(for me: String) -> String? {
        let others = members.filter { $0 != me }
        guard members.contains(me), others.count == 1 else { return nil }
        return others[0]
    }
}

nonisolated struct MarmotOutcome: Sendable {
    var eventId: String
    var type: String
    var groupId: String?
    var messageJSON: String?
    var groupJSON: String?
    var evolutionEvent: String?
    var isNewWelcome: Bool

    var retry: [String]

    init(eventId: String, raw: String?) {
        let j = raw.flatMap { JSON.object($0) } ?? [:]
        self.eventId = eventId
        type = raw == nil ? "error" : (j["type"] as? String) ?? "ignored"
        retry = j.strings("retry")
        groupId = j.str("groupId")
        messageJSON = (j["message"] as? JSONObject).map { JSON.string($0) }
        groupJSON = (j["group"] as? JSONObject).map { JSON.string($0) }
        evolutionEvent = j.str("evolutionEvent")
        isNewWelcome = j.bool("isNew")
    }
}

nonisolated struct MarmotCreatedChat: Sendable {
    var groupJSON: String
    var welcomes: [String]
    var welcomeRelays: [String]
}

nonisolated struct MarmotSent: Sendable {
    var eventJSON: String
    var messageJSON: String?
}

nonisolated struct MarmotEncryptedMedia: Sendable {
    var fileURL: URL
    var encryptedHash: String
    var originalHash: String
    var mimeType: String
    var filename: String
    var size: Int
    var imeta: [String]
}

actor MarmotEngine {
    static let shared = MarmotEngine()

    private var tail: Task<Void, Never>?

    static var storageDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("marmot", isDirectory: true)
    }

    nonisolated static func excludeFromBackup(_ directory: URL) {
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private func serial<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task { () async throws -> T in
            await previous?.value
            return try await work()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }

    func close() async {
        _ = try? await serial { marmotClose() }
    }

    func open(privateKey: String) async throws -> String {
        let directory = Self.storageDirectory
        return try await serial {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            Self.excludeFromBackup(directory)
            return try marmotOpen(dataDir: directory.path, privateKeyHex: privateKey)
        }
    }

    func groups() async throws -> [MarmotGroup] {
        let raw = try await serial { try marmotGroups() }
        return JSON.array(raw).compactMap(MarmotGroup.init(json:))
    }

    func messages(groupId: String, limit: Int, offset: Int = 0) async throws -> String {
        try await serial { try marmotMessagesPage(groupIdHex: groupId, limit: UInt32(limit), offset: UInt32(max(offset, 0))) }
    }

    func process(_ events: [String]) async -> [MarmotOutcome] {
        let ordered = events
            .compactMap { raw -> (Int, String, String)? in
                guard let j = JSON.object(raw), let id = j.str("id") else { return nil }
                return (j.int("created_at"), id, raw)
            }
            .sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
        guard !ordered.isEmpty else { return [] }
        return (try? await serial {
            ordered.map { item in MarmotOutcome(eventId: item.1, raw: try? marmotProcessEvent(eventJson: item.2)) }
        }) ?? []
    }

    func keyPackageEvent(relays: [String]) async throws -> String {
        try await serial { try marmotKeyPackageEvent(relays: relays) }
    }

    func keyPackageRelaysEvent(relays: [String]) async throws -> String {
        try await serial { try marmotKeyPackageRelaysEvent(relays: relays) }
    }

    func pickKeyPackage(eventsJSON: String, owner: String) async throws -> String? {
        try await serial { try marmotPickKeyPackage(eventsJson: eventsJSON, pubkeyHex: owner) }
    }

    func createChat(keyPackage: String, relays: [String]) async throws -> MarmotCreatedChat {
        let raw = try await serial { try marmotCreateChat(peerKeyPackageJson: keyPackage, relays: relays) }
        let j = JSON.object(raw) ?? [:]
        guard let group = j["group"] as? JSONObject else { throw CoreError(L("dmSendFailed")) }
        return MarmotCreatedChat(
            groupJSON: JSON.string(group),
            welcomes: (j["welcomes"] as? [String]) ?? [],
            welcomeRelays: j.strings("welcomeRelays")
        )
    }

    func send(groupId: String, kind: UInt16, content: String, tags: [[String]]) async throws -> MarmotSent {
        let tagsJSON = tags.isEmpty ? "[]" : JSON.string(tags)
        let raw = try await serial { try marmotSendMessage(groupIdHex: groupId, kind: kind, content: content, tagsJson: tagsJSON) }
        let j = JSON.object(raw) ?? [:]
        guard let event = j["event"] as? String else { throw CoreError(L("dmSendFailed")) }
        return MarmotSent(eventJSON: event, messageJSON: (j["message"] as? JSONObject).map { JSON.string($0) })
    }

    func rotateKeys(olderThan seconds: UInt64, publish: @escaping @Sendable (String, String) async -> Bool) async {
        _ = try? await serial {
            let groups = (try? marmotGroupsNeedingSelfUpdate(thresholdSecs: seconds)) ?? []
            for group in groups {
                guard let commit = try? marmotSelfUpdate(groupIdHex: group) else { continue }
                if await publish(group, commit) {
                    try? marmotMergePendingCommit(groupIdHex: group)
                } else {
                    try? marmotClearPendingCommit(groupIdHex: group)
                }
            }
        }
    }

    func finishCommit(groupId: String, eventJSON: String, publish: @escaping @Sendable (String) async -> Bool) async {
        _ = try? await serial {
            if await publish(eventJSON) {
                try? marmotMergePendingCommit(groupIdHex: groupId)
            } else {
                try? marmotClearPendingCommit(groupIdHex: groupId)
            }
        }
    }

    func encryptMedia(groupId: String, data: Data, mimeType: String, filename: String) async throws -> MarmotEncryptedMedia {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("marmot-upload-\(UUID().uuidString)")
        let raw = try await serial {
            try marmotEncryptMedia(groupIdHex: groupId, data: data, mimeType: mimeType, filename: filename, outputPath: output.path)
        }
        let j = JSON.object(raw) ?? [:]
        guard let encryptedHash = j.str("encryptedHash"), let originalHash = j.str("originalHash") else {
            throw CoreError(L("encryptionFailed"))
        }
        return MarmotEncryptedMedia(
            fileURL: output,
            encryptedHash: encryptedHash,
            originalHash: originalHash,
            mimeType: j.str("mimeType") ?? mimeType,
            filename: j.str("filename") ?? filename,
            size: j.int("size"),
            imeta: j.strings("imeta")
        )
    }

    func decryptMedia(groupId: String, imeta: [String], data: Data) async throws -> Data {
        try await serial { try marmotDecryptMedia(groupIdHex: groupId, imeta: imeta, data: data) }
    }
}
