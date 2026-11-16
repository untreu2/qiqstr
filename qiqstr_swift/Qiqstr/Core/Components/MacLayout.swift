import SwiftUI

extension View {
    /// For screens whose principal toolbar item already names the screen: on macOS the
    /// window toolbar would also show the navigation title beside it.
    func hidesMacToolbarTitle() -> some View {
        #if os(macOS)
        toolbar(removing: .title)
        #else
        self
        #endif
    }
}

extension View {
    /// Lets section footer text wrap. A macOS List draws footers on one line and cuts them off.
    func wrapsInFooter() -> some View {
        lineLimit(nil).fixedSize(horizontal: false, vertical: true)
    }
}
