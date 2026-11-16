import SwiftUI

struct EmojiPacksSettingsView: View {
    @State private var service = EmojiPackService.shared
    @State private var cache = ProfileCache.shared
    @State private var feedback = 0

    private var suggestions: [EmojiPack] { service.discovered.filter { !service.contains($0.coordinate) } }

    var body: some View {
        List {
            Section {
                if service.packs.isEmpty {
                    ContentUnavailableView(L("emojiNoPacks"), systemImage: "face.smiling", description: Text(L("emojiNoPacksHere")))
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("emoji-packs-empty")
                } else {
                    ForEach(service.packs) { pack in
                        EmojiPackRow(pack: pack, author: authorName(pack))
                            .swipeActions {
                                if pack.coordinate != EmojiPackService.ownCoordinate {
                                    Button(L("delete"), systemImage: "trash", role: .destructive) { remove(pack) }
                                }
                            }
                            .contextMenu {
                                if pack.coordinate != EmojiPackService.ownCoordinate {
                                    Button(L("emojiRemovePack"), systemImage: "trash", role: .destructive) { remove(pack) }
                                }
                            }
                    }
                }
            } header: {
                Text(L("emojiYourPacks"))
            } footer: {
                Text(L("emojiPacksFooter")).wrapsInFooter()
            }
            Section {
                if suggestions.isEmpty {
                    if service.isDiscovering {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else {
                        Text(L("emojiNoSuggestions")).foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(suggestions.prefix(60)) { pack in
                        HStack(spacing: 10) {
                            EmojiPackRow(pack: pack, author: authorName(pack))
                            Button(L("settingsAdd")) { add(pack) }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .disabled(service.busy.contains(pack.coordinate))
                                .accessibilityIdentifier("emoji-pack-add")
                        }
                    }
                }
            } header: {
                Text(L("emojiDiscover"))
            }
        }
        .settingsListStyle()
        .navigationTitle(L("emojiPacksTitle"))
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await service.load()
            await service.discover()
        }
        .task {
            await service.load()
            await service.discover()
        }
        .sensoryFeedback(.success, trigger: feedback)
        .animation(.snappy, value: service.packs)
    }

    private func authorName(_ pack: EmojiPack) -> String? {
        guard pack.coordinate != EmojiPackService.ownCoordinate else { return nil }
        return cache.profile(pack.author)?.bestName ?? Profile.shortNpub(pack.author)
    }

    private func add(_ pack: EmojiPack) {
        guard ReadOnlyGate.check() else { return }
        Task {
            do {
                try await service.add(pack)
                feedback += 1
            } catch {
                ToastCenter.shared.error(error)
            }
        }
    }

    private func remove(_ pack: EmojiPack) {
        Task {
            do { try await service.remove(pack) } catch { ToastCenter.shared.error(error) }
        }
    }
}

struct EmojiPackRow: View {
    let pack: EmojiPack
    var author: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(pack.title).font(.body.weight(.semibold)).lineLimit(1)
                Text("\(pack.emojis.count)").font(.footnote).foregroundStyle(.secondary)
            }
            if let author {
                Text(author).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 6) {
                ForEach(pack.emojis.prefix(8)) { emoji in
                    CustomEmojiImage(url: emoji.url, size: 24)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("emoji-pack-row")
    }
}
