import SwiftUI

enum KeysPasswordStrength: Int, Comparable {
    case weak, fair, strong

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    init(_ password: String) {
        let classes = [
            password.contains(where: \.isLowercase),
            password.contains(where: \.isUppercase),
            password.contains(where: \.isNumber),
            password.contains { !$0.isLetter && !$0.isNumber },
        ].filter { $0 }.count
        let count = password.count
        if count < Ncryptsec.minimumPasswordLength || (count < 12 && classes < 2) {
            self = .weak
        } else if count >= 16 || (count >= 12 && classes >= 3) {
            self = .strong
        } else {
            self = .fair
        }
    }

    var title: String {
        switch self {
        case .weak: L("keysBackupStrengthWeak")
        case .fair: L("keysBackupStrengthFair")
        case .strong: L("keysBackupStrengthStrong")
        }
    }

    var systemImage: String {
        switch self {
        case .weak: "exclamationmark.shield"
        case .fair: "shield.lefthalf.filled"
        case .strong: "checkmark.shield"
        }
    }

    var tint: Color {
        switch self {
        case .weak: AppColors.error
        case .fair: .orange
        case .strong: .green
        }
    }
}

@MainActor
@Observable
final class KeysBackupModel {
    var password = ""
    var confirmation = ""
    private(set) var isEncrypting = false
    private(set) var ncryptsec: String?
    private(set) var errorMessage: String?
    private(set) var copied = false
    private(set) var copyCount = 0
    private let privateKeyHex: String

    init(privateKeyHex: String) {
        self.privateKeyHex = privateKeyHex
    }

    var strength: KeysPasswordStrength { KeysPasswordStrength(password) }
    var isLongEnough: Bool { password.count >= Ncryptsec.minimumPasswordLength }
    var matches: Bool { !confirmation.isEmpty && password == confirmation }
    var showMismatch: Bool { !confirmation.isEmpty && password != confirmation }
    var canEncrypt: Bool { isLongEnough && matches && !isEncrypting }

    func encrypt() async {
        guard canEncrypt else { return }
        isEncrypting = true
        errorMessage = nil
        defer { isEncrypting = false }
        do {
            ncryptsec = try await Ncryptsec.encrypt(privateKeyHex: privateKeyHex, password: password)
            password = ""
            confirmation = ""
        } catch {
            errorMessage = coreMessage(error)
        }
    }

    func copy() {
        guard let ncryptsec else { return }
        SettingsClipboard.copy(ncryptsec, sensitive: true)
        copied = true
        copyCount += 1
        ToastCenter.shared.show(L("copiedToClipboardWithType", ["type": "NCRYPTSEC"]), style: .success)
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

struct KeysBackupSheet: View {
    @State private var model: KeysBackupModel
    @FocusState private var field: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field { case password, confirmation }

    init(privateKeyHex: String) {
        _model = State(initialValue: KeysBackupModel(privateKeyHex: privateKeyHex))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let ncryptsec = model.ncryptsec {
                    resultSections(ncryptsec)
                } else {
                    passwordSections
                }
            }
            .navigationTitle(L("keysBackupTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .animation(.snappy, value: model.ncryptsec)
            .animation(.snappy, value: model.showMismatch)
            .animation(.snappy, value: model.password.isEmpty)
            .sensoryFeedback(.success, trigger: model.copyCount)
            .sensoryFeedback(.success, trigger: model.ncryptsec != nil)
            .onAppear { field = .password }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isEncrypting)
        .accessibilityIdentifier("keys-backup-sheet")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.ncryptsec == nil {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) { dismiss() }
                    .disabled(model.isEncrypting)
            }
            ToolbarItem(placement: .confirmationAction) {
                if model.isEncrypting {
                    ProgressView()
                } else {
                    Button(L("keysBackupEncrypt"), action: encrypt)
                        .disabled(!model.canEncrypt)
                        .accessibilityIdentifier("keys-backup-encrypt")
                }
            }
        } else {
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .confirm) { dismiss() }
                    .accessibilityIdentifier("keys-backup-done")
            }
        }
    }

    @ViewBuilder
    private var passwordSections: some View {
        Section {
            SecureField(L("keysBackupPassword"), text: $model.password)
                .textContentType(.newPassword)
                .focused($field, equals: .password)
                .submitLabel(.next)
                .onSubmit { field = .confirmation }
                .accessibilityIdentifier("keys-backup-password")
            SecureField(L("keysBackupConfirm"), text: $model.confirmation)
                .textContentType(.newPassword)
                .focused($field, equals: .confirmation)
                .submitLabel(.done)
                .onSubmit(encrypt)
                .accessibilityIdentifier("keys-backup-confirm")
            if !model.password.isEmpty {
                LabeledContent(L("keysBackupStrength")) {
                    Label(model.strength.title, systemImage: model.strength.systemImage)
                        .foregroundStyle(model.strength.tint)
                }
                .accessibilityIdentifier("keys-backup-strength")
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if model.showMismatch {
                    Text(L("keysBackupMismatch")).foregroundStyle(AppColors.error)
                } else if !model.password.isEmpty && !model.isLongEnough {
                    Text(L("keysBackupTooShort", ["count": Ncryptsec.minimumPasswordLength])).foregroundStyle(AppColors.error)
                }
                if let message = model.errorMessage {
                    Text(message).foregroundStyle(AppColors.error)
                }
                Text(L("keysBackupPasswordFooter", ["count": Ncryptsec.minimumPasswordLength]))
            }
        }
        .disabled(model.isEncrypting)

        if model.isEncrypting {
            Section {
                Label {
                    Text(L("keysBackupEncrypting"))
                } icon: {
                    ProgressView()
                }
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("keys-backup-progress")
            }
        }
    }

    @ViewBuilder
    private func resultSections(_ ncryptsec: String) -> some View {
        Section {
            HStack {
                Spacer()
                QRCodeView(content: ncryptsec, size: 220)
                    .accessibilityLabel(L("keysBackupQRCode"))
                Spacer()
            }
            .listRowBackground(Color.clear)
        }

        Section {
            Text(ncryptsec)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("keys-backup-value")
            Button(action: model.copy) {
                Label(model.copied ? L("copied") : L("copy"), systemImage: model.copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityIdentifier("keys-backup-copy")
            ShareLink(item: ncryptsec) {
                Label(L("share"), systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("keys-backup-share")
        } header: {
            Text(L("keysBackupResultHeader"))
        } footer: {
            Text(L("keysBackupResultFooter"))
        }
    }

    private func encrypt() {
        guard model.canEncrypt else { return }
        field = nil
        Task { await model.encrypt() }
    }
}
