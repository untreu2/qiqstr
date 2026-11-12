import SwiftUI

enum ExploreSection: String, CaseIterable, Identifiable {
    case forYou, feeds, media, people, zaps, topics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forYou: L("exploreForYou")
        case .feeds: L("exploreFeeds")
        case .media: L("exploreMedia")
        case .people: L("explorePeople")
        case .zaps: L("exploreZaps")
        case .topics: L("exploreTopics")
        }
    }

    var systemImage: String {
        switch self {
        case .forYou: "sparkles"
        case .feeds: "square.stack"
        case .media: "photo.on.rectangle"
        case .people: "person.2"
        case .zaps: "bolt"
        case .topics: "number"
        }
    }
}

struct ExploreChipBar: View {
    @Binding var selection: ExploreSection

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(ExploreSection.allCases) { section in
                            chip(section).id(section)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) {
                withAnimation(.snappy) { proxy.scrollTo(selection, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityIdentifier("explore-sections")
    }

    @ViewBuilder
    private func chip(_ section: ExploreSection) -> some View {
        let selected = section == selection
        let button = Button {
            withAnimation(.snappy) { selection = section }
        } label: {
            Label(section.title, systemImage: section.systemImage)
                .font(.subheadline.weight(.semibold))
        }
        .buttonBorderShape(.capsule)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("explore-section-\(section.rawValue)")
        if selected {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass).foregroundStyle(.primary)
        }
    }
}

struct ExploreSectionRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

extension View {
    func exploreCarouselRow() -> some View { modifier(ExploreSectionRow()) }
}

struct ExploreCarousel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) { content }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .exploreCarouselRow()
    }
}

