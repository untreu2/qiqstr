import SwiftUI

enum CommunityChatTarget: Hashable {
    case group(String)
    case channel(String)
}

@MainActor
@Observable
final class CommunityChatModel {
    let target: CommunityChatTarget
    private(set) var group: RelayGroup?
    private(set) var channel: PublicChannel?
    private(set) var messages: [CommunityChatMessage] = []
    private(set) var loaded = false
    private(set) var missing = false
    private(set) var isSending = false
    private(set) var isUpdatingMembership = false
    private(set) var memberCount: Int?
    var draft = ""
    @ObservationIgnored private var streamTask: Task<Void, Never>?

    init(target: CommunityChatTarget) {
        self.target = target
        if case .group(let id) = target { group = CommunityService.shared.cachedGroup(id) ?? RelayGroup(link: id) }
    }

    var title: String { group?.displayName ?? channel?.displayName ?? "" }
    var about: String { group?.about ?? channel?.about ?? "" }
    var picture: String { group?.picture ?? channel?.picture ?? "" }
    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && (group != nil || channel != nil) }

    var isJoined: Bool {
        if let group { return CommunityService.shared.isJoined(group) }
        if let channel { return CommunityService.shared.isJoined(channel) }
        return false
    }

    var shareLink: String? {
        if let group { return group.id }
        if let channel { return Nip19.note(channel.id).map { "nostr:\($0)" } }
        return nil
    }

    func start() async {
        let service = CommunityService.shared
        switch target {
        case .group:
            guard let ref = group else { missing = true; loaded = true; return }
            group = await service.group(ref)
            async let history = service.groupHistory(ref)
            async let members = service.groupMemberCount(ref)
            let (list, count) = await (history, members)
            merge(list)
            memberCount = count
            listen(service.groupStream(ref))
        case .channel(let id):
            guard let found = await service.channel(id: id) else { missing = true; loaded = true; return }
            channel = found
            merge(await service.channelHistory(found))
            listen(service.channelStream(found))
        }
        loaded = true
        await ProfileCache.shared.load(Array(Set(messages.map(\.pubkey))))
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
    }

    private func listen(_ stream: AsyncThrowingStream<CommunityChatMessage, Error>) {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            do {
                for try await message in stream {
                    guard let self else { return }
                    self.merge([message])
                    if ProfileCache.shared.profile(message.pubkey) == nil { await ProfileCache.shared.load([message.pubkey]) }
                }
            } catch {}
        }
    }

    private func merge(_ incoming: [CommunityChatMessage]) {
        let muted = Set(Session.shared.mutedPubkeys)
        let fresh = incoming.filter { message in !muted.contains(message.pubkey) && !messages.contains { $0.id == message.id } }
        guard !fresh.isEmpty else { return }
        messages = (messages + fresh).sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    func send() {
        guard canSend, ReadOnlyGate.check() else { return }
        let text = draft
        draft = ""
        isSending = true
        Task {
            defer { isSending = false }
            do {
                let sent: CommunityChatMessage
                if let group { sent = try await CommunityService.shared.send(text, to: group) } else if let channel { sent = try await CommunityService.shared.send(text, to: channel) } else { return }
                merge([sent])
            } catch {
                if draft.isEmpty { draft = text }
                ToastCenter.shared.show(coreMessage(error), style: .error)
            }
        }
    }

    func toggleMembership() async {
        guard ReadOnlyGate.check(), !isUpdatingMembership else { return }
        isUpdatingMembership = true
        defer { isUpdatingMembership = false }
        let service = CommunityService.shared
        do {
            if let group {
                if isJoined { try await service.leave(group) } else { try await service.join(group) }
            } else if let channel {
                if isJoined { try await service.leave(channel) } else { try await service.join(channel) }
            }
            ToastCenter.shared.show(L(isJoined ? "communityJoinedToast" : "communityLeftToast"), style: .success)
        } catch {
            ToastCenter.shared.show(coreMessage(error), style: .error)
        }
    }
}

struct CommunityChatView: View {
    @State private var model: CommunityChatModel
    @State private var service = CommunityService.shared
    @State private var showsInfo = false

    init(target: CommunityChatTarget) {
        _model = State(initialValue: CommunityChatModel(target: target))
    }

