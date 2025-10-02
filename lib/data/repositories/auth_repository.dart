import '../../core/base/result.dart';
import '../services/auth_service.dart';
import '../services/validation_service.dart';

/// Repository for authentication operations
/// Handles business logic for login, logout, and user management
class AuthRepository {
  final AuthService _authService;
  final ValidationService _validationService;

  AuthRepository({
    required AuthService authService,
    required ValidationService validationService,
  })  : _authService = authService,
        _validationService = validationService;

  /// Get the currently logged-in user's npub
  Future<Result<String?>> getCurrentUserNpub() async {
    try {
      return await _authService.getCurrentUserNpub();
    } catch (e) {
      return Result.error('Failed to get current user: ${e.toString()}');
    }
  }

  /// Check if user is currently authenticated
  Future<Result<bool>> isAuthenticated() async {
    try {
      return await _authService.isAuthenticated();
    } catch (e) {
      return Result.error('Failed to check authentication: ${e.toString()}');
    }
  }

  /// Login with NSEC with validation
  Future<Result<AuthResult>> loginWithNsec(String nsec) async {
    try {
      // Validate NSEC format first
      final validationResult = _validationService.validateNsec(nsec);
      if (validationResult.isError) {
        return Result.error(validationResult.error!);
      }

      // Attempt login
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

  /// Create a new account
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

  /// Login with private key (hex format)
  Future<Result<AuthResult>> loginWithPrivateKey(String privateKey) async {
    try {
      // Validate private key format first
      final validationResult = _validationService.validatePrivateKeyHex(privateKey);
      if (validationResult.isError) {
        return Result.error(validationResult.error!);
      }

      // Attempt login
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

  /// Logout user
  Future<Result<void>> logout() async {
    try {
      return await _authService.logout();
    } catch (e) {
      return Result.error('Logout failed: ${e.toString()}');
    }
  }

  /// Get user's NSEC for backup purposes
  Future<Result<String?>> getUserNsec() async {
    try {
      return await _authService.getUserNsec();
    } catch (e) {
      return Result.error('Failed to get NSEC: ${e.toString()}');
    }
  }

  /// Get user's private key (for advanced operations)
  Future<Result<String?>> getCurrentUserPrivateKey() async {
    try {
      return await _authService.getCurrentUserPrivateKey();
    } catch (e) {
      return Result.error('Failed to get private key: ${e.toString()}');
    }
  }

  /// Check if the provided npub belongs to the current user
  Future<Result<bool>> isCurrentUser(String npub) async {
    try {
      // Validate npub format first
      final validationResult = _validationService.validateNpub(npub);
      if (validationResult.isError) {
        return Result.error(validationResult.error!);
      }

      return await _authService.isCurrentUser(npub);
    } catch (e) {
      return Result.error('Failed to check current user: ${e.toString()}');
    }
  }

  /// Get current user's public key in hex format
  Future<Result<String?>> getCurrentUserPublicKeyHex() async {
    try {
      return await _authService.getCurrentUserPublicKeyHex();
    } catch (e) {
      return Result.error('Failed to get public key: ${e.toString()}');
    }
  }

  /// Convert npub to hex format (utility method)
  String? npubToHex(String npub) {
    try {
      return _authService.npubToHex(npub);
    } catch (e) {
      return null;
    }
  }

  /// Convert hex to npub format (utility method)
  String? hexToNpub(String hex) {
    try {
      return _authService.hexToNpub(hex);
    } catch (e) {
      return null;
    }
  }

  /// Convert hex private key to nsec format (utility method)
  String? hexToNsec(String hexPrivateKey) {
    try {
      return _authService.hexToNsec(hexPrivateKey);
    } catch (e) {
      return null;
    }
  }

  /// Convert nsec to hex format (utility method)
  String? nsecToHex(String nsec) {
    try {
      return _authService.nsecToHex(nsec);
    } catch (e) {
      return null;
    }
  }

  /// Get current user's NSEC (generated from hex private key)
  Future<Result<String?>> getCurrentUserNsec() async {
    try {
      return await _authService.getCurrentUserNsec();
    } catch (e) {
      return Result.error('Failed to get current user NSEC: ${e.toString()}');
    }
  }

  /// Validate credentials and attempt recovery
  Future<Result<AuthResult>> recoverAccount({
    required String nsec,
  }) async {
    try {
      // This is essentially the same as login but with recovery context
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

  /// Get authentication status with user info
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

  /// Clear all authentication data (for development/testing)
  Future<Result<void>> clearAllData() async {
    try {
      return await _authService.clearAllData();
    } catch (e) {
      return Result.error('Failed to clear data: ${e.toString()}');
    }
  }
}

/// Result of authentication operations
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

/// Types of authentication results
enum AuthResultType {
  login, // Normal login
  newAccount, // New account creation
  recovery, // Account recovery
}

/// Current authentication status
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
