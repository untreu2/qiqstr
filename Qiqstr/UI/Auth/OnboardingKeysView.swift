import SwiftUI

struct OnboardingKeysView: View {
    let onContinue: () -> Void

    @State private var session = Session.shared
    @State private var revealNsec = false
    @State private var pendingCopy: PendingCopy?
    @State private var copyCount = 0

    private struct PendingCopy: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    private var mnemonicWords: [String] {
        (session.account?.mnemonic ?? "").split(separator: " ").map(String.init)
    }

    private var nsec: String {
        session.privateKey.flatMap { Nip19.nsec($0) } ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AuthHeader(title: L("backupYourAccount"), subtitle: L("secureYourAccount"))
                if !mnemonicWords.isEmpty { seedSection }
                if !nsec.isEmpty { nsecSection }
                warnings
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(AppColors.background)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: L("iHaveWrittenDownSeedPhrase"), action: onContinue)
                .accessibilityIdentifier("onboarding-keys-continue")
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(AppColors.background)
        }
        .toolbar {
            ToolbarItem(placement: .principal) { OnboardingStepIndicator(current: 1) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert(L("warning"), isPresented: Binding(get: { pendingCopy != nil }, set: { if !$0 { pendingCopy = nil } }), presenting: pendingCopy) { item in
            Button(L("cancel"), role: .cancel) {}
            Button(L("copy")) {
                SecureClipboard.copy(item.value)
                copyCount += 1
                ToastCenter.shared.show(L("copiedToClipboardWithType", ["type": item.label]), style: .success)
            }
            .accessibilityIdentifier("copy-warning-confirm")
        } message: { _ in
            Text(L("copyKeyWarning"))
        }
        .sensoryFeedback(.success, trigger: copyCount)
    }

    private var seedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("seedPhrase"), copyIdentifier: "onboarding-copy-seed") {
                pendingCopy = PendingCopy(label: L("seedPhrase"), value: mnemonicWords.joined(separator: " "))
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(mnemonicWords.enumerated()), id: \.offset) { index, word in
                    HStack(spacing: 6) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(minWidth: 16, alignment: .trailing)
                        Text(word)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(AppColors.overlayLight, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("onboarding-seed-grid")
        }
    }

    private var nsecSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("privateKeyNsec"), copyIdentifier: "onboarding-copy-nsec") {
                pendingCopy = PendingCopy(label: L("privateKeyNsec"), value: nsec)
            }
            Button {
                withAnimation(.snappy) { revealNsec.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(revealNsec ? nsec : String(repeating: "•", count: 32))
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.opacity)
                    Image(systemName: revealNsec ? "eye.slash" : "eye")
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(AppColors.overlayLight, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(revealNsec ? L("hideKey") : L("showKey"))
            .accessibilityIdentifier("onboarding-reveal-nsec")
            Text(L("useThisToRecoverAccount"))
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 4)
        }
    }

    private var warnings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("important"), systemImage: "exclamationmark.triangle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.error)
            ForEach([L("writeSeedPhraseInOrder"), L("storeItSafely"), L("neverShareIt"), L("ifYouLoseIt"), L("accessFromSettings")], id: \.self) { warning in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                    Text(warning).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textPrimary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.error.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func sectionTitle(_ title: String, copyIdentifier: String, onCopy: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Button(action: onCopy) {
                Label(L("copy"), systemImage: "doc.on.doc")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .accessibilityIdentifier(copyIdentifier)
        }
        .padding(.horizontal, 4)
    }
}
