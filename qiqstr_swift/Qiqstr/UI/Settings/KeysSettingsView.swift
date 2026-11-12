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
    private(set) var privateKeyHex: String?
    var pendingCopy: SettingsSecretKind?
    var isBackupPresented = false
    var showAdvanced = false
    var copyCount = 0

    func load() {
        let account = Session.shared.account
        npub = account?.npub ?? ""
        privateKeyHex = account?.signingKey
        nsec = account?.signingKey.flatMap { Nip19.nsec($0) }
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

    func requestBackup() async {
        guard privateKeyHex != nil, await authenticate() else { return }
        isBackupPresented = true
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

    static func unhyphenated(_ key: String) -> String {
        key.map(String.init).joined(separator: "\u{200B}")
    }

    var body: some View {
        List {
            Section {
                Text(model.npub.isEmpty ? L("loading") : Self.unhyphenated(model.npub))
                    .font(.body.monospaced())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("keys-npub")
                copyButton(copied: model.isCopied("npub"), identifier: "keys-copy-npub") { model.copyNpub() }
            } header: {
                Text(L("publicKeyNpub"))
            } footer: {
                Text(L("shareThisToReceiveMessages"))
            }

            Section {
                if let mnemonic = model.mnemonic {
                    secretRows(.mnemonic) {
                        SettingsSeedPhraseGrid(phrase: mnemonic, masked: !model.isRevealed(.mnemonic))
                    }
                } else {
                    Text(L("notAvailable")).foregroundStyle(.secondary)
                }
            } header: {
                Text(L("seedPhrase"))
            } footer: {
                Text(L("useThisToRecoverAccount"))
            }

            if model.privateKeyHex != nil {
                Section {
                    Button {
                        Task { await model.requestBackup() }
                    } label: {
                        SettingsRowLabel(title: L("keysBackupCreate"), systemImage: "lock.doc")
                    }
                    .accessibilityIdentifier("keys-backup-create")
                } header: {
                    Text(L("keysBackupHeader"))
                } footer: {
                    Text(L("keysBackupFooter"))
                }
            }

            Section {
                Button {
                    withAnimation(.snappy) { model.showAdvanced.toggle() }
                } label: {
                    LabeledContent {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .rotationEffect(.degrees(model.showAdvanced ? 90 : 0))
                    } label: {
                        SettingsRowLabel(title: L("advanced"), systemImage: "gearshape.2")
                    }
                }
                .accessibilityIdentifier("keys-advanced")
                if model.showAdvanced {
                    if let nsec = model.nsec {
                        secretRows(.nsec) {
                            Text(model.isRevealed(.nsec) ? Self.unhyphenated(nsec) : String(repeating: "\u{2022}", count: nsec.count))
                                .font(.body.monospaced())
                                .foregroundStyle(model.isRevealed(.nsec) ? .primary : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(L("errorEncodingNsec")).foregroundStyle(AppColors.error)
                    }
                }
            } header: {
                if model.showAdvanced { Text(L("privateKeyNsec")) }
            } footer: {
                if model.showAdvanced { Text(L("keepThisSecret")) }
            }
        }
        .settingsListStyle()
        .navigationTitle(L("keysTitle"))
        .navigationBarTitleDisplayMode(.large)
        .onAppear { model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.hideAll() }
            if phase == .background { model.isBackupPresented = false }
        }
        .sheet(isPresented: $model.isBackupPresented) {
            if let key = model.privateKeyHex {
                KeysBackupSheet(privateKeyHex: key)
            }
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
    private func secretRows<Content: View>(_ kind: SettingsSecretKind, @ViewBuilder content: () -> Content) -> some View {
        let revealed = model.isRevealed(kind)
        content()
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture { if !revealed { Task { await model.toggleReveal(kind) } } }
            .accessibilityLabel(revealed ? kind.title : L("keysTapToReveal"))
            .animation(.snappy, value: revealed)
        Button {
            Task { await model.toggleReveal(kind) }
        } label: {
            Label(revealed ? L("hideKey") : L("showKey"), systemImage: revealed ? "eye.slash" : "eye")
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityIdentifier("keys-reveal-\(kind.rawValue)")
        copyButton(copied: model.isCopied(kind.rawValue), identifier: "keys-copy-\(kind.rawValue)") {
            Task { await model.requestCopy(kind) }
        }
    }

    private func copyButton(copied: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(copied ? L("copied") : L("copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityIdentifier(identifier)
    }
}

struct SettingsSeedPhraseGrid: View {
    let phrase: String
    var masked = false

    var body: some View {
        let words = phrase.split(separator: " ").map(String.init)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: 3), alignment: .leading, spacing: 10) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                HStack(spacing: 6) {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 18, alignment: .trailing)
                    Text(masked ? String(repeating: "\u{2022}", count: 5) : word)
                        .font(.body.monospaced())
                        .foregroundStyle(masked ? .secondary : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .accessibilityElement(children: masked ? .ignore : .combine)
        .accessibilityIdentifier("keys-seed-grid")
    }
}
