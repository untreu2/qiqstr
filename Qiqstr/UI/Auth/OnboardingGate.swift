import SwiftUI

struct OnboardingGate: ViewModifier {
    @State private var session = Session.shared

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: isPresented) {
            OnboardingFlowView { session.isNewAccount = false }
                .id(session.account?.npub)
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { session.isNewAccount && session.phase == .ready },
            set: { if !$0 { session.isNewAccount = false } }
        )
    }
}

extension View {
    func onboardingGate() -> some View { modifier(OnboardingGate()) }
}

enum OnboardingStep: Hashable {
    case profile
    case follows
}

struct OnboardingFlowView: View {
    let onFinish: () -> Void
    @State private var path: [OnboardingStep] = []

    var body: some View {
        NavigationStack(path: $path) {
            OnboardingKeysView { path.append(.profile) }
                .navigationDestination(for: OnboardingStep.self) { step in
                    switch step {
                    case .profile:
                        OnboardingProfileView { path.append(.follows) }
                    case .follows:
                        SuggestedFollowsView(onFinish: onFinish)
                            .navigationBarBackButtonHidden()
                    }
                }
        }
        .tint(AppColors.textPrimary)
        .interactiveDismissDisabled()
    }
}

struct OnboardingStepIndicator: View {
    let current: Int
    var total = 3

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? AppColors.textPrimary : AppColors.overlayLight)
                    .frame(width: index == current ? 22 : 8, height: 8)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityElement()
        .accessibilityLabel(L("authStepOf", ["current": current, "total": total]))
        .accessibilityIdentifier("onboarding-step-\(current)")
    }
}
