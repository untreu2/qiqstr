import SwiftUI

enum ReadOnlyError: LocalizedError {
    case signerRequired
    var errorDescription: String? { L("readOnlyMessage") }
}

@MainActor
@Observable
final class ReadOnlyGate {
    static let shared = ReadOnlyGate()
    var isAlertPresented = false
    var isAddingKey = false

    func present() {
        guard !isAddingKey else { return }
        isAlertPresented = true
    }

    func addKey() {
        isAlertPresented = false
        isAddingKey = true
    }

    func reset() {
        isAlertPresented = false
        isAddingKey = false
    }

    static func check() -> Bool {
        guard Session.shared.isReadOnly else { return true }
        shared.present()
        return false
    }

    static func intercepts(_ message: String) -> Bool {
        guard Session.shared.isReadOnly else { return false }
        let markers = [L("readOnlyMessage"), L("authenticationRequired"), L("dmNotSignedIn"), L("privateKeyNotFound"), L("walletNoAccount"), "Not signed in", "Not authenticated"]
        guard markers.contains(where: message.contains) else { return false }
        shared.present()
        return true
    }
}

extension EnvironmentValues {
    @Entry var canSign = true
}
