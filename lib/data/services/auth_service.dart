import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/base/result.dart';
import '../../core/di/app_di.dart';
import 'coinos_service.dart';
import 'rust_nostr_bridge.dart';
import 'validation_service.dart';

class StoredAccount {
  final String npub;
  final String privateKeyHex;
  final String? mnemonic;

  const StoredAccount({
    required this.npub,
    required this.privateKeyHex,
    this.mnemonic,
  });

  Map<String, dynamic> toJson() => {
        'npub': npub,
        'privateKeyHex': privateKeyHex,
        if (mnemonic != null) 'mnemonic': mnemonic,
      };

  factory StoredAccount.fromJson(Map<String, dynamic> json) => StoredAccount(
        npub: json['npub'] as String,
        privateKeyHex: json['privateKeyHex'] as String,
        mnemonic: json['mnemonic'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is StoredAccount && npub == other.npub;

  @override
  int get hashCode => npub.hashCode;
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
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static AuthService get instance => _instance;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  String? _cachedPubkeyHex;
  String? _cachedNpub;

  String? get currentUserPubkeyHex => _cachedPubkeyHex;
  String? get currentUserNpub => _cachedNpub;

  Future<void> refreshCache() async {
    final npubResult = await getCurrentUserNpub();
    if (npubResult.isSuccess && npubResult.data != null) {
      _cachedNpub = npubResult.data;
      _cachedPubkeyHex = npubToHex(npubResult.data!);

      // Migrate existing account to multi-account list if not already there
      final accounts = await getStoredAccounts();
      if (accounts.isEmpty) {
        await _addCurrentAccountToList();
      }
    }
  }

  // --- Multi-account support ---

  static const String _accountsKey = 'stored_accounts';

  Future<List<StoredAccount>> getStoredAccounts() async {
    try {
      final raw = await _secureStorage.read(key: _accountsKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => StoredAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAccountToList(StoredAccount account) async {
    final accounts = await getStoredAccounts();
    accounts.removeWhere((a) => a.npub == account.npub);
    accounts.insert(0, account);
    await _secureStorage.write(
      key: _accountsKey,
      value: jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
  }

  Future<void> removeAccountFromList(String npub) async {
    final accounts = await getStoredAccounts();
    accounts.removeWhere((a) => a.npub == npub);
    await _secureStorage.write(
      key: _accountsKey,
      value: jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
  }

  Future<Result<String>> switchAccount(String npub) async {
    try {
      final accounts = await getStoredAccounts();
      final target = accounts.where((a) => a.npub == npub).firstOrNull;
      if (target == null) {
        return const Result.error('Account not found');
      }

      await Future.wait([
        _secureStorage.write(key: 'npub', value: target.npub),
        _secureStorage.write(key: 'privateKey', value: target.privateKeyHex),
      ]);

      if (target.mnemonic != null) {
        await _secureStorage.write(key: 'mnemonic', value: target.mnemonic!);
      } else {
        await _secureStorage.delete(key: 'mnemonic');
      }

      _cachedNpub = target.npub;
      _cachedPubkeyHex = npubToHex(target.npub);

      return Result.success(target.npub);
    } catch (e) {
      return Result.error('Failed to switch account: ${e.toString()}');
    }
  }

  Future<void> _addCurrentAccountToList() async {
    final npub = await _secureStorage.read(key: 'npub');
    final privateKey = await _secureStorage.read(key: 'privateKey');
    final mnemonic = await _secureStorage.read(key: 'mnemonic');
    if (npub != null && privateKey != null) {
      await _saveAccountToList(StoredAccount(
        npub: npub,
        privateKeyHex: privateKey,
        mnemonic: mnemonic,
      ));
    }
  }

  Future<Result<String?>> getCurrentUserNpub() async {
    try {
      final npub = await _secureStorage.read(key: 'npub');
      return Result.success(npub);
    } catch (e) {
      return Result.error('Failed to read current user: ${e.toString()}');
    }
  }

  Future<Result<String?>> getCurrentUserPrivateKey() async {
    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      return Result.success(privateKey);
    } catch (e) {
      return Result.error('Failed to read private key: ${e.toString()}');
    }
  }

  Future<Result<bool>> isAuthenticated() async {
    try {
      final npub = await _secureStorage.read(key: 'npub');
      final privateKey = await _secureStorage.read(key: 'privateKey');

      final isAuth = npub != null &&
          npub.isNotEmpty &&
          privateKey != null &&
          privateKey.isNotEmpty;

      return Result.success(isAuth);
    } catch (e) {
      return Result.error(
          'Failed to check authentication status: ${e.toString()}');
    }
  }

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

      String privateKey;
      try {
        privateKey = Nip19.decode(nsec);
      } catch (e) {
        return const Result.error('Invalid NSEC format');
      }

      String npub;
      try {
        final publicKey = Bip340.getPublicKey(privateKey);
        npub = Nip19.encodePubKey(publicKey);
      } catch (e) {
        return const Result.error('Failed to generate public key from NSEC');
      }

      await Future.wait([
        _secureStorage.write(key: 'npub', value: npub),
        _secureStorage.write(key: 'privateKey', value: privateKey),
      ]);

      _cachedNpub = npub;
      _cachedPubkeyHex = npubToHex(npub);

      await _saveAccountToList(StoredAccount(
        npub: npub,
        privateKeyHex: privateKey,
      ));

      return Result.success(npub);
    } catch (e) {
      return Result.error('Login failed: ${e.toString()}');
    }
  }

  Future<Result<String>> createNewAccount() async {
    try {
      final keyPair = Bip340.generatePrivateKey();
      final privateKey = keyPair.privateKey!;
      final publicKey = keyPair.publicKey;

      final npub = Nip19.encodePubKey(publicKey);

      await Future.wait([
        _secureStorage.write(key: 'npub', value: npub),
        _secureStorage.write(key: 'privateKey', value: privateKey),
      ]);

      _cachedNpub = npub;
      _cachedPubkeyHex = npubToHex(npub);

      await _saveAccountToList(StoredAccount(
        npub: npub,
        privateKeyHex: privateKey,
      ));

      return Result.success(npub);
    } catch (e) {
      return Result.error('Failed to create new account: ${e.toString()}');
    }
  }

  Future<Result<String>> loginWithPrivateKey(String privateKey) async {
    try {
      if (privateKey.trim().isEmpty) {
        return const Result.error('Private key cannot be empty');
      }

      if (privateKey.length != 64) {
        return const Result.error('Private key must be 64 characters long');
      }

      try {
        int.parse(privateKey, radix: 16);
      } catch (e) {
        return const Result.error('Private key must be valid hexadecimal');
      }

      String npub;
      try {
        final publicKey = Bip340.getPublicKey(privateKey);
        npub = Nip19.encodePubKey(publicKey);
      } catch (e) {
        return const Result.error(
            'Failed to generate public key from private key');
      }

      await Future.wait([
        _secureStorage.write(key: 'npub', value: npub),
        _secureStorage.write(key: 'privateKey', value: privateKey),
      ]);

      _cachedNpub = npub;
      _cachedPubkeyHex = npubToHex(npub);

      await _saveAccountToList(StoredAccount(
        npub: npub,
        privateKeyHex: privateKey,
      ));

      return Result.success(npub);
    } catch (e) {
      return Result.error('Login with private key failed: ${e.toString()}');
    }
  }

  Future<Result<void>> logout() async {
    try {
      await Future.wait([
        _secureStorage.delete(key: 'npub'),
        _secureStorage.delete(key: 'privateKey'),
        _secureStorage.delete(key: 'mnemonic'),
        _secureStorage.delete(key: _accountsKey),
      ]);

      _cachedNpub = null;
      _cachedPubkeyHex = null;

      return const Result.success(null);
    } catch (e) {
      return Result.error('Logout failed: ${e.toString()}');
    }
  }

  Future<Result<String?>> getUserNsec() async {
    return getCurrentUserNsec();
  }

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

  Future<Result<bool>> isCurrentUser(String npub) async {
    try {
      final currentNpub = await _secureStorage.read(key: 'npub');
      return Result.success(currentNpub == npub);
    } catch (e) {
      return Result.error('Failed to check current user: ${e.toString()}');
    }
  }

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
        return Result.success(npub);
      } else {
        return const Result.error('Invalid npub format');
      }
    } catch (e) {
      return Result.error('Failed to get public key: ${e.toString()}');
    }
  }

  String? npubToHex(String npub) {
    try {
      if (npub.startsWith('npub1')) {
        return decodeBasicBech32(npub, 'npub');
      } else if (npub.length == 64) {
        return npub;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  String? hexToNpub(String hex) {
    try {
      if (hex.length == 64) {
        return Nip19.encodePubKey(hex);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  String? hexToNsec(String hexPrivateKey) {
    try {
      if (hexPrivateKey.length == 64) {
        return Nip19.encodePrivateKey(hexPrivateKey);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  String? nsecToHex(String nsec) {
    try {
      if (nsec.startsWith('nsec1')) {
        return decodeBasicBech32(nsec, 'nsec');
      } else if (nsec.length == 64) {
        return nsec;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

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

  String? decodeBasicBech32(String bech32String, String expectedPrefix) {
    try {
      if (expectedPrefix == 'npub') {
        return Nip19.decode(bech32String);
      } else if (expectedPrefix == 'nsec') {
        return Nip19.decode(bech32String);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<Result<void>> clearAllData() async {
    try {
      await _secureStorage.deleteAll();
      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to clear all data: ${e.toString()}');
    }
  }

  Future<Result<AuthResult>> loginWithNsecValidated(String nsec) async {
    final validationResult = ValidationService.instance.validateNsec(nsec);
    if (validationResult.isError) {
      return Result.error(validationResult.error!);
    }

    final loginResult = await loginWithNsec(nsec);
    return loginResult.fold(
      (npub) => Result.success(AuthResult(
        npub: npub,
        type: AuthResultType.login,
        isNewAccount: false,
      )),
      (error) => Result.error(error),
    );
  }

  Future<Result<AuthResult>> createNewAccountWithResult() async {
    final createResult = await createNewAccount();
    return createResult.fold(
      (npub) => Result.success(AuthResult(
        npub: npub,
        type: AuthResultType.newAccount,
        isNewAccount: true,
      )),
      (error) => Result.error(error),
    );
  }

  Future<Result<AuthResult>> loginWithPrivateKeyValidated(
      String privateKey) async {
    final validationResult =
        ValidationService.instance.validatePrivateKeyHex(privateKey);
    if (validationResult.isError) {
      return Result.error(validationResult.error!);
    }

    final loginResult = await loginWithPrivateKey(privateKey);
    return loginResult.fold(
      (npub) => Result.success(AuthResult(
        npub: npub,
        type: AuthResultType.login,
        isNewAccount: false,
      )),
      (error) => Result.error(error),
    );
  }

  Future<Result<AuthResult>> recoverAccount(String nsec) async {
    final validationResult = ValidationService.instance.validateNsec(nsec);
    if (validationResult.isError) {
      return Result.error(validationResult.error!);
    }

    final loginResult = await loginWithNsec(nsec);
    return loginResult.fold(
      (npub) => Result.success(AuthResult(
        npub: npub,
        type: AuthResultType.recovery,
        isNewAccount: false,
      )),
      (error) => Result.error('Account recovery failed: $error'),
    );
  }

  Future<Result<AuthStatus>> getAuthStatus() async {
    final isAuthResult = await isAuthenticated();
    return isAuthResult.fold(
      (isAuthenticated) async {
        if (!isAuthenticated) {
          return const Result.success(AuthStatus(
            isAuthenticated: false,
            npub: null,
          ));
        }

        final npubResult = await getCurrentUserNpub();
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
  }

  Future<Result<String>> generateMnemonic() async {
    try {
      final mnemonic = Bip39Bridge.generateMnemonic();
      return Result.success(mnemonic);
    } catch (e) {
      return Result.error('Failed to generate mnemonic: ${e.toString()}');
    }
  }

  Future<Result<String>> loginWithMnemonic(String mnemonic) async {
    try {
      if (mnemonic.trim().isEmpty) {
        return const Result.error('Mnemonic cannot be empty');
      }

      final words = mnemonic.trim().split(' ');
      if (words.length != 12) {
        return const Result.error('Mnemonic must be exactly 12 words');
      }

      final isValid = Bip39Bridge.validateMnemonic(mnemonic.trim());
      if (!isValid) {
        return const Result.error('Invalid mnemonic phrase');
      }

      final privateKey = Bip39Bridge.mnemonicToPrivateKey(mnemonic.trim());

      String npub;
      try {
        final publicKey = Bip340.getPublicKey(privateKey);
        npub = Nip19.encodePubKey(publicKey);
      } catch (e) {
        return const Result.error(
            'Failed to generate public key from mnemonic');
      }

      await Future.wait([
        _secureStorage.write(key: 'npub', value: npub),
        _secureStorage.write(key: 'privateKey', value: privateKey),
        _secureStorage.write(key: 'mnemonic', value: mnemonic.trim()),
      ]);

      _cachedNpub = npub;
      _cachedPubkeyHex = npubToHex(npub);

      await _saveAccountToList(StoredAccount(
        npub: npub,
        privateKeyHex: privateKey,
        mnemonic: mnemonic.trim(),
      ));

      return Result.success(npub);
    } catch (e) {
      return Result.error('Login with mnemonic failed: ${e.toString()}');
    }
  }

  Future<Result<String>> createAccountWithMnemonic() async {
    try {
      final mnemonicResult = await generateMnemonic();
      if (mnemonicResult.isError) {
        return Result.error(mnemonicResult.error!);
      }

      final mnemonic = mnemonicResult.data!;
      final loginResult = await loginWithMnemonic(mnemonic);

      if (loginResult.isError) {
        return Result.error(loginResult.error!);
      }

      return Result.success(loginResult.data!);
    } catch (e) {
      return Result.error(
          'Failed to create account with mnemonic: ${e.toString()}');
    }
  }

  Future<Result<String?>> getCurrentUserMnemonic() async {
    try {
      final mnemonic = await _secureStorage.read(key: 'mnemonic');
      return Result.success(mnemonic);
    } catch (e) {
      return Result.error('Failed to read mnemonic: ${e.toString()}');
    }
  }

  Future<Result<Map<String, dynamic>>> authenticateWithCoinos() async {
    try {
      final coinosService = AppDI.get<CoinosService>();
      final authResult = await coinosService.authenticateWithNostr();
      if (authResult.isError) {
        return Result.error(authResult.error!);
      }
      return Result.success(authResult.data!);
    } catch (e) {
      return Result.error(
          'Coinos Nostr authentication failed: ${e.toString()}');
    }
  }

  Future<Result<Map<String, dynamic>>> autoLoginCoinos() async {
    try {
      final coinosService = AppDI.get<CoinosService>();
      final authResult = await coinosService.autoLogin();
      if (authResult.isError) {
        return Result.error(authResult.error!);
      }
      return Result.success(authResult.data!);
    } catch (e) {
      return Result.error('Coinos auto-login failed: ${e.toString()}');
    }
  }

  Future<Result<bool>> isCoinosAuthenticated() async {
    try {
      final coinosService = AppDI.get<CoinosService>();
      return await coinosService.isAuthenticated();
    } catch (e) {
      return Result.error(
          'Failed to check Coinos authentication: ${e.toString()}');
    }
  }

  Future<Result<Map<String, dynamic>?>> getCoinosUser() async {
    try {
      final coinosService = AppDI.get<CoinosService>();
      final userResult = await coinosService.getStoredUser();
      if (userResult.isError) {
        return Result.error(userResult.error!);
      }
      return Result.success(userResult.data);
    } catch (e) {
      return Result.error('Failed to get Coinos user: ${e.toString()}');
    }
  }

  Future<Result<void>> clearCoinosData() async {
    try {
      final coinosService = AppDI.get<CoinosService>();
      return await coinosService.clearAuthData();
    } catch (e) {
      return Result.error('Failed to clear Coinos data: ${e.toString()}');
    }
  }
}
