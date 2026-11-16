import SwiftUI

@MainActor
@Observable
final class GifPickerModel {
    var query = ""
    private(set) var items: [GifItem] = []
    private(set) var isLoading = true
    @ObservationIgnored private var task: Task<Void, Never>?

    func load() {
        task?.cancel()
        let term = query
        isLoading = true
        task = Task { [weak self] in
            if !term.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            let result = await GifService.shared.search(term)
            guard !Task.isCancelled, let self, self.query == term else { return }
            self.items = result
            self.isLoading = false
        }
    }
}

struct GifPickerSheet: View {
    let onPick: (GifItem) -> Void
    @State private var model = GifPickerModel()
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 6)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(model.items) { gif in
                        Button {
                            onPick(gif)
                            dismiss()
                        } label: {
                            AnimatedRemoteImage(url: gif.preview, blurhash: gif.blurhash, maxPixel: 400)
                                .aspectRatio(1.3, contentMode: .fit)
                                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(gif.title.isEmpty ? L("feedGif") : gif.title)
                        .accessibilityIdentifier("gif-item")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .overlay {
                if model.items.isEmpty {
                    if model.isLoading {
                        ProgressView().controlSize(.large)
                    } else {
                        EmptyStateView(systemImage: "photo.on.rectangle.angled", title: L("feedGifEmpty"), message: L("feedGifEmptyMessage"))
                    }
                }
            }
            .background(AppColors.background)
            .navigationTitle(L("feedGifTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: L("feedGifSearch"))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("cancel"), systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("gif-cancel")
                }
            }
            .onChange(of: model.query) { model.load() }
            .task { model.load() }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("gif-picker")
    }
}
