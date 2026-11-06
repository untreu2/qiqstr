import SwiftUI

enum ZapTarget: Hashable {
    case note(Note)
    case profile(String)
}

struct ZapSheet: View {
    let target: ZapTarget
    var body: some View { Text("Zap") }
}
