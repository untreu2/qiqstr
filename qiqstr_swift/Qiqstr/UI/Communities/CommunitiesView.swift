import SwiftUI

enum CommunitySection: String, CaseIterable, Identifiable {
    case groups, communities, channels
    var id: Self { self }

    var title: String {
        switch self {
        case .groups: L("communityGroups")
        case .communities: L("communityCommunities")
        case .channels: L("communityChannels")
        }
    }

    var footnote: String {
        switch self {
        case .groups: L("communityGroupsAbout")
        case .communities: L("communityCommunitiesAbout")
        case .channels: L("communityChannelsAbout")
        }
    }
}

@MainActor
@Observable
final class CommunitiesModel {
    var section: CommunitySection = .groups
    var query = ""
    var groupRelay = CommunityService.groupRelays[0] {
        didSet { if groupRelay != oldValue { Task { await loadGroups() } } }
    }
    private(set) var groups: [RelayGroup] = []
    private(set) var communities: [Community] = []
    private(set) var channels: [PublicChannel] = []
    private(set) var loading: Set<CommunitySection> = []
    private var loaded: Set<CommunitySection> = []

    var relayOptions: [String] {
        var seen = Set<String>()
        return ([groupRelay] + CommunityService.groupRelays + CommunityService.shared.groups.map(\.relay)).filter { seen.insert($0).inserted }
    }

    func appear() async {
        if !CommunityService.shared.hasLoaded { await CommunityService.shared.load() }
        await loadCurrent(force: false)
    }

    func loadCurrent(force: Bool) async {
        guard force || !loaded.contains(section) else { return }
        switch section {
        case .groups: await loadGroups()
        case .communities: await run(.communities) { self.communities = await CommunityService.shared.discoverCommunities() }
        case .channels: await run(.channels) { self.channels = await CommunityService.shared.discoverChannels() }
        }
    }

    func refresh() async {
        await CommunityService.shared.load()
        await loadCurrent(force: true)
    }

    private func loadGroups() async {
        let relay = groupRelay
        await run(.groups) {
            let found = await CommunityService.shared.discoverGroups(relay: relay)
            if relay == self.groupRelay { self.groups = found }
        }
    }

    private func run(_ section: CommunitySection, _ work: () async -> Void) async {
        loading.insert(section)
        await work()
        loading.remove(section)
        loaded.insert(section)
    }

    func matches(_ fields: String...) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty || fields.contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}

struct CommunitiesView: View {
    @State private var model = CommunitiesModel()
    @State private var service = CommunityService.shared
    @State private var showsLink = false
    @State private var link = ""

