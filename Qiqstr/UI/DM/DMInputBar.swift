import PhotosUI
import SwiftUI

struct DMInputBar: View {
    @Bindable var model: DMChatViewModel
    var focus: FocusState<Bool>.Binding
    var placeholder: String = L("typeAMessage")

    var body: some View {
        VStack(spacing: 8) {
            if !model.attachments.isEmpty { attachmentStrip }
            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $model.pickerItems, maxSelectionCount: 4, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.regular))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .background(AppColors.tile, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("dmAttach"))
                .accessibilityIdentifier("dm-attach")

                TextField(placeholder, text: $model.draft, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...6)
                    .textInputAutocapitalization(.sentences)
                    .focused(focus)
                    .padding(.vertical, 9)
                    .accessibilityIdentifier("dm-input")

                Button(action: model.send) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(AppColors.background)
                        .frame(width: 40, height: 40)
                        .background(AppColors.textPrimary, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canSend)
                .opacity(model.canSend ? 1 : 0.3)
                .accessibilityLabel(L("sendMessage"))
                .accessibilityIdentifier("dm-send")
            }
            .padding(8)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28, style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .animation(.snappy(duration: 0.25), value: model.attachments.map(\.id))
        .animation(.snappy(duration: 0.2), value: model.canSend)
        .onChange(of: model.pickerItems) { if !model.pickerItems.isEmpty { model.handlePicked() } }
        .sensoryFeedback(.impact(weight: .light), trigger: model.sentCount)
        .sensoryFeedback(.error, trigger: model.failureCount)
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.attachments) { attachment in
                    ZStack {
                        if let thumbnail = attachment.thumbnail {
                            Image(uiImage: thumbnail).resizable().scaledToFill()
                        } else {
                            AppColors.tile
                            Image(systemName: attachment.isVideo ? "video.fill" : "photo")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        if attachment.state == .preparing {
                            Color.black.opacity(0.35)
                            ProgressView().tint(.white)
                        } else if attachment.isVideo {
                            Image(systemName: "play.circle.fill").font(.title).foregroundStyle(.white).shadow(radius: 3)
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            model.removeAttachment(attachment.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.primary)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .padding(4)
                        .accessibilityLabel(L("removeThisMediaFile"))
                        .accessibilityIdentifier("dm-attachment-remove")
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 4)
        }
        .accessibilityIdentifier("dm-attachments")
    }
}
