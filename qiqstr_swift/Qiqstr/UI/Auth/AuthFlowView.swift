import SwiftUI

enum AuthStep: Hashable {
    case login
    case signup
}

struct AuthFlowView: View {
    @State private var path: [AuthStep] = []

    var body: some View {
        NavigationStack(path: $path) {
            AuthWelcomeView(
                onLogin: { path.append(.login) },
                onSignup: { path.append(.signup) }
            )
            .authDestinations()
        }
    }
}

extension View {
    func authDestinations() -> some View {
        navigationDestination(for: AuthStep.self) { step in
            switch step {
            case .login: AuthLoginView()
            case .signup: AuthSignupView()
            }
        }
    }
}
