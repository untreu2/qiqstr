import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nostr/nostr.dart';

import '../../core/base/result.dart';

/// Service responsible for authentication operations
/// Handles secure storage of credentials and key management
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static AuthService get instance => _instance;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// Get the currently logged-in user's npub
  Future<Result<String?>> getCurrentUserNpub() async {
    try {
      final npub = await _secureStorage.read(key: 'npub');
      return Result.success(npub);
    } catch (e) {
      return Result.error('Failed to read current user: ${e.toString()}');
    }
  }

  /// Get the currently logged-in user's private key
  Future<Result<String?>> getCurrentUserPrivateKey() async {
    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      return Result.success(privateKey);
    } catch (e) {
      return Result.error('Failed to read private key: ${e.toString()}');
    }
  }

  /// Check if user is currently authenticated
  Future<Result<bool>> isAuthenticated() async {
    try {
      final npub = await _secureStorage.read(key: 'npub');
      final privateKey = await _secureStorage.read(key: 'privateKey');

      final isAuth = npub != null && npub.isNotEmpty && privateKey != null && privateKey.isNotEmpty;

      return Result.success(isAuth);
    } catch (e) {
      return Result.error('Failed to check authentication status: ${e.toString()}');
    }
  }

  /// Login with NSEC (private key)
  Future<Result<String>> loginWithNsec(String nsec) async {
    try {
      if (nsec.trim().isEmpty) {
        return const Result.error('NSEC cannot be empty');
      }

      if (!nsec.startsWith('nsec1')) {
        return const Result.error('NSEC must start with "nsec1"');
      }

      if (nsec.length < 63) {
        return const Result.error('NSEC is too short');
      }

      // Validate and decode NSEC
      String privateKey;
      try {
        privateKey = Nip19.decodePrivkey(nsec);
      } catch (e) {
        return const Result.error('Invalid NSEC format');
      }

      // Generate npub from private key
      String npub;
      try {
        final keychain = Keychain(privateKey);
        npub = Nip19.encodePubkey(keychain.public);
      } catch (e) {
        return const Result.error('Failed to generate public key from NSEC');
      }

      // Store credentials securely (only hex format internally)
      await Future.wait([
        _secureStorage.write(key: 'npub', value: npub),
        _secureStorage.write(key: 'privateKey', value: privateKey),
      ]);

      return Result.success(npub);
    } catch (e) {
      return Result.error('Login failed: ${e.toString()}');
    }
  }

  /// Create a new account with randomly generated keys
  Future<Result<String>> createNewAccount() async {
    try {
      // Generate new key pair
      final keychain = Keychain.generate();
      final privateKey = keychain.private;
      final publicKey = keychain.public;

      // Encode to bech32 format
      final npub = Nip19.encodePubkey(publicKey);

      // Store credentials securely (only hex format internally)
      await Future.wait([
        _secureStorage.write(key: 'npub', value: npub),
        _secureStorage.write(key: 'privateKey', value: privateKey),
      ]);

      return Result.success(npub);
    } catch (e) {
      return Result.error('Failed to create new account: ${e.toString()}');
    }
  }

  /// Login with private key (hex format)
  Future<Result<String>> loginWithPrivateKey(String privateKey) async {
    try {
      if (privateKey.trim().isEmpty) {
        return const Result.error('Private key cannot be empty');
      }

      if (privateKey.length != 64) {
        return const Result.error('Private key must be 64 characters long');
      }

      // Validate private key format
      try {
        int.parse(privateKey, radix: 16);
      } catch (e) {
        return const Result.error('Private key must be valid hexadecimal');
      }

      // Generate public key and npub
      String npub;
      try {
        final keychain = Keychain(privateKey);
        npub = Nip19.encodePubkey(keychain.public);
      } catch (e) {
        return const Result.error('Failed to generate public key from private key');
      }

      // Store credentials securely (only hex format internally)
      await Future.wait([
        _secureStorage.write(key: 'npub', value: npub),
        _secureStorage.write(key: 'privateKey', value: privateKey),
      ]);

      return Result.success(npub);
    } catch (e) {
      return Result.error('Login with private key failed: ${e.toString()}');
    }
  }

  /// Logout user and clear all stored credentials
  Future<Result<void>> logout() async {
    try {
      await Future.wait([
        _secureStorage.delete(key: 'npub'),
        _secureStorage.delete(key: 'privateKey'),
      ]);

      return const Result.success(null);
    } catch (e) {
      return Result.error('Logout failed: ${e.toString()}');
    }
  }

  /// Get user's NSEC (encoded private key) - now generated from hex
  Future<Result<String?>> getUserNsec() async {
    return getCurrentUserNsec();
  }

  /// Update stored credentials (useful for account recovery)
  Future<Result<void>> updateCredentials({
    required String npub,
    required String privateKey,
  }) async {
    try {
      await Future.wait([
        _secureStorage.write(key: 'npub', value: npub),
        _secureStorage.write(key: 'privateKey', value: privateKey),
      ]);

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to update credentials: ${e.toString()}');
    }
  }

  /// Check if the provided npub belongs to the current user
  Future<Result<bool>> isCurrentUser(String npub) async {
    try {
      final currentNpub = await _secureStorage.read(key: 'npub');
      return Result.success(currentNpub == npub);
    } catch (e) {
      return Result.error('Failed to check current user: ${e.toString()}');
    }
  }

  /// Get public key in hex format from stored npub
  Future<Result<String?>> getCurrentUserPublicKeyHex() async {
    try {
      final npub = await _secureStorage.read(key: 'npub');
      if (npub == null || npub.isEmpty) {
        return const Result.success(null);
      }

      if (npub.startsWith('npub1')) {
        final publicKeyHex = decodeBasicBech32(npub, 'npub');
        return Result.success(publicKeyHex);
      } else if (npub.length == 64) {
        // Already in hex format
        return Result.success(npub);
      } else {
        return const Result.error('Invalid npub format');
      }
    } catch (e) {
      return Result.error('Failed to get public key: ${e.toString()}');
    }
  }

  /// Convert npub to hex format
  String? npubToHex(String npub) {
    try {
      if (npub.startsWith('npub1')) {
        return decodeBasicBech32(npub, 'npub');
      } else if (npub.length == 64) {
        return npub; // Already hex
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Convert hex to npub format
  String? hexToNpub(String hex) {
    try {
      if (hex.length == 64) {
        return Nip19.encodePubkey(hex);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Convert hex private key to nsec format for display
  String? hexToNsec(String hexPrivateKey) {
    try {
      if (hexPrivateKey.length == 64) {
        return Nip19.encodePrivkey(hexPrivateKey);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Convert nsec to hex format
  String? nsecToHex(String nsec) {
    try {
      if (nsec.startsWith('nsec1')) {
        return decodeBasicBech32(nsec, 'nsec');
      } else if (nsec.length == 64) {
        return nsec; // Already hex
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get current user's nsec (generated from hex private key)
  Future<Result<String?>> getCurrentUserNsec() async {
    try {
      final privateKeyResult = await getCurrentUserPrivateKey();
      if (privateKeyResult.isError || privateKeyResult.data == null) {
        return Result.success(null);
      }

      final hexPrivateKey = privateKeyResult.data!;
      final nsec = hexToNsec(hexPrivateKey);
      return Result.success(nsec);
    } catch (e) {
      return Result.error('Failed to get NSEC: ${e.toString()}');
    }
  }

  /// Decode basic bech32 string to hex
  String? decodeBasicBech32(String bech32String, String expectedPrefix) {
    try {
      if (expectedPrefix == 'npub') {
        return Nip19.decodePubkey(bech32String);
      } else if (expectedPrefix == 'nsec') {
        return Nip19.decodePrivkey(bech32String);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Clear all authentication data (for development/testing)
  Future<Result<void>> clearAllData() async {
    try {
      await _secureStorage.deleteAll();
      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to clear all data: ${e.toString()}');
    }
  }
}
