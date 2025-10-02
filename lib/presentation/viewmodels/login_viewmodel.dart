import 'dart:async';

import 'package:flutter/widgets.dart';
import '../../core/base/base_view_model.dart';
import '../../core/base/ui_state.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/services/validation_service.dart';

/// ViewModel for the login screen
/// Handles login, account creation, and input validation
class LoginViewModel extends BaseViewModel with CommandMixin {
  final AuthRepository _authRepository;
  final ValidationService _validationService;

  LoginViewModel({
    required AuthRepository authRepository,
    required ValidationService validationService,
  })  : _authRepository = authRepository,
        _validationService = validationService;

  // State
  UIState<AuthResult> _authState = const InitialState();
  UIState<AuthResult> get authState => _authState;

  String _nsecInput = '';
  String get nsecInput => _nsecInput;

  ValidationResult _nsecValidation = ValidationResult.valid();
  ValidationResult get nsecValidation => _nsecValidation;

  bool _obscureNsec = true;
  bool get obscureNsec => _obscureNsec;

  // Commands - simple approach to avoid initialization issues
  late final SimpleCommand loginCommand;
  late final SimpleCommand createAccountCommand;
  late final SimpleCommand toggleNsecVisibilityCommand;

  @override
  void initialize() {
    super.initialize();

    // Initialize commands directly
    loginCommand = SimpleCommand(loginWithNsec);
    createAccountCommand = SimpleCommand(createNewAccount);
    toggleNsecVisibilityCommand = SimpleCommand(_toggleNsecVisibility);

    // Check for existing authentication
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkExistingAuth();
    });
  }

  /// Toggle NSEC visibility (async wrapper)
  Future<void> _toggleNsecVisibility() async {
    toggleNsecVisibility();
  }

  /// Check if user is already authenticated
  Future<void> _checkExistingAuth() async {
    await executeOperation('checkAuth', () async {
      final authStatusResult = await _authRepository.getAuthStatus();

      authStatusResult.fold(
        (authStatus) {
          if (authStatus.isAuthenticated && authStatus.npub != null) {
            _authState = LoadedState(AuthResult(
              npub: authStatus.npub!,
              type: AuthResultType.login,
              isNewAccount: false,
            ));
          } else {
            _authState = const InitialState();
          }
        },
        (error) {
          _authState = const InitialState();
          // Don't show error for missing auth - this is normal for new users
        },
      );
    }, showLoading: false);
  }

  /// Update NSEC input and validate
  void updateNsecInput(String nsec) {
    _nsecInput = nsec.trim();
    _validateNsec();
    safeNotifyListeners();
  }

  /// Validate current NSEC input
  void _validateNsec() {
    if (_nsecInput.isEmpty) {
      _nsecValidation = ValidationResult.valid();
      return;
    }

    final validationResult = _validationService.validateNsec(_nsecInput);
    _nsecValidation = ValidationResult.fromResult(validationResult);
  }

  /// Toggle NSEC visibility
  void toggleNsecVisibility() {
    _obscureNsec = !_obscureNsec;
    safeNotifyListeners();
  }

  /// Login with NSEC
  Future<void> loginWithNsec() async {
    await executeOperation('login', () async {
      _authState = const LoadingState();
      safeNotifyListeners();

      final result = await _authRepository.loginWithNsec(_nsecInput);

      result.fold(
        (authResult) {
          _authState = LoadedState(authResult);
        },
        (error) {
          _authState = ErrorState(error);
        },
      );

      safeNotifyListeners();
    }, showLoading: false);
  }

  /// Create new account
  Future<void> createNewAccount() async {
    await executeOperation('createAccount', () async {
      _authState = const LoadingState();
      safeNotifyListeners();

      final result = await _authRepository.createNewAccount();

      result.fold(
        (authResult) {
          _authState = LoadedState(authResult);
        },
        (error) {
          _authState = ErrorState(error);
        },
      );

      safeNotifyListeners();
    }, showLoading: false);
  }

  /// Clear any error state
  @override
  void clearError() {
    if (_authState.isError) {
      _authState = const InitialState();
      safeNotifyListeners();
    }
  }

  /// Get current validation state for UI
  bool get canLogin => _nsecInput.isNotEmpty && _nsecValidation.isValid && !_authState.isLoading;

  bool get canCreateAccount => !_authState.isLoading;

  /// Check if we're in a loading state
  @override
  bool get isLoading => _authState.isLoading;

  /// Get error message if any
  String? get errorMessage => _authState.error;

  /// Check if login was successful
  bool get isLoginSuccessful => _authState.isLoaded;

  /// Get the authentication result if available
  AuthResult? get authResult => _authState.data;

  @override
  void onRetry() {
    // Clear error and allow user to try again
    clearError();
  }
}

/// Command for login operation
class LoginCommand extends ParameterlessCommand {
  final LoginViewModel _viewModel;

  LoginCommand(this._viewModel);

  @override
  Future<void> executeImpl() => _viewModel.loginWithNsec();
}

/// Command for creating new account
class CreateAccountCommand extends ParameterlessCommand {
  final LoginViewModel _viewModel;

  CreateAccountCommand(this._viewModel);

  @override
  Future<void> executeImpl() => _viewModel.createNewAccount();
}

/// Command for toggling NSEC visibility
class ToggleNsecVisibilityCommand extends ParameterlessCommand {
  final LoginViewModel _viewModel;

  ToggleNsecVisibilityCommand(this._viewModel);

  @override
  Future<void> executeImpl() async {
    _viewModel.toggleNsecVisibility();
  }
}
