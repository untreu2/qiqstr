import '../../../core/bloc/base/base_event.dart';

abstract class AuthEvent extends BaseEvent {
  const AuthEvent();
}

class AuthCheckRequested extends AuthEvent {
  const AuthCheckRequested();
}

class LoginRequested extends AuthEvent {
  final String nsec;

  const LoginRequested(this.nsec);

  @override
  List<Object?> get props => [nsec];
}

class CreateAccountRequested extends AuthEvent {
  const CreateAccountRequested();
}

class LogoutRequested extends AuthEvent {
  const LogoutRequested();
}

class NsecInputChanged extends AuthEvent {
  final String nsec;

  const NsecInputChanged(this.nsec);

  @override
  List<Object?> get props => [nsec];
}

class ToggleNsecVisibilityRequested extends AuthEvent {
  const ToggleNsecVisibilityRequested();
}
