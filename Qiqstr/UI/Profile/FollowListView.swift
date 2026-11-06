import SwiftUI

struct FollowListView: View {
    let pubkey: String
    let mode: FollowListMode
    var body: some View { Text(pubkey) }
}
