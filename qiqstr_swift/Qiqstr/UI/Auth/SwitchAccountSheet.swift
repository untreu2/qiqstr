import SwiftUI

enum SwitchAccountRoute: Hashable {
    case addAccount
}

struct SwitchAccountSheet: View {
    @State private var session = Session.shared
    @State private var cache = ProfileCache.shared
    @State private var path = NavigationPath()
    @State private var detent: PresentationDetent = .medium
    @State private var switchingTo: String?
    @State private var removing: StoredAccount?
    @State private var confirmLogout = false
    @State private var isLoggingOut = false
    @State private var switchCount = 0
    @State private var isAddingKey = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(session.accounts) { account in
                        accountRow(account)
                    }
                } header: {
                    Text(L("authAccounts"))
                }
                if session.isReadOnly {
                    Section {
                        Button {
                            isAddingKey = true
                        } label: {
                            Label(L("readOnlyAddKey"), systemImage: "key")
                                .foregroundStyle(.primary)
                        }
                        .accessibilityIdentifier("switch-add-key")
                    } footer: {
                        Text(L("readOnlyMessage"))
                    }
                }
                Section {
                    Button {
                        detent = .large
                        path.append(SwitchAccountRoute.addAccount)
                    } label: {
                        Label(L("addAccount"), systemImage: "plus.circle")
                            .foregroundStyle(.primary)
                    }
                    .accessibilityIdentifier("switch-add-account")
                }
                Section {
                    Button(role: .destructive) {
                        confirmLogout = true
                    } label: {
                        HStack {
                            Label(L("logout"), systemImage: "rectangle.portrait.and.arrow.right")
                            if isLoggingOut {
                                Spacer()
                                ProgressView()
                            }
                        }
                        .foregroundStyle(.red)
                    }
                    .disabled(isLoggingOut)
                    .accessibilityIdentifier("switch-logout")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L("switchAccount"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityIdentifier("switch-close")
                }
            }
            .navigationDestination(for: SwitchAccountRoute.self) { _ in
                AuthWelcomeView(
                    isAddAccount: true,
                    onLogin: { path.append(AuthStep.login) },
                    onSignup: { path.append(AuthStep.signup) }
                )
            }
            .authDestinations()
            .confirmationDialog(L("areYouSureLogout"), isPresented: $confirmLogout, titleVisibility: .visible) {
                Button(L("logout"), role: .destructive) { logout() }
                    .accessibilityIdentifier("switch-logout-confirm")
                Button(L("cancel"), role: .cancel) {}
            } message: {
                Text(L("seedPhraseWarning"))
            }
            .confirmationDialog(L("authRemoveAccountTitle"), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible, presenting: removing) { account in
                Button(L("authRemoveAccount"), role: .destructive) { remove(account) }
                    .accessibilityIdentifier("switch-remove-confirm")
                Button(L("cancel"), role: .cancel) {}
            } message: { _ in
                Text(L("seedPhraseWarning"))
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .task(id: session.accounts.map(\.npub)) {
            await cache.load(session.accounts.map(\.pubkeyHex).filter { !$0.isEmpty })
        }
        .onChange(of: path.count) { _, count in
            if count == 0 { detent = .medium }
        }
        .sensoryFeedback(.success, trigger: switchCount)
        .sheet(isPresented: $isAddingKey) { AddKeySheet() }
        .accessibilityIdentifier("switch-account-sheet")
    }

    private func accountRow(_ account: StoredAccount) -> some View {
        let pubkey = account.pubkeyHex
        let isActive = account.npub == session.npub
        let profile = cache.profile(pubkey)
        return Button {
            switchTo(account)
        } label: {
            HStack(spacing: 12) {
                ProfileAvatar(pubkey: pubkey, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(profile?.bestName ?? Profile.shortNpub(pubkey))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if account.isReadOnly {
                            Image(systemName: "eye")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(L("readOnlyBadge"))
                                .accessibilityIdentifier("switch-read-only-\(account.npub.suffix(6))")
                        }
                    }
                    Text(shortNpub(account.npub))
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if switchingTo == account.npub {
                    ProgressView()
                } else if isActive {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityLabel(L("authActive"))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(switchingTo != nil)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                removing = account
            } label: {
                Label(L("authRemoveAccount"), systemImage: "trash")
            }
            .accessibilityIdentifier("switch-remove-\(account.npub.suffix(6))")
        }
        .contextMenu {
            if account.isReadOnly, isActive {
                Button {
                    isAddingKey = true
                } label: {
                    Label(L("readOnlyAddKey"), systemImage: "key")
                }
            }
            Button {
                UIPasteboard.general.string = account.npub
                ToastCenter.shared.show(L("copiedNpub"), style: .success)
            } label: {
                Label(L("publicKeyNpub"), systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                removing = account
            } label: {
                Label(L("authRemoveAccount"), systemImage: "trash")
            }
        }
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier("switch-account-\(account.npub.suffix(6))")
    }

    private func shortNpub(_ npub: String) -> String {
        npub.count > 16 ? "\(npub.prefix(10))…\(npub.suffix(6))" : npub
    }

    private func switchTo(_ account: StoredAccount) {
        guard account.npub != session.npub else {
            dismiss()
            return
        }
        switchingTo = account.npub
        Task {
            do {
                try await session.switchAccount(account.npub)
                switchCount += 1
            } catch {
                ToastCenter.shared.error(error)
            }
            switchingTo = nil
        }
    }

    private func remove(_ account: StoredAccount) {
        Task { await session.removeAccount(account.npub) }
    }

    private func logout() {
        isLoggingOut = true
        Task {
            await session.logout()
            isLoggingOut = false
        }
    }
}
