import SwiftUI

// A value NavigationLink in a macOS List selects its row, and the row stays
// selected after you go back, so clicking it again does nothing. The shared
// screens only use links to app routes in the window's stacks, so on macOS a
// link is a plain button that pushes the route for the visible section.
struct NavigationLink<Label: View>: View {
    private let value: Route
    private let label: Label

    init(value: Route, @ViewBuilder label: () -> Label) {
        self.value = value
        self.label = label()
    }

    var body: some View {
        Button { Router.shared.push(value) } label: {
            label.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
