import Foundation
import Observation
import UIKit

enum DMConversationFilter: String, CaseIterable, Identifiable {
    case following, other
    var id: String { rawValue }
}

@MainActor
@Observable
final class DMConversationsViewModel {
    var filter: DMConversationFilter = .following
    var showNewMessage = false
    @ObservationIgnored private var didAutoSelect = false
    private let service = DMService.shared

    var isInitialLoading: Bool { !service.hasLoaded && service.conversations.isEmpty }
    var hasAnyConversation: Bool { !service.conversations.isEmpty }
    var hasUnread: Bool { service.unreadCount > 0 }

    var visibleConversations: [DMConversation] {
        service.conversations.filter { matches($0, filter) }
    }

    func unreadCount(_ filter: DMConversationFilter) -> Int {
        service.conversations.filter { $0.isUnread && matches($0, filter) }.count
    }

    func title(for filter: DMConversationFilter) -> String {
        let base = filter == .following ? L("dmTabFollowing") : L("dmTabOther")
        let unread = unreadCount(filter)
        return unread > 0 ? "\(base) (\(unread))" : base
    }

    private func matches(_ conversation: DMConversation, _ filter: DMConversationFilter) -> Bool {
        let followed = service.isFollowing(conversation.peer)
        return filter == .following ? followed : !followed
    }

    var hasLoaded: Bool { service.hasLoaded }

    func appeared() async {
        service.isListVisible = true
        await service.start()
        autoSelectFilter()
    }

    func autoSelectFilter() {
        guard !didAutoSelect, service.hasLoaded else { return }
        didAutoSelect = true
        if filter == .following, visibleConversations.isEmpty, hasAnyConversation { filter = .other }
    }

    func disappeared() { service.isListVisible = false }

    func refresh() async {
        await service.reloadFollowing()
        await service.refresh()
    }

    func poll() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            await service.refresh()
        }
    }

    func reloadFollowing() async { await service.reloadFollowing() }

    func toggleRead(_ conversation: DMConversation) {
        if conversation.isUnread { service.markRead(conversation.peer) } else { service.markUnread(conversation.peer) }
    }

    func canMarkUnread(_ conversation: DMConversation) -> Bool {
        !conversation.isUnread && !conversation.lastMessage.isMine
    }

    func markAllRead() { service.markAllRead() }

    func copyNpub(_ pubkey: String) {
        UIPasteboard.general.string = Nip19.npub(pubkey) ?? pubkey
        ToastCenter.shared.show(L("copiedNpub"), style: .success)
    }
}
