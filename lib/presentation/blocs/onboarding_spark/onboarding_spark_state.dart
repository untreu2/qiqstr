import '../../../core/bloc/base/base_state.dart';

abstract class OnboardingSparkState extends BaseState {
  const OnboardingSparkState();
}

class OnboardingSparkInitial extends OnboardingSparkState {
  const OnboardingSparkInitial();
}

class OnboardingSparkLoading extends OnboardingSparkState {
  const OnboardingSparkLoading();
}

class OnboardingSparkReady extends OnboardingSparkState {
  final bool shouldNavigate;

  const OnboardingSparkReady({this.shouldNavigate = false});

  @override
  List<Object?> get props => [shouldNavigate];
}

class OnboardingSparkSkippedState extends OnboardingSparkState {
  const OnboardingSparkSkippedState();
}

class OnboardingSparkError extends OnboardingSparkState {
  final String message;

  const OnboardingSparkError(this.message);

  @override
  List<Object?> get props => [message];
}
