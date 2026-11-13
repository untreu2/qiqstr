import UIKit

enum ListError: LocalizedError {
    case cancelled
    var errorDescription: String? { L("listNewCancelled") }
}

@MainActor
enum ListConfirmation {
    private static var pending: [Int: Task<Bool, Never>] = [:]

    static func startNewList(kind: Int) async -> Bool {
        if let task = pending[kind] { return await task.value }
        let task = Task { await ask(kind: kind) }
        pending[kind] = task
        defer { pending[kind] = nil }
        return await task.value
    }

    private static func ask(kind: Int) async -> Bool {
        guard let presenter = topController() else { return false }
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: L("listNotFoundTitle"), message: L("listNotFoundMessage", ["list": name(kind)]), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L("cancel"), style: .cancel) { _ in continuation.resume(returning: false) })
            alert.addAction(UIAlertAction(title: L("listStartNew"), style: .default) { _ in continuation.resume(returning: true) })
            alert.view.accessibilityIdentifier = "list-not-found-alert"
            presenter.present(alert, animated: true)
        }
    }

    private static func name(_ kind: Int) -> String {
        switch kind {
        case 10001: L("listNamePins")
        case 30001: L("listNameBookmarks")
        case 10015: L("listNameTopics")
        case 10002: L("listNameRelays")
        default: L("listNameGeneric")
        }
    }

    private static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }
}
