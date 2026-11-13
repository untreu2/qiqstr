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
                .controlSize(.small)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(Text("shareRemoveImage"))
            }
    }
}
