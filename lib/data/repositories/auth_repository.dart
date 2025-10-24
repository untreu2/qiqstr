import '../../core/base/result.dart';
import '../services/auth_service.dart';
import '../services/validation_service.dart';

class AuthRepository {
  final AuthService _authService;
  final ValidationService _validationService;

  AuthRepository({
    required AuthService authService,
    required ValidationService validationService,
  })  : _authService = authService,
        _validationService = validationService;

  Future<Result<String?>> getCurrentUserNpub() async {
    try {
      return await _authService.getCurrentUserNpub();
    } catch (e) {
      return Result.error('Failed to get current user: ${e.toString()}');
    }
  }

  Future<Result<bool>> isAuthenticated() async {
    try {
      return await _authService.isAuthenticated();
    } catch (e) {
      return Result.error('Failed to check authentication: ${e.toString()}');
    }
  }

  Future<Result<AuthResult>> loginWithNsec(String nsec) async {
    try {
      final validationResult = _validationService.validateNsec(nsec);
      if (validationResult.isError) {
        return Result.error(validationResult.error!);
      }

      final loginResult = await _authService.loginWithNsec(nsec);

      return loginResult.fold(
        (npub) => Result.success(AuthResult(
          npub: npub,
          type: AuthResultType.login,
          isNewAccount: false,
        )),
        (error) => Result.error(error),
      );
    } catch (e) {
      return Result.error('Login failed: ${e.toString()}');
    }
  }

  Future<Result<AuthResult>> createNewAccount() async {
    try {
      final createResult = await _authService.createNewAccount();

      return createResult.fold(
        (npub) => Result.success(AuthResult(
          npub: npub,
          type: AuthResultType.newAccount,
          isNewAccount: true,
        )),
        (error) => Result.error(error),
      );
    } catch (e) {
      return Result.error('Account creation failed: ${e.toString()}');
    }
  }

  Future<Result<AuthResult>> loginWithPrivateKey(String privateKey) async {
    try {
      final validationResult = _validationService.validatePrivateKeyHex(privateKey);
      if (validationResult.isError) {
        return Result.error(validationResult.error!);
      }

      final loginResult = await _authService.loginWithPrivateKey(privateKey);

      return loginResult.fold(
        (npub) => Result.success(AuthResult(
          npub: npub,
          type: AuthResultType.login,
          isNewAccount: false,
        )),
        (error) => Result.error(error),
      );
    } catch (e) {
      return Result.error('Login with private key failed: ${e.toString()}');
    }
  }

  Future<Result<void>> logout() async {
    try {
      return await _authService.logout();
    } catch (e) {
      return Result.error('Logout failed: ${e.toString()}');
    }
  }

  Future<Result<String?>> getUserNsec() async {
    try {
      return await _authService.getUserNsec();
    } catch (e) {
      return Result.error('Failed to get NSEC: ${e.toString()}');
    }
  }

  Future<Result<String?>> getCurrentUserPrivateKey() async {
    try {
      return await _authService.getCurrentUserPrivateKey();
    } catch (e) {
      return Result.error('Failed to get private key: ${e.toString()}');
    }
  }

  Future<Result<bool>> isCurrentUser(String npub) async {
    try {
      final validationResult = _validationService.validateNpub(npub);
      if (validationResult.isError) {
        return Result.error(validationResult.error!);
      }

      return await _authService.isCurrentUser(npub);
    } catch (e) {
      return Result.error('Failed to check current user: ${e.toString()}');
    }
  }

  Future<Result<String?>> getCurrentUserPublicKeyHex() async {
    try {
      return await _authService.getCurrentUserPublicKeyHex();
    } catch (e) {
      return Result.error('Failed to get public key: ${e.toString()}');
    }
  }

  String? npubToHex(String npub) {
    try {
      return _authService.npubToHex(npub);
    } catch (e) {
      return null;
    }
  }

  String? hexToNpub(String hex) {
    try {
      return _authService.hexToNpub(hex);
    } catch (e) {
      return null;
    }
  }

  String? hexToNsec(String hexPrivateKey) {
    try {
      return _authService.hexToNsec(hexPrivateKey);
    } catch (e) {
      return null;
    }
  }

  String? nsecToHex(String nsec) {
    try {
      return _authService.nsecToHex(nsec);
    } catch (e) {
      return null;
    }
  }

  Future<Result<String?>> getCurrentUserNsec() async {
    try {
      return await _authService.getCurrentUserNsec();
    } catch (e) {
      return Result.error('Failed to get current user NSEC: ${e.toString()}');
    }
  }

  Future<Result<AuthResult>> recoverAccount({
    required String nsec,
  }) async {
    try {
      final validationResult = _validationService.validateNsec(nsec);
      if (validationResult.isError) {
        return Result.error(validationResult.error!);
      }

      final loginResult = await _authService.loginWithNsec(nsec);

      return loginResult.fold(
        (npub) => Result.success(AuthResult(
          npub: npub,
          type: AuthResultType.recovery,
          isNewAccount: false,
        )),
        (error) => Result.error('Account recovery failed: $error'),
      );
    } catch (e) {
      return Result.error('Account recovery failed: ${e.toString()}');
    }
  }

  Future<Result<AuthStatus>> getAuthStatus() async {
    try {
      final isAuthResult = await _authService.isAuthenticated();

      return isAuthResult.fold(
        (isAuthenticated) async {
          if (!isAuthenticated) {
            return const Result.success(AuthStatus(
              isAuthenticated: false,
              npub: null,
            ));
          }

          final npubResult = await _authService.getCurrentUserNpub();
          return npubResult.fold(
            (npub) => Result.success(AuthStatus(
              isAuthenticated: true,
              npub: npub,
            )),
            (error) => const Result.success(AuthStatus(
              isAuthenticated: false,
              npub: null,
            )),
          );
        },
        (error) => Result.error(error),
      );
    } catch (e) {
      return Result.error('Failed to get auth status: ${e.toString()}');
    }
  }

  Future<Result<void>> clearAllData() async {
    try {
      return await _authService.clearAllData();
    } catch (e) {
      return Result.error('Failed to clear data: ${e.toString()}');
    }
  }
}

class AuthResult {
  final String npub;
  final AuthResultType type;
  final bool isNewAccount;

  const AuthResult({
    required this.npub,
    required this.type,
    required this.isNewAccount,
  });

  @override
  String toString() => 'AuthResult(npub: $npub, type: $type, isNew: $isNewAccount)';
}

enum AuthResultType {
  login,
  newAccount,
  recovery,
}

class AuthStatus {
  final bool isAuthenticated;
  final String? npub;

  const AuthStatus({
    required this.isAuthenticated,
    this.npub,
  });

  @override
  String toString() => 'AuthStatus(authenticated: $isAuthenticated, npub: $npub)';
}
