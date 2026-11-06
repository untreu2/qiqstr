import SwiftUI

struct SettingsPageView: View {
    let page: SettingsRoute

    var body: some View {
        switch page {
        case .keys: KeysSettingsView()
        case .relays: RelaySettingsView()
        case .muted: MutedSettingsView()
        case .display: DisplaySettingsView()
        case .database: DatabaseSettingsView()
        case .eventManager: EventManagerSettingsView()
        case .payments: PaymentsSettingsView()
        case .language: LanguageSettingsView()
        }
    }
}
