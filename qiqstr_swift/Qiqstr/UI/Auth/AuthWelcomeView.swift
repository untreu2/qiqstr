import SwiftUI

struct AuthWelcomeView: View {
    var isAddAccount = false
    let onLogin: () -> Void
    let onSignup: () -> Void

    @AppStorage("acceptedTerms") private var acceptedTerms = false
    @State private var pendingDestination: Destination?
    @State private var showTermsPrompt = false
    @State private var showTerms = false
    @State private var showLanguage = false

    private enum Destination {
        case signup
        case login
    }

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
        .alert(L("authTermsTitle"), isPresented: $showTermsPrompt) {
            Button(L("authTermsAgree")) { acceptTerms() }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("welcome-terms-agree")
            Button(L("authTermsRead")) { showTerms = true }
                .accessibilityIdentifier("welcome-terms-read")
            Button(L("cancel"), role: .cancel) { pendingDestination = nil }
        } message: {
            Text(L("authTermsPromptMessage"))
        }
        .sheet(isPresented: $showTerms, onDismiss: {
            if acceptedTerms { acceptTerms() } else { pendingDestination = nil }
        }) {
            AuthTermsSheet(onAccept: pendingDestination == nil ? nil : {
                acceptedTerms = true
                showTerms = false
            })
        }
        .sheet(isPresented: $showLanguage) { AuthLanguageSheet() }
        .sensoryFeedback(.success, trigger: acceptedTerms)
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
            PrimaryButton(title: L("createNewAccount")) {
                proceed(to: .signup)
            }
            .accessibilityIdentifier("welcome-create-account")
            Button {
                proceed(to: .login)
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

    private func proceed(to destination: Destination) {
        guard acceptedTerms else {
            pendingDestination = destination
            showTermsPrompt = true
            return
        }
        open(destination)
    }

    private func acceptTerms() {
        acceptedTerms = true
        guard let destination = pendingDestination else { return }
        pendingDestination = nil
        open(destination)
    }

    private func open(_ destination: Destination) {
        switch destination {
        case .signup: onSignup()
        case .login: onLogin()
        }
    }
}
