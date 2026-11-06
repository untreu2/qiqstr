import SwiftUI

struct ContinueReadingSection: View {
    var limit = 3
    @State private var store = ReadingProgressStore.shared

    var body: some View {
        let entries = store.continueReading(limit: limit)
        if !entries.isEmpty {
            Section {
                ForEach(entries) { entry in
                    ContinueReadingRow(entry: entry)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                withAnimation { store.remove(entry) }
                            } label: {
                                Label(L("articleRemoveFromContinue"), systemImage: "xmark")
                            }
                        }
                }
            } header: {
                Text(L("articleContinueReading"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
            .accessibilityIdentifier("continue-reading-section")
        }
    }
}

struct ContinueReadingRow: View {
    let entry: ReadingProgressEntry
    @State private var cache = ProfileCache.shared
    @ScaledMetric(relativeTo: .headline) private var thumbnailSize: CGFloat = 56

    private var authorName: String {
        cache.profile(entry.authorPubkey)?.bestName ?? entry.authorName ?? Profile.shortNpub(entry.authorPubkey)
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(authorName) · \(L("articleMinutesLeft", ["count": entry.minutesLeft]))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ProgressView(value: entry.progress)
                        .progressViewStyle(.linear)
                        .tint(.primary)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(L("articlePercentRead", ["percent": Int((entry.progress * 100).rounded())]))
        .accessibilityIdentifier("continue-reading-\(entry.articleId)")
    }

    private var thumbnail: some View {
        Group {
            if let image = entry.image {
                RemoteImage(url: image, maxPixel: 240) { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary) }
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColors.tile)
                    .overlay { Image(systemName: "doc.richtext").foregroundStyle(.secondary) }
            }
        }
        .frame(width: thumbnailSize, height: thumbnailSize)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
    }

    private func open() {
        if let naddr = entry.naddr {
            Router.shared.push(.articleAddress(naddr))
        } else {
            Router.shared.push(.article(entry.articleId))
        }
    }
}
