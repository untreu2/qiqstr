import SwiftUI

@MainActor
@Observable
final class AuthSignupViewModel {
    var isLoading = false
    var errorMessage: String?
    var failureCount = 0

    func create() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            _ = try await Session.shared.createAccount()
        } catch {
            errorMessage = L("errorPrefix", ["message": coreMessage(error)])
            failureCount += 1
        }
        isLoading = false
    }
}

struct AuthSignupView: View {
    @State private var model = AuthSignupViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                AuthHeader(title: L("createNewAccount"), subtitle: L("signupSubtitle"))
                VStack(alignment: .leading, spacing: 24) {
                    AuthFeatureRow(systemImage: "key", text: L("signupFeatureKeys"))
                    AuthFeatureRow(systemImage: "checkmark.shield", text: L("signupFeatureBackup"))
                    AuthFeatureRow(systemImage: "person", text: L("signupFeatureProfile"))
                }
                .padding(.horizontal, 4)
                if let message = model.errorMessage {
                    AuthErrorText(message: message)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .background(AppColors.background)
        .overlay {
            if model.isLoading {
                VStack(spacing: 18) {
                    ProgressView().controlSize(.large)
                    Text(L("signupCreating"))
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.background)
                .transition(.opacity)
                .accessibilityIdentifier("signup-creating")
            }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: L("createNewAccount"), isLoading: model.isLoading) {
                Task { await model.create() }
            }
            .accessibilityIdentifier("signup-create")
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(AppColors.background)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.isLoading)
        .animation(.smooth, value: model.isLoading)
        .animation(.snappy, value: model.errorMessage)
        .sensoryFeedback(.error, trigger: model.failureCount)
    }
}
