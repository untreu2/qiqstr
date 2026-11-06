import PhotosUI
import SwiftUI

struct DMInputBar: View {
    @Bindable var model: DMChatViewModel
    var focus: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 8) {
            if !model.attachments.isEmpty { attachmentStrip }
            GlassEffectContainer(spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    PhotosPicker(selection: $model.pickerItems, maxSelectionCount: 4, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel(L("dmAttach"))
                    .accessibilityIdentifier("dm-attach")

                    HStack(alignment: .bottom, spacing: 8) {
                        TextField(L("typeAMessage"), text: $model.draft, axis: .vertical)
                            .font(.system(size: 16))
                            .lineLimit(1...6)
                            .textInputAutocapitalization(.sentences)
                            .focused(focus)
                            .padding(.vertical, 12)
                            .padding(.leading, 18)
                            .accessibilityIdentifier("dm-input")
                        Button(action: model.send) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(AppColors.background)
                                .frame(width: 36, height: 36)
                                .background(AppColors.textPrimary, in: Circle())
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(!model.canSend)
                        .opacity(model.canSend ? 1 : 0.35)
                        .padding(.trailing, 5)
                        .padding(.bottom, 5)
                        .accessibilityLabel(L("sendMessage"))
                        .accessibilityIdentifier("dm-send")
                    }
                    .frame(minHeight: 46)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                }
            }
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
                                .font(.system(size: 22))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        if attachment.state == .preparing {
                            Color.black.opacity(0.35)
                            ProgressView().tint(.white)
                        } else if attachment.isVideo {
                            Image(systemName: "play.circle.fill").font(.system(size: 24)).foregroundStyle(.white).shadow(radius: 3)
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            model.removeAttachment(attachment.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AppColors.textPrimary)
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
