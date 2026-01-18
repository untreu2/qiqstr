import '../../../core/bloc/base/base_state.dart';

abstract class AuthState extends BaseState {
  const AuthState();
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  final String npub;
  final bool isNewAccount;

  const AuthAuthenticated({
    required this.npub,
    this.isNewAccount = false,
  });

  @override
  List<Object?> get props => [npub, isNewAccount];
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthError extends AuthState {
  final String message;

  const AuthError(this.message);

  @override
  List<Object?> get props => [message];
}

class AuthInputState extends AuthState {
  final String nsecInput;
  final bool isValid;
  final String? validationError;
  final bool obscureNsec;

  const AuthInputState({
    required this.nsecInput,
    required this.isValid,
    this.validationError,
    this.obscureNsec = true,
  });

  @override
  List<Object?> get props => [nsecInput, isValid, validationError, obscureNsec];

  AuthInputState copyWith({
    String? nsecInput,
    bool? isValid,
    String? validationError,
    bool? obscureNsec,
  }) {
    return AuthInputState(
      nsecInput: nsecInput ?? this.nsecInput,
      isValid: isValid ?? this.isValid,
      validationError: validationError ?? this.validationError,
      obscureNsec: obscureNsec ?? this.obscureNsec,
    );
  }
}
