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
                .font(.custom("Poppins-Bold", size: 52, relativeTo: .largeTitle))
                .kerning(-1.5)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var subtitle: AttributedString {
        var text = AttributedString(L("welcomeSubtitle"))
        for word in Self.boldWords {
            var searchRange = text.startIndex..<text.endIndex
            while let range = text[searchRange].range(of: word) {
                text[range].inlinePresentationIntent = .stronglyEmphasized
                text[range].foregroundColor = .primary
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
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
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .accessibilityIdentifier("welcome-login")
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppColors.background)
    }

    private var termsRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                acceptedTerms.toggle()
                if acceptedTerms { showTermsError = false }
            } label: {
                Image(systemName: acceptedTerms ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(acceptedTerms ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("termsOfUse"))
            .accessibilityValue(acceptedTerms ? L("yes") : "")
            .accessibilityAddTraits(acceptedTerms ? [.isSelected, .isToggle] : .isToggle)
            .accessibilityIdentifier("welcome-terms-checkbox")
            Text(termsText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .environment(\.openURL, OpenURLAction { _ in
                    showTerms = true
                    return .handled
                })
                .accessibilityIdentifier("welcome-terms-link")
        }
        .frame(maxWidth: .infinity)
    }

    private var termsText: AttributedString {
        let prefix = AttributedString(L("iAcceptThe"))
        var link = AttributedString(L("termsOfUse"))
        link.link = Self.termsURL
        link.foregroundColor = .primary
        link.inlinePresentationIntent = .stronglyEmphasized
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
