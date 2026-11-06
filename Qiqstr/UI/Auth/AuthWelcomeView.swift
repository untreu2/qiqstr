import SwiftUI

struct AuthWelcomeView: View {
    var isAddAccount = false
    let onLogin: () -> Void
    let onSignup: () -> Void

    @State private var acceptedTerms = false
    @State private var showTermsError = false
    @State private var showTerms = false
    @State private var showLanguage = false
    @State private var termsErrorTrigger = 0

    private static let termsURL = URL(string: "qiqstr-auth://terms")!
    private static let boldWords = ["decentralized", "Nostr", "open source", "açık kaynaklı", "merkeziyetsiz", "dezentrales"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                title
                    .padding(.top, isAddAccount ? 8 : 40)
                    .padding(.horizontal, 20)
                features
                    .padding(.top, 36)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(AppColors.background)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showLanguage = true
                } label: {
                    Image(systemName: "translate")
                }
                .accessibilityLabel(L("language"))
                .accessibilityIdentifier("welcome-language")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTerms) { AuthTermsSheet() }
        .sheet(isPresented: $showLanguage) { AuthLanguageSheet() }
        .sensoryFeedback(.selection, trigger: acceptedTerms)
        .sensoryFeedback(.error, trigger: termsErrorTrigger)
        .animation(.snappy, value: showTermsError)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("welcomeTitle"))
                .font(AppFont.brand(52))
                .kerning(-1.5)
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var subtitle: AttributedString {
        var text = AttributedString(L("welcomeSubtitle"))
        for word in Self.boldWords {
            var searchRange = text.startIndex..<text.endIndex
            while let range = text[searchRange].range(of: word) {
                text[range].font = .system(size: 15, weight: .bold)
                searchRange = range.upperBound..<text.endIndex
            }
        }
        return text
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 24) {
            AuthFeatureRow(systemImage: "globe", text: L("welcomeFeatureDecentralized"))
            AuthFeatureRow(systemImage: "key", text: L("welcomeFeatureKeys"))
            AuthFeatureRow(systemImage: "lock", text: L("welcomeFeatureBitcoin"))
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            termsRow
            if showTermsError {
                Text(L("acceptanceOfTermsIsRequired"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.error)
                    .transition(.opacity)
                    .accessibilityIdentifier("welcome-terms-error")
            }
            PrimaryButton(title: L("createNewAccount")) {
                proceed(onSignup)
            }
            .accessibilityIdentifier("welcome-create-account")
            Button {
                proceed(onLogin)
            } label: {
                Text(L("welcomeAlreadyHaveAccount"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("welcome-login")
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppColors.background)
    }

    private var termsRow: some View {
        HStack(spacing: 10) {
            Button {
                acceptedTerms.toggle()
                if acceptedTerms { showTermsError = false }
            } label: {
                Image(systemName: acceptedTerms ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(acceptedTerms ? AppColors.textPrimary : AppColors.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("termsOfUse"))
            .accessibilityValue(acceptedTerms ? L("yes") : "")
            .accessibilityAddTraits(acceptedTerms ? .isSelected : [])
            .accessibilityIdentifier("welcome-terms-checkbox")
            Text(termsText)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
                .environment(\.openURL, OpenURLAction { _ in
                    showTerms = true
                    return .handled
                })
                .accessibilityIdentifier("welcome-terms-link")
        }
        .frame(maxWidth: .infinity)
    }

    private var termsText: AttributedString {
        var prefix = AttributedString(L("iAcceptThe"))
        prefix.foregroundColor = AppColors.textSecondary
        var link = AttributedString(L("termsOfUse"))
        link.link = Self.termsURL
        link.foregroundColor = AppColors.textPrimary
        link.underlineStyle = .single
        return prefix + link
    }

    private func proceed(_ action: () -> Void) {
        guard acceptedTerms else {
            showTermsError = true
            termsErrorTrigger += 1
            return
        }
        action()
    }
}
