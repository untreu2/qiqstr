import SwiftUI

enum QuickAction: CaseIterable, Identifiable {
    case compose, search, messages

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .compose: "widgetNewPost"
        case .search: "widgetSearch"
        case .messages: "widgetMessages"
        }
    }

    var systemImage: String {
        switch self {
        case .compose: "square.and.pencil"
        case .search: "magnifyingglass"
        case .messages: "message"
        }
    }

    var url: URL {
        switch self {
        case .compose: DeepLink.compose
        case .search: DeepLink.search
        case .messages: DeepLink.messages
        }
    }
}
