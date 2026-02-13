import '../../../core/bloc/base/base_event.dart';

abstract class OnboardingCoinosEvent extends BaseEvent {
  const OnboardingCoinosEvent();
}

class OnboardingCoinosConnectRequested extends OnboardingCoinosEvent {
  final String? recaptchaToken;

  const OnboardingCoinosConnectRequested({this.recaptchaToken});

  @override
  List<Object?> get props => [recaptchaToken];
}

class OnboardingCoinosSkipped extends OnboardingCoinosEvent {
  const OnboardingCoinosSkipped();
}