struct DiscoverFeedArtwork: View {
    let feed: DiscoverFeed
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let image = feed.image, !image.isEmpty {
                RemoteImage(url: image, maxPixel: size * 3) { placeholder }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            AppColors.tile
            Image(systemName: feed.content == .reads ? "doc.text" : "sparkles.rectangle.stack")
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct DiscoverFeedPinButton: View {
    let feed: DiscoverFeed
    @State private var explore = ExploreService.shared

    var body: some View {
        let pinned = explore.isPinned(feed)
        Button {
            explore.togglePin(feed)
            ToastCenter.shared.show(L(pinned ? "exploreFeedUnpinned" : "exploreFeedPinned", ["name": feed.name]), style: .success)
        } label: {
            Label(L(pinned ? "exploreFeedOnHome" : "exploreFeedAddToHome"), systemImage: pinned ? "checkmark" : "plus")
                .font(.subheadline.weight(.semibold))
        }
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .modifier(DiscoverFeedPinStyle(pinned: pinned))
        .sensoryFeedback(.success, trigger: pinned)
        .accessibilityIdentifier("discover-feed-pin-\(feed.dTag)")
    }
}

private struct DiscoverFeedPinStyle: ViewModifier {
    let pinned: Bool

    func body(content: Content) -> some View {
        if pinned {
            content.buttonStyle(.bordered).foregroundStyle(.primary)
        } else {
            content.buttonStyle(.glassProminent).foregroundStyle(AppColors.background)
        }
    }
}

struct DiscoverFeedRow: View {
    let feed: DiscoverFeed
    @State private var explore = ExploreService.shared

    var body: some View {
        NavigationLink(value: Route.discoverFeed(feed.id)) {
            HStack(spacing: 14) {
                DiscoverFeedArtwork(feed: feed, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(feed.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if explore.isPinned(feed) {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(L("exploreFeedOnHome"))
                        }
                    }
                    if !feed.about.isEmpty {
                        Text(feed.about)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .swipeActions(edge: .trailing) {
            if feed.content == .notes {
                let pinned = explore.isPinned(feed)
                Button(L(pinned ? "exploreFeedRemoveFromHome" : "exploreFeedAddToHome"), systemImage: pinned ? "pin.slash" : "pin") {
                    explore.togglePin(feed)
                }
                .tint(pinned ? .gray : .primary)
            }
        }
        .contextMenu {
            if feed.content == .notes {
                let pinned = explore.isPinned(feed)
                Button(L(pinned ? "exploreFeedRemoveFromHome" : "exploreFeedAddToHome"), systemImage: pinned ? "pin.slash" : "pin") {
                    explore.togglePin(feed)
                }
            }
            Button(L("exploreOpenProfile"), systemImage: "person.crop.circle") { Router.shared.push(.profile(feed.pubkey)) }
        }
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("discover-feed-\(feed.dTag)")
    }
}

struct DiscoverFeedCard: View {
    let feed: DiscoverFeed

    var body: some View {
        NavigationLink(value: Route.discoverFeed(feed.id)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    DiscoverFeedArtwork(feed: feed, size: 44)
                    Spacer(minLength: 8)
                    if feed.content == .reads {
                        Text(L("reads"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(feed.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(feed.about.isEmpty ? " " : feed.about)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(14)
            .frame(width: 230, alignment: .leading)
            .background(AppColors.tile, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("discover-feed-card-\(feed.dTag)")
    }
}

struct RisingPersonRow: View {
    let person: RisingPerson
    @State private var cache = ProfileCache.shared

    var body: some View {
        HStack(spacing: 12) {
            Button { Router.shared.push(.profile(person.pubkey)) } label: {
                HStack(spacing: 12) {
                    ProfileAvatar(pubkey: person.pubkey, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cache.profile(person.pubkey)?.bestName.nilIfEmpty ?? Profile.shortNpub(person.pubkey))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        RisingStat(person: person)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ExploreFollowButton(pubkey: person.pubkey)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
        .contextMenu { ExploreUserMenu(pubkey: person.pubkey) }
        .accessibilityIdentifier("explore-rising-\(person.pubkey.prefix(8))")
    }
}

struct RisingStat: View {
    let person: RisingPerson

    var body: some View {
        HStack(spacing: 4) {
            if person.increase > 0 {
                RisingIncrease(count: person.increase)
                Text(verbatim: "·").foregroundStyle(.tertiary)
            }
            Text(L("exploreFollowerCount", ["count": Sats.compact(person.followers)]))
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .lineLimit(1)
    }
}

struct RisingIncrease: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.up.right").imageScale(.small).fontWeight(.semibold)
            Text(L("exploreRisingIncrease", ["count": Sats.compact(count)]))
        }
        .foregroundStyle(AppColors.repost)
        .lineLimit(1)
    }
}

struct RisingPersonCard: View {
    let person: RisingPerson
    @State private var cache = ProfileCache.shared

    var body: some View {
        VStack(spacing: 8) {
            NavigationLink(value: Route.profile(person.pubkey)) {
                VStack(spacing: 6) {
                    ProfileAvatar(pubkey: person.pubkey, size: 64)
                    Text(cache.profile(person.pubkey)?.bestName.nilIfEmpty ?? Profile.shortNpub(person.pubkey))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if person.increase > 0 {
                        RisingIncrease(count: person.increase).font(.caption)
                    } else {
                        Text(L("exploreFollowerCount", ["count": Sats.compact(person.followers)]))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ExploreFollowButton(pubkey: person.pubkey)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .frame(width: 140)
        .background(AppColors.tile, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contextMenu { ExploreUserMenu(pubkey: person.pubkey) }
    }
}

struct TopZapRow: View {
    let zap: TopZap
    var note: Note?
    @State private var cache = ProfileCache.shared

    private func name(_ pubkey: String) -> String {
        let value = cache.profile(pubkey)?.bestName.nilIfEmpty ?? Profile.shortNpub(pubkey)
        return "\u{2068}\(value)\u{2069}"
    }

    var body: some View {
        Button {
            if let noteId = zap.noteId { Router.shared.push(.thread(noteId)) } else { Router.shared.push(.profile(zap.receiver)) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatar(pubkey: zap.sender, size: 44)
                    ProfileAvatar(pubkey: zap.receiver, size: 22)
                        .overlay(Circle().stroke(AppColors.background, lineWidth: 2))
                        .offset(x: 4, y: 4)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Label(Sats.format(zap.sats), systemImage: "bolt.fill")
                            .font(.headline)
                            .foregroundStyle(AppColors.zap)
                            .labelStyle(.titleAndIcon)
                        Spacer(minLength: 4)
                        Text(TimeFormat.relative(zap.createdAt))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(L("exploreZapFromTo", ["sender": name(zap.sender), "receiver": name(zap.receiver)]))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if !zap.comment.isEmpty {
                        Text(zap.comment)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let note, !note.content.isEmpty {
                        Text(note.content)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppColors.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L("exploreViewSender"), systemImage: "person") { Router.shared.push(.profile(zap.sender)) }
            Button(L("exploreViewReceiver"), systemImage: "person.fill") { Router.shared.push(.profile(zap.receiver)) }
        }
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("explore-zap-\(zap.id.prefix(8))")
    }
}

struct TopicRow: View {
    let topic: TrendingTopic
    var rank: Int?
    @State private var hashtags = HashtagFollowService.shared

    var body: some View {
        HStack(spacing: 12) {
            Button { Router.shared.push(.hashtag(topic.tag)) } label: {
                HStack(spacing: 12) {
                    if let rank {
                        Text(verbatim: "\(rank)")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .frame(minWidth: 22, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "#\(topic.tag)")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(L("exploreTopicNotes", ["count": topic.count]))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HashtagFollowButton(isFollowing: hashtags.isFollowing(topic.tag), isPending: hashtags.isPending(topic.tag)) {
                Task { await toggle() }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("explore-topic-\(topic.tag)")
    }

    private func toggle() async {
        do {
            if hashtags.isFollowing(topic.tag) {
                try await hashtags.unfollow(topic.tag)
            } else {
                try await hashtags.follow(topic.tag)
            }
        } catch {
            ToastCenter.shared.error(error)
        }
    }
}

struct TopicChips: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    NavigationLink(value: Route.hashtag(tag)) {
                        Text(verbatim: "#\(tag)").font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .accessibilityIdentifier("search-trending-tag-\(tag)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .exploreCarouselRow()
    }
}

struct FollowPackTile: View {
    let pack: FollowPack

    var body: some View {
        NavigationLink(value: Route.followPack(pack.id)) {
            VStack(alignment: .leading, spacing: 10) {
                FollowPackArtwork(url: pack.image.nilIfEmpty, isBuiltIn: pack.kind == 0)
                Text(pack.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2, reservesSpace: true)
                HStack(spacing: 8) {
                    FollowPackAvatarStack(pubkeys: Array(pack.members.prefix(4)), size: 22)
                    Text(L("memberCount", ["count": pack.members.count]))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(width: 200, alignment: .leading)
            .background(AppColors.tile, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("explore-pack-\(pack.id.prefix(8))")
    }
}

struct FollowPackRow: View {
    let pack: FollowPack

    var body: some View {
        NavigationLink(value: Route.followPack(pack.id)) {
            HStack(spacing: 14) {
                FollowPackArtwork(url: pack.image.nilIfEmpty, isBuiltIn: pack.kind == 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pack.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let summary = pack.summary.nilIfEmpty {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        FollowPackAvatarStack(pubkeys: Array(pack.members.prefix(5)), size: 20)
                        Text(L("memberCount", ["count": pack.members.count]))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.clear)
    }
}

struct ExploreMediaStrip: View {
    let entries: [ProfileMediaEntry]
    let onOpen: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    Button { onOpen(index) } label: {
                        ExploreMediaThumb(entry: entry)
                            .frame(width: 120, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.item.alt ?? L(entry.isVideo ? "videoTapToPlay" : "profileViewImage"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .exploreCarouselRow()
    }
}

struct ExploreMediaThumb: View {
    let entry: ProfileMediaEntry

    var body: some View {
        ZStack {
            AppColors.tile
            if entry.isVideo {
                if let poster = entry.item.poster {
                    RemoteImage(url: poster, maxPixel: 400) { Color.clear }
                }
            } else {
                RemoteImage(url: entry.url, maxPixel: 400) {
                    NoteMediaPlaceholder(blurhash: entry.item.blurhash)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if entry.isVideo {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .padding(6)
            }
        }
        .clipped()
    }
}

struct ExploreLoadingRows: View {
    var count = 3
    var person = false

    var body: some View {
        ForEach(0..<count, id: \.self) { index in
            Group {
                if person { SearchPersonSkeletonRow() } else { SearchNoteSkeletonRow(lines: index % 2 == 0 ? 3 : 2) }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
}
