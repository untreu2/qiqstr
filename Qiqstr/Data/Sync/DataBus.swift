import Foundation
import Observation

@MainActor
@Observable
final class DataBus {
    static let shared = DataBus()
    private(set) var feedVersion = 0
    private(set) var profileVersion = 0
    private(set) var notificationVersion = 0
    private(set) var interactionVersion = 0
    private(set) var dmVersion = 0
    private(set) var listsVersion = 0
    private(set) var lastFeedIds: [String] = []

    func feedChanged(ids: [String] = []) { lastFeedIds = ids; feedVersion &+= 1 }
    func profileChanged() { profileVersion &+= 1 }
    func notificationsChanged() { notificationVersion &+= 1 }
    func interactionsChanged() { interactionVersion &+= 1 }
    func dmChanged() { dmVersion &+= 1 }
    func listsChanged() { listsVersion &+= 1 }
    func everythingChanged() { feedChanged(); profileChanged(); notificationsChanged(); interactionsChanged(); dmChanged(); listsChanged() }
}
