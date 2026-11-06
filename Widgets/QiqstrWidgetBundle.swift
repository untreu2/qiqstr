import SwiftUI
import WidgetKit

@main
struct QiqstrWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickActionsWidget()
        NotificationsWidget()
    }
}