    var body: some View {
        List {
            Section {
                Picker(L("communities"), selection: $model.section) {
                    ForEach(CommunitySection.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .accessibilityIdentifier("communities-section")
            } footer: {
                Text(model.section.footnote)
            }
            switch model.section {
            case .groups: groupSections
            case .communities: communitySections
            case .channels: channelSections
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("communities"))
        .searchable(text: $model.query, prompt: L("communitySearch"))
        .refreshable { await model.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsLink = true } label: { Label(L("communityOpenLink"), systemImage: "link.badge.plus") }
                    .accessibilityIdentifier("communities-open-link")
            }
        }
        .alert(L("communityOpenLink"), isPresented: $showsLink) {
            TextField(L("communityLinkPlaceholder"), text: $link)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(L("cancel"), role: .cancel) { link = "" }
            Button(L("communityOpen")) { openLink() }
        } message: {
            Text(L("communityLinkMessage"))
        }
        .task { await model.appear() }
        .onChange(of: model.section) { Task { await model.loadCurrent(force: false) } }
    }

    private func openLink() {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        link = ""
        if let group = RelayGroup(link: text) {
            Router.shared.push(.relayGroup(group.id))
        } else if let link = NostrLink(entity: text), case .event(let entity) = link, let id = Nip19.decode(entity) {
            // Public channels are shared as links to their kind 40 creation event.
            model.section = .channels
            Router.shared.push(.publicChannel(id))
        } else if let relay = CommunityService.normalizedRelay(text) {
            model.section = .groups
            model.groupRelay = relay
        } else if let address = ArticleAddress(naddr: text.replacingOccurrences(of: "nostr:", with: "")), address.kind == CommunityService.communityKind {
            Router.shared.push(.community("\(address.kind):\(address.pubkey):\(address.identifier)"))
        } else {
            ToastCenter.shared.show(L("communityLinkInvalid"), style: .error)
        }
    }

    // MARK: Groups

    @ViewBuilder
    private var groupSections: some View {
        let joined = service.groups.filter { model.matches($0.displayName, $0.about, $0.relayHost) }
        if !joined.isEmpty {
            Section(L("communityJoined")) {
                ForEach(joined) { group in groupLink(group) }
            }
        }
        Section {
            Picker(L("communityRelay"), selection: $model.groupRelay) {
                ForEach(model.relayOptions, id: \.self) { relay in
                    Text(URL(string: relay)?.host() ?? relay).tag(relay)
                }
            }
            .accessibilityIdentifier("communities-relay")
            let found = model.groups.filter { group in !service.isJoined(group) && model.matches(group.displayName, group.about) }
            if model.loading.contains(.groups) {
                loadingRow
            } else if found.isEmpty {
                Text(L("communityNoGroups")).foregroundStyle(.secondary)
            }
            ForEach(found) { group in groupLink(group) }
        } header: {
            Text(L("communityDiscover"))
        }
    }

    private func groupLink(_ group: RelayGroup) -> some View {
        NavigationLink(value: Route.relayGroup(group.id)) {
            CommunityRow(title: group.displayName, subtitle: group.about.nilIfEmpty ?? group.relayHost, picture: group.picture, systemImage: "bubble.left.and.bubble.right", badge: group.isClosed ? L("communityClosed") : nil)
        }
        .accessibilityIdentifier("community-group-row")
    }

    // MARK: Communities

    @ViewBuilder
    private var communitySections: some View {
        let joined = service.communities.filter { model.matches($0.displayName, $0.summary) }
        if !joined.isEmpty {
            Section(L("communityJoined")) {
                ForEach(joined) { community in communityLink(community) }
            }
        }
        Section {
            let found = model.communities.filter { community in !service.isJoined(community) && model.matches(community.displayName, community.summary) }
            if model.loading.contains(.communities) {
                loadingRow
            } else if found.isEmpty {
                Text(L("communityNoCommunities")).foregroundStyle(.secondary)
            }
            ForEach(found) { community in communityLink(community) }
        } header: {
            Text(L("communityDiscover"))
        }
    }

    private func communityLink(_ community: Community) -> some View {
        NavigationLink(value: Route.community(community.coordinate)) {
            CommunityRow(title: community.displayName, subtitle: community.summary, picture: community.image, systemImage: "person.3")
        }
        .accessibilityIdentifier("community-row")
    }

    // MARK: Channels

    @ViewBuilder
    private var channelSections: some View {
        let joined = service.channels.filter { model.matches($0.displayName, $0.about) }
        if !joined.isEmpty {
            Section(L("communityJoined")) {
                ForEach(joined) { channel in channelLink(channel) }
            }
        }
        Section {
            let found = model.channels.filter { channel in !service.isJoined(channel) && model.matches(channel.displayName, channel.about) }
            if model.loading.contains(.channels) {
                loadingRow
            } else if found.isEmpty {
                Text(L("communityNoChannels")).foregroundStyle(.secondary)
            }
            ForEach(found) { channel in channelLink(channel) }
        } header: {
            Text(L("communityDiscover"))
        }
    }

    private func channelLink(_ channel: PublicChannel) -> some View {
        NavigationLink(value: Route.publicChannel(channel.id)) {
            CommunityRow(title: channel.displayName, subtitle: channel.about, picture: channel.picture, systemImage: "number")
        }
        .accessibilityIdentifier("community-channel-row")
    }

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.vertical, 12)
    }
}

struct CommunityRow: View {
    let title: String
    let subtitle: String
    let picture: String
    let systemImage: String
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            CommunityIcon(picture: picture, systemImage: systemImage, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.inputFill, in: .capsule)
                    }
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct CommunityIcon: View {
    let picture: String
    let systemImage: String
    var size: CGFloat = 44

    var body: some View {
        RemoteImage(url: picture.nilIfEmpty, maxPixel: size * 3) {
            ZStack {
                AppColors.inputFill
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.26, style: .continuous))
        .accessibilityHidden(true)
    }
}