    var body: some View {
        Group {
            if model.missing {
                EmptyStateView(systemImage: "questionmark.bubble", title: L("communityNotFound"))
            } else {
                CommunityChatList(messages: model.messages, loaded: model.loaded)
                    .safeAreaInset(edge: .bottom) {
                        VStack(spacing: 0) {
                            if model.group != nil, !model.isJoined, model.loaded {
                                joinBanner
                            }
                            LiveChatInput(text: $model.draft, canSend: model.canSend, isSending: model.isSending, placeholder: L("communityMessagePlaceholder")) { model.send() }
                        }
                    }
            }
        }
        .background(AppColors.background)
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsInfo = true } label: { Label(L("communityInfo"), systemImage: "info.circle") }
                    .disabled(model.group == nil && model.channel == nil)
                    .accessibilityIdentifier("community-chat-info")
            }
        }
        .sheet(isPresented: $showsInfo) {
            CommunityChatInfoSheet(model: model)
                .presentationDetents([.medium, .large])
        }
        .task { await model.start() }
        .onDisappear { model.stop() }
    }

    private var joinBanner: some View {
        HStack(spacing: 12) {
            Text(L(model.group?.isClosed == true ? "communityClosedBanner" : "communityJoinBanner"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(L("communityJoin")) { Task { await model.toggleMembership() } }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.textPrimary)
                .disabled(model.isUpdatingMembership)
                .accessibilityIdentifier("community-join")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct CommunityChatList: View {
    let messages: [CommunityChatMessage]
    let loaded: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !loaded {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else if messages.isEmpty {
                        Text(L("communityChatEmpty"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                    ForEach(messages) { message in
                        CommunityChatRow(message: message).id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .accessibilityIdentifier("community-chat")
    }
}

struct CommunityChatRow: View {
    let message: CommunityChatMessage
    @State private var cache = ProfileCache.shared
    @State private var reportTarget: ReportTarget?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { Router.shared.push(.profile(message.pubkey)) } label: {
                ProfileAvatar(pubkey: message.pubkey, size: 32)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(cache.profile(message.pubkey)?.bestName.nilIfEmpty ?? Profile.shortNpub(message.pubkey))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(TimeFormat.relative(message.createdAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(ChatText.attributed(message.content))
                    .font(.subheadline)
                    .environment(\.openURL, OpenURLAction { NoteLink.handle($0) })
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .contentShape(Rectangle())
        .contextMenu {
            Button(L("copy"), systemImage: "doc.on.doc") { UIPasteboard.general.string = message.content }
            if message.pubkey != Session.shared.pubkey {
                Button(L("mute"), systemImage: "speaker.slash", role: .destructive) {
                    Task {
                        await Moderation.mute(message.pubkey)
                        ToastCenter.shared.show(L("feedUserMuted"), style: .success)
                    }
                }
                Button(L("report"), systemImage: "flag", role: .destructive) {
                    reportTarget = ReportTarget(pubkey: message.pubkey, eventId: message.id)
                }
            }
        }
        .reportSheet($reportTarget)
    }
}

/// Chat text with tappable web links, hashtags, readable @mentions and short links for nostr references.
enum ChatText {
    private static let pattern = try? NSRegularExpression(pattern: "(?:nostr:)?(?:npub1|nprofile1|note1|nevent1|naddr1)[02-9ac-hj-np-z]{20,}|https?://[^\\s]+|#[\\p{L}\\p{N}_]+")

    static func attributed(_ text: String) -> AttributedString {
        guard let pattern else { return AttributedString(text) }
        var result = AttributedString()
        var cursor = text.startIndex
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            result += AttributedString(String(text[cursor..<range.lowerBound]))
            result += token(String(text[range]))
            cursor = range.upperBound
        }
        result += AttributedString(String(text[cursor...]))
        return result
    }

    private static func token(_ raw: String) -> AttributedString {
        if raw.hasPrefix("#") {
            var tag = AttributedString(raw)
            tag.link = NoteLink.hashtag(String(raw.dropFirst()))
            return tag
        }
        if raw.hasPrefix("http") {
            var link = AttributedString(raw)
            link.link = URL(string: raw)
            return link
        }
        let bare = Nip19.stripScheme(raw)
        if bare.hasPrefix("npub1") || bare.hasPrefix("nprofile1"), let pubkey = Nip19.pubkeyHex(from: bare) {
            var mention = AttributedString("@" + (ProfileCache.shared.profile(pubkey)?.bestName.nilIfEmpty ?? Profile.shortNpub(pubkey)))
            mention.link = URL(string: "nostr:\(bare)")
            return mention
        }
        var reference = AttributedString(bare.hasPrefix("naddr1") ? L("chatLinkedArticle") : L("chatLinkedNote"))
        reference.link = URL(string: "nostr:\(bare)")
        return reference
    }
}

struct CommunityChatInfoSheet: View {
    let model: CommunityChatModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        CommunityIcon(picture: model.picture, systemImage: model.group != nil ? "bubble.left.and.bubble.right" : "number", size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.title).font(.title3.weight(.semibold))
                            if let count = model.memberCount {
                                Text(L("communityMembers", ["count": count])).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !model.about.isEmpty {
                        Text(model.about).font(.subheadline)
                    }
                }
                Section {
                    if let group = model.group {
                        LabeledContent(L("communityRelay"), value: group.relayHost)
                        if group.isClosed { LabeledContent(L("communityAccess"), value: L("communityClosed")) }
                    }
                    if let channel = model.channel {
                        Button { dismiss(); Router.shared.push(.profile(channel.creator)) } label: {
                            LabeledContent(L("communityCreator")) {
                                Text(ProfileCache.shared.profile(channel.creator)?.bestName.nilIfEmpty ?? Profile.shortNpub(channel.creator))
                            }
                        }
                    }
                    if let link = model.shareLink {
                        Button(L("communityCopyLink"), systemImage: "link") {
                            UIPasteboard.general.string = link
                            ToastCenter.shared.show(L("copiedToClipboard"), style: .success)
                        }
                    }
                }
                Section {
                    Button(model.isJoined ? L("communityLeave") : L("communityJoin"), role: model.isJoined ? .destructive : nil) {
                        Task { await model.toggleMembership() }
                    }
                    .disabled(model.isUpdatingMembership)
                    .accessibilityIdentifier("community-membership")
                }
            }
            .navigationTitle(L("communityInfo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("done")) { dismiss() }
                }
            }
        }
    }
}
