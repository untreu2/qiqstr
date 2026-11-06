import Foundation

nonisolated struct ShareManifest: Codable, Sendable {
    let id: String
    let text: String
    let images: [String]
    let created: Date
}

nonisolated enum ShareInbox {
    static let appGroup = "group.me.untreu.qiqstrswift"
    static let folder = "SharedInbox"
    static let manifestName = "manifest.json"

    static var rootURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: folder, directoryHint: .isDirectory)
    }

    static func write(text: String, images: [Data]) throws -> String {
        guard let root = rootURL else { throw CocoaError(.fileNoSuchFile) }
        let id = UUID().uuidString.lowercased()
        let dir = root.appending(path: id, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var names: [String] = []
        for (index, data) in images.enumerated() {
            let name = "\(index).jpg"
            try data.write(to: dir.appending(path: name), options: .atomic)
            names.append(name)
        }
        let manifest = ShareManifest(id: id, text: text, images: names, created: Date())
        try JSONEncoder().encode(manifest).write(to: dir.appending(path: manifestName), options: .atomic)
        return id
    }
}
