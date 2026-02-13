import '../../../core/bloc/base/base_state.dart';

abstract class OnboardingCoinosState extends BaseState {
  const OnboardingCoinosState();
}

class OnboardingCoinosInitial extends OnboardingCoinosState {
  const OnboardingCoinosInitial();
}

class OnboardingCoinosLoading extends OnboardingCoinosState {
  const OnboardingCoinosLoading();
}

class OnboardingCoinosConnected extends OnboardingCoinosState {
  final String username;
  final bool shouldNavigate;

  const OnboardingCoinosConnected({
    required this.username,
    this.shouldNavigate = false,
  });

  @override
  List<Object?> get props => [username, shouldNavigate];

  OnboardingCoinosConnected copyWith({
    String? username,
    bool? shouldNavigate,
  }) {
    return OnboardingCoinosConnected(
      username: username ?? this.username,
      shouldNavigate: shouldNavigate ?? this.shouldNavigate,
    );
  }
}

class OnboardingCoinosSkippedState extends OnboardingCoinosState {
  const OnboardingCoinosSkippedState();
}

class OnboardingCoinosError extends OnboardingCoinosState {
  final String message;

  const OnboardingCoinosError(this.message);

  @override
  List<Object?> get props => [message];
}
