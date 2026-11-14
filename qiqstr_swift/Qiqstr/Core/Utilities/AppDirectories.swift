import Foundation

nonisolated enum AppDirectories {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if os(macOS)
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "me.untreu.qiqstrmac", isDirectory: true)
        #else
        return base
        #endif
    }
}
