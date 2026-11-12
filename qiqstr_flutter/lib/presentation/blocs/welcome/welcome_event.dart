import '../../../core/bloc/base/base_event.dart';

sealed class WelcomeEvent extends BaseEvent {
  const WelcomeEvent();
}

class WelcomeTermsChanged extends WelcomeEvent {
  final bool accepted;

  const WelcomeTermsChanged(this.accepted);

  @override
  List<Object?> get props => [accepted];
}

class WelcomeTermsRequired extends WelcomeEvent {
  const WelcomeTermsRequired();
}
