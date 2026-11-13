import BackgroundTasks
import Foundation

@MainActor
enum BackgroundRefresh {
    static let identifier = "me.untreu.qiqstrswift.refresh"
    private static let interval: TimeInterval = 15 * 60
    private static var launchTask: Task<Void, Never>?

    static func schedule() {
        guard LocalNotificationService.shared.isEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    static func launchSession() async {
        if let launchTask { return await launchTask.value }
        guard Session.shared.phase == .launching else { return }
        let task = Task { await Session.shared.launch() }
        launchTask = task
        await task.value
    }

    static func run() async {
        schedule()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await refresh() }
            group.addTask { try? await Task.sleep(for: .seconds(25)) }
            await group.next()
            group.cancelAll()
        }
    }

    private static func refresh() async {
        let service = LocalNotificationService.shared
        guard service.isEnabled else { return }
        await launchSession()
        await service.refreshStatus()
        guard !Task.isCancelled, service.isAuthorized, Session.shared.phase == .ready, let me = Session.shared.pubkey else { return }
        await service.checkForNewActivity(me: me)
    }
}
