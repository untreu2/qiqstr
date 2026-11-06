import SwiftUI

struct ShareThumbnail: View {
    let image: SharedImage
    let onRemove: () -> Void

    var body: some View {
        Image(uiImage: image.thumbnail)
            .resizable()
            .scaledToFill()
            .frame(width: 80, height: 80)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .padding(6)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.mini)
                .padding(4)
                .accessibilityLabel(Text("shareRemoveImage"))
            }
    }
}
