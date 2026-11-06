import '../../../core/bloc/base/base_event.dart';

abstract class OnboardingSparkEvent extends BaseEvent {
  const OnboardingSparkEvent();
}

class OnboardingSparkWalletSetupRequested extends OnboardingSparkEvent {
  const OnboardingSparkWalletSetupRequested();
}

class OnboardingSparkSkipped extends OnboardingSparkEvent {
  const OnboardingSparkSkipped();
}

class OnboardingSparkRestoreRequested extends OnboardingSparkEvent {
  final String entropyHex;
  const OnboardingSparkRestoreRequested(this.entropyHex);

  @override
  List<Object?> get props => [entropyHex];
}
