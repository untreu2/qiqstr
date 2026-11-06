import SwiftUI

struct ShareComposeView: View {
    @State var model: ShareModel
    @FocusState private var editorFocused: Bool

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("shareTitle"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .interactiveDismissDisabled(model.phase == .saving)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .editing, .saving:
            editor
        case .handoff:
            ContentUnavailableView {
                Label("shareSavedTitle", systemImage: "tray.and.arrow.down")
            } description: {
                Text("shareOpenAppMessage")
            } actions: {
                Button("shareDone") { model.finish() }
                    .buttonStyle(.glassProminent)
            }
        case .failed:
            ContentUnavailableView {
                Label("shareFailedTitle", systemImage: "exclamationmark.triangle")
            } description: {
                Text("shareFailedMessage")
            } actions: {
                Button("shareDone") { model.cancel() }
                    .buttonStyle(.glass)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $model.text)
                .font(.body)
                .focused($editorFocused)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    if model.text.isEmpty {
                        Text("sharePlaceholder")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityIdentifier("share-text")
            if !model.images.isEmpty {
                thumbnails
            }
        }
        .padding()
        .disabled(model.phase == .saving)
        .onAppear { editorFocused = true }
    }

    private var thumbnails: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.images) { image in
                    ShareThumbnail(image: image) { model.remove(image) }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.phase == .editing || model.phase == .saving || model.phase == .loading {
            ToolbarItem(placement: .cancellationAction) {
                Button("shareCancel", role: .cancel) { model.cancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if model.phase == .saving {
                    ProgressView()
                } else {
                    Button("sharePost", role: .confirm) { model.post() }
                        .disabled(!model.canPost)
                        .accessibilityIdentifier("share-post")
                }
            }
        }
    }
}
