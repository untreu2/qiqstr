import LocalAuthentication
import SwiftUI

enum SettingsSecretKind: String, Identifiable {
    case nsec, mnemonic
    var id: String { rawValue }
    var title: String { self == .nsec ? L("privateKeyNsec") : L("seedPhrase") }
}

@MainActor
@Observable
final class KeysSettingsModel {
    private(set) var npub = ""
    private(set) var nsec: String?
    private(set) var mnemonic: String?
    private(set) var revealed: Set<SettingsSecretKind> = []
    private(set) var copied: String?
    var pendingCopy: SettingsSecretKind?
    var showAdvanced = false
    var copyCount = 0

    func load() {
        let account = Session.shared.account
        npub = account?.npub ?? ""
        nsec = account.flatMap { Nip19.nsec($0.privateKeyHex) }
        mnemonic = account?.mnemonic?.nilIfEmpty
    }

    func isRevealed(_ kind: SettingsSecretKind) -> Bool { revealed.contains(kind) }

    func toggleReveal(_ kind: SettingsSecretKind) async {
        if revealed.contains(kind) {
            revealed.remove(kind)
            return
        }
        if await authenticate() { revealed.insert(kind) }
    }

    func requestCopy(_ kind: SettingsSecretKind) async {
        guard await authenticate() else { return }
        pendingCopy = kind
    }

    func confirmCopy() {
        guard let kind = pendingCopy else { return }
        pendingCopy = nil
        let value = kind == .nsec ? nsec : mnemonic
        guard let value else { return }
        SettingsClipboard.copy(value, sensitive: true)
        markCopied(kind.rawValue, label: kind == .nsec ? "NSEC" : L("seedPhrase"))
    }

    func copyNpub() {
        SettingsClipboard.copy(npub)
        markCopied("npub", label: "NPUB")
    }

    func hideAll() { revealed.removeAll() }

    private func markCopied(_ id: String, label: String) {
        copied = id
        copyCount += 1
        ToastCenter.shared.show(L("copiedToClipboardWithType", ["type": label]), style: .success)
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copied == id { copied = nil }
        }
    }

    func isCopied(_ id: String) -> Bool { copied == id }

    private func authenticate() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            let code = (error as? LAError)?.code
            return code == .passcodeNotSet || code == .biometryNotAvailable || code == .biometryNotEnrolled || error == nil
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L("keysAuthenticateReason"))
        } catch {
            return false
        }
    }
}

struct KeysSettingsView: View {
    @State private var model = KeysSettingsModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            SettingsPageHeader(subtitle: L("keysSubtitle"))
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.npub.isEmpty ? L("loading") : model.npub)
                        .font(.system(size: 15).monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("keys-npub")
                    copyButton(copied: model.isCopied("npub"), identifier: "keys-copy-npub") { model.copyNpub() }
                }
                .padding(.vertical, 4)
            } header: {
                Text(L("publicKeyNpub"))
            } footer: {
                Text(L("shareThisToReceiveMessages"))
            }

            Section {
                if let mnemonic = model.mnemonic {
                    secretBody(.mnemonic) { SettingsSeedPhraseGrid(phrase: mnemonic) }
                } else {
                    Text(L("notAvailable")).foregroundStyle(AppColors.textSecondary)
                }
            } header: {
                Text(L("seedPhrase"))
            } footer: {
                Text(L("useThisToRecoverAccount"))
            }

            if model.showAdvanced {
                Section {
                    if let nsec = model.nsec {
                        secretBody(.nsec) {
                            Text(nsec)
                                .font(.system(size: 15).monospaced())
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(L("errorEncodingNsec")).foregroundStyle(AppColors.error)
                    }
                } header: {
                    Text(L("privateKeyNsec"))
                } footer: {
                    Text(L("keepThisSecret"))
                }
            }

            Section {
                Button {
                    withAnimation(.snappy) { model.showAdvanced.toggle() }
                } label: {
                    HStack {
                        Spacer()
                        Text(L("advanced"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                        Image(systemName: model.showAdvanced ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("keys-advanced")
            }
        }
        .settingsListStyle()
        .navigationTitle(L("keysTitle"))
        .onAppear { model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.hideAll() }
        }
        .alert(L("warning"), isPresented: Binding(get: { model.pendingCopy != nil }, set: { if !$0 { model.pendingCopy = nil } })) {
            Button(L("cancel"), role: .cancel) { model.pendingCopy = nil }
            Button(L("copy")) { model.confirmCopy() }
                .accessibilityIdentifier("keys-copy-confirm")
        } message: {
            Text(L("copyKeyWarning"))
        }
        .sensoryFeedback(.success, trigger: model.copyCount)
    }

    @ViewBuilder
    private func secretBody<Content: View>(_ kind: SettingsSecretKind, @ViewBuilder content: () -> Content) -> some View {
        let revealed = model.isRevealed(kind)
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                if revealed {
                    content()
                } else {
                    content()
                        .hidden()
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppColors.tile)
                                .overlay {
                                    Text(String(repeating: "•••• ", count: 18))
                                        .font(.system(size: 15, design: .monospaced))
                                        .foregroundStyle(AppColors.textSecondary)
                                        .blur(radius: 6)
                                        .padding(16)
                                }
                                .accessibilityHidden(true)
                        }
                }
                if !revealed {
                    Label(L("keysTapToReveal"), systemImage: "faceid")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { if !revealed { Task { await model.toggleReveal(kind) } } }
            HStack(spacing: 10) {
                Button {
                    Task { await model.toggleReveal(kind) }
                } label: {
                    Label(revealed ? L("hideKey") : L("showKey"), systemImage: revealed ? "eye.slash" : "eye")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("keys-reveal-\(kind.rawValue)")
                copyButton(copied: model.isCopied(kind.rawValue), identifier: "keys-copy-\(kind.rawValue)") {
                    Task { await model.requestCopy(kind) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func copyButton(copied: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(copied ? L("copied") : L("copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier(identifier)
    }
}

struct SettingsSeedPhraseGrid: View {
    let phrase: String

    var body: some View {
        let words = phrase.split(separator: " ").map(String.init)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                HStack(spacing: 4) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(AppColors.textSecondary)
                    Text(word)
                        .font(.system(size: 14, weight: .medium).monospaced())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AppColors.tile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("keys-seed-grid")
    }
}
