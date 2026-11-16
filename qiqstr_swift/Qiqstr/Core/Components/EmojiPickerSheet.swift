import SwiftUI

struct CustomEmojiImage: View {
    let url: String
    var size: CGFloat = 28

    var body: some View {
        RemoteImage(url: url, maxPixel: 96, contentMode: .fit) { Color.clear }
            .frame(width: size, height: size)
    }
}

struct EmojiChoiceView: View {
    let choice: EmojiChoice
    var size: CGFloat = 28

    var body: some View {
        switch choice {
        case .unicode(let emoji): Text(emoji).font(.system(size: size))
        case .custom(let emoji): CustomEmojiImage(url: emoji.url, size: size)
        }
    }
}

struct EmojiPickerSheet: View {
    var customOnly = false
    let onPick: (EmojiChoice) -> Void
    @State private var query = ""
    @State private var packs = EmojiPackService.shared
    @State private var recents = RecentEmojiStore.shared
    @State private var jump: String?
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 42), spacing: 4)]

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var customMatches: [CustomEmoji] {
        let term = query.trimmingCharacters(in: .whitespaces).lowercased()
        return packs.allEmojis.filter { $0.shortcode.lowercased().contains(term) }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14, pinnedViews: []) {
                        if searching {
                            let custom = customMatches
                            let standard = customOnly ? [] : EmojiCatalog.search(query)
                            if custom.isEmpty, standard.isEmpty {
                                EmptyStateView(systemImage: "face.dashed", title: L("emojiNoResults")).padding(.top, 40)
                            }
                            if !custom.isEmpty { grid(custom.map(EmojiChoice.custom)) }
                            if !standard.isEmpty { grid(standard.map { .unicode($0.emoji) }) }
                        } else {
                            let recent = recents.items.filter { if case .custom = $0 { return true } else { return !customOnly } }
                            if !recent.isEmpty { section("recent", L("emojiRecent"), recent) }
                            ForEach(packs.packs) { pack in
                                section(pack.coordinate, pack.title, pack.emojis.map(EmojiChoice.custom))
                            }
                            if customOnly, packs.packs.isEmpty {
                                EmptyStateView(systemImage: "face.smiling", title: L("emojiNoPacks"), message: L("emojiNoPacksMessage")).padding(.top, 40)
                            }
                            if !customOnly {
                                ForEach(EmojiCatalog.groups) { group in
                                    section(group.id, group.title, group.items.map { .unicode($0.emoji) })
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
                .onChange(of: jump) { _, target in
                    guard let target else { return }
                    withAnimation(.snappy) { proxy.scrollTo(target, anchor: .top) }
                    jump = nil
                }
            }
            .background(AppColors.background)
            .safeAreaInset(edge: .bottom) { if !customOnly, !searching { categoryBar } }
            .navigationTitle(L("emojiTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L("emojiSearch"))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("cancel"), systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("emoji-cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { if !packs.isLoaded { await packs.load() } }
        .accessibilityIdentifier("emoji-picker")
    }

    private func section(_ id: String, _ title: String, _ choices: [EmojiChoice]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            grid(choices)
        }
        .id(id)
    }

    private func grid(_ choices: [EmojiChoice]) -> some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(choices, id: \.self) { choice in
                Button {
                    recents.record(choice)
                    onPick(choice)
                    dismiss()
                } label: {
                    EmojiChoiceView(choice: choice, size: 28)
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.content)
                .accessibilityIdentifier("emoji-item")
            }
        }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if !packs.packs.isEmpty {
                    barButton("star", id: packs.packs[0].coordinate, label: L("emojiCustom"))
                }
                ForEach(EmojiCatalog.groups) { group in
                    barButton(group.symbol, id: group.id, label: group.title)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func barButton(_ symbol: String, id: String, label: String) -> some View {
        Button { jump = id } label: {
            Image(systemName: symbol)
                .font(.body)
                .frame(width: 38, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
    }
}
