import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/validation_service.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthService _authService;
  final ValidationService _validationService;

  AuthBloc({
    required AuthService authService,
    required ValidationService validationService,
  })  : _authService = authService,
        _validationService = validationService,
        super(const AuthInitial()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<LoginRequested>(_onLoginRequested);
    on<CreateAccountRequested>(_onCreateAccountRequested);
    on<LogoutRequested>(_onLogoutRequested);
    on<NsecInputChanged>(_onNsecInputChanged);
    on<ToggleNsecVisibilityRequested>(_onToggleNsecVisibilityRequested);
  }

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    final result = await _authService.getAuthStatus();

    result.fold(
      (authStatus) {
        if (authStatus.isAuthenticated && authStatus.npub != null) {
          emit(AuthAuthenticated(npub: authStatus.npub!));
        } else {
          emit(const AuthUnauthenticated());
        }
      },
      (error) => emit(AuthError(error)),
    );
  }

  Future<void> _onLoginRequested(
    LoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    final result = await _authService.loginWithNsecValidated(event.nsec);

    result.fold(
      (authResult) => emit(AuthAuthenticated(
        npub: authResult.npub,
        isNewAccount: authResult.isNewAccount,
      )),
      (error) => emit(AuthError(error)),
    );
  }

  Future<void> _onCreateAccountRequested(
    CreateAccountRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    final result = await _authService.createNewAccountWithResult();

    result.fold(
      (authResult) => emit(AuthAuthenticated(
        npub: authResult.npub,
        isNewAccount: true,
      )),
      (error) => emit(AuthError(error)),
    );
  }

  Future<void> _onLogoutRequested(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    final result = await _authService.logout();

    result.fold(
      (_) => emit(const AuthUnauthenticated()),
      (error) => emit(AuthError(error)),
    );
  }

  void _onNsecInputChanged(
    NsecInputChanged event,
    Emitter<AuthState> emit,
  ) {
    final nsec = event.nsec.trim();
    final currentInputState = state is AuthInputState
        ? (state as AuthInputState)
        : const AuthInputState(nsecInput: '', isValid: false);

    if (nsec.isEmpty) {
      emit(currentInputState.copyWith(
        nsecInput: nsec,
        isValid: false,
        validationError: null,
      ));
      return;
    }

    final validationResult = _validationService.validateNsec(nsec);
    final isValid = validationResult.isSuccess;
    final error = validationResult.isError ? validationResult.error : null;

    emit(currentInputState.copyWith(
      nsecInput: nsec,
      isValid: isValid,
      validationError: error,
    ));
  }

  void _onToggleNsecVisibilityRequested(
    ToggleNsecVisibilityRequested event,
    Emitter<AuthState> emit,
  ) {
    final currentInputState = state is AuthInputState
        ? (state as AuthInputState)
        : const AuthInputState(nsecInput: '', isValid: false);

    emit(currentInputState.copyWith(
      obscureNsec: !currentInputState.obscureNsec,
    ));
  }
}
