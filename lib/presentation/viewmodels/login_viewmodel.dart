import 'dart:async';

import 'package:flutter/widgets.dart';
import '../../core/base/base_view_model.dart';
import '../../core/base/ui_state.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/services/validation_service.dart';

class LoginViewModel extends BaseViewModel with CommandMixin {
  final AuthRepository _authRepository;
  final ValidationService _validationService;

  LoginViewModel({
    required AuthRepository authRepository,
    required ValidationService validationService,
  })  : _authRepository = authRepository,
        _validationService = validationService;

  UIState<AuthResult> _authState = const InitialState();
  UIState<AuthResult> get authState => _authState;

  String _nsecInput = '';
  String get nsecInput => _nsecInput;

  ValidationResult _nsecValidation = ValidationResult.valid();
  ValidationResult get nsecValidation => _nsecValidation;

  bool _obscureNsec = true;
  bool get obscureNsec => _obscureNsec;

  late final SimpleCommand loginCommand;
  late final SimpleCommand createAccountCommand;
  late final SimpleCommand toggleNsecVisibilityCommand;

  @override
  void initialize() {
    super.initialize();

    loginCommand = SimpleCommand(loginWithNsec);
    createAccountCommand = SimpleCommand(createNewAccount);
    toggleNsecVisibilityCommand = SimpleCommand(_toggleNsecVisibility);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkExistingAuth();
    });
  }

  Future<void> _toggleNsecVisibility() async {
    toggleNsecVisibility();
  }

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
        },
      );
    }, showLoading: false);
  }

  void updateNsecInput(String nsec) {
    _nsecInput = nsec.trim();
    _validateNsec();
    safeNotifyListeners();
  }

  void _validateNsec() {
    if (_nsecInput.isEmpty) {
      _nsecValidation = ValidationResult.valid();
      return;
    }

    final validationResult = _validationService.validateNsec(_nsecInput);
    _nsecValidation = ValidationResult.fromResult(validationResult);
  }

  void toggleNsecVisibility() {
    _obscureNsec = !_obscureNsec;
    safeNotifyListeners();
  }

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

  @override
  void clearError() {
    if (_authState.isError) {
      _authState = const InitialState();
      safeNotifyListeners();
    }
  }

  bool get canLogin => _nsecInput.isNotEmpty && _nsecValidation.isValid && !_authState.isLoading;

  bool get canCreateAccount => !_authState.isLoading;

  @override
  bool get isLoading => _authState.isLoading;

  String? get errorMessage => _authState.error;

  bool get isLoginSuccessful => _authState.isLoaded;

  AuthResult? get authResult => _authState.data;

  @override
  void onRetry() {
    clearError();
  }
}

class LoginCommand extends ParameterlessCommand {
  final LoginViewModel _viewModel;

  LoginCommand(this._viewModel);

  @override
  Future<void> executeImpl() => _viewModel.loginWithNsec();
}

class CreateAccountCommand extends ParameterlessCommand {
  final LoginViewModel _viewModel;

  CreateAccountCommand(this._viewModel);

  @override
  Future<void> executeImpl() => _viewModel.createNewAccount();
}

class ToggleNsecVisibilityCommand extends ParameterlessCommand {
  final LoginViewModel _viewModel;

  ToggleNsecVisibilityCommand(this._viewModel);

  @override
  Future<void> executeImpl() async {
    _viewModel.toggleNsecVisibility();
  }
}
