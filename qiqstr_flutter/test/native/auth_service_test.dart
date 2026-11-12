import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/data/services/auth_service.dart';
import '../../lib/data/services/rust_nostr_bridge.dart';
import '../support/native_rust.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = AuthService.instance;
  const mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  const privateKey =
      '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798';

  setUpAll(initializeNativeRust);
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await auth.refreshCache();
  });

  test(
    'imports a full-width private key through validation and native crypto',
    () async {
      final result = await auth.loginWithPrivateKeyValidated(privateKey);
      expect(result.isSuccess, isTrue, reason: result.error);
      expect(
        auth.currentUserNpub,
        Nip19.encodePubKey(Bip340.getPublicKey(privateKey)),
      );
    },
  );

  test(
    'switching from a mnemonic to nsec clears the active recovery phrase',
    () async {
      final first = await auth.loginWithMnemonic(mnemonic);
      expect(first.isSuccess, isTrue);
      final second = await auth.loginWithNsec(
        Nip19.encodePrivateKey(privateKey),
      );
      expect(second.isSuccess, isTrue);
      expect((await auth.getCurrentUserMnemonic()).data, isNull);
      expect((await auth.switchAccount(first.data!)).isSuccess, isTrue);
      expect((await auth.getCurrentUserMnemonic()).data, mnemonic);
    },
  );

  test(
    'reimporting the same identity retains its known recovery phrase',
    () async {
      await auth.loginWithMnemonic(mnemonic);
      final nsec = (await auth.getCurrentUserNsec()).data!;
      expect((await auth.loginWithNsec(nsec)).isSuccess, isTrue);
      expect((await auth.getCurrentUserMnemonic()).data, mnemonic);
      expect((await auth.getStoredAccounts()).single.mnemonic, mnemonic);
    },
  );

  test('normalizes pasted mnemonic whitespace', () async {
    final result = await auth.loginWithMnemonic(
      '  ${mnemonic.replaceAll(' ', '  \n')}  ',
    );
    expect(result.isSuccess, isTrue, reason: result.error);
    expect((await auth.getCurrentUserMnemonic()).data, mnemonic);
  });

  test('decodes note IDs and rejects the wrong bech32 type', () {
    final note = auth.encodeNoteId(privateKey);
    expect(auth.decodeNoteId(note), privateKey);
    expect(
      auth.decodeBasicBech32(Nip19.encodePrivateKey(privateKey), 'npub'),
      isNull,
    );
  });

  test('clearing secure data also clears cached authentication', () async {
    await auth.loginWithMnemonic(mnemonic);
    expect((await auth.clearAllData()).isSuccess, isTrue);
    expect(auth.currentUserNpub, isNull);
    expect(auth.currentUserPubkeyHex, isNull);
  });

  test('refreshing missing credentials clears cached authentication', () async {
    await auth.loginWithMnemonic(mnemonic);
    FlutterSecureStorage.setMockInitialValues({});
    await auth.refreshCache();
    expect(auth.currentUserNpub, isNull);
    expect(auth.currentUserPubkeyHex, isNull);
  });

  test('mismatched stored credentials cannot authenticate', () async {
    final first = await auth.loginWithMnemonic(mnemonic);
    FlutterSecureStorage.setMockInitialValues({
      'npub': first.data!,
      'privateKey': privateKey,
    });
    expect((await auth.isAuthenticated()).data, isFalse);
    await auth.refreshCache();
    expect(auth.currentUserNpub, isNull);
  });

  test('pasted nsec whitespace is accepted', () async {
    final result = await auth.loginWithNsecValidated(
      ' \n${Nip19.encodePrivateKey(privateKey)}\n ',
    );
    expect(result.isSuccess, isTrue, reason: result.error);
  });

  test('concurrent identity imports retain every recovery account', () async {
    final keys = List.generate(
      8,
      (index) => (index + 1).toRadixString(16).padLeft(64, '0'),
    );
    final results = await Future.wait(keys.map(auth.loginWithPrivateKey));
    expect(results.every((result) => result.isSuccess), isTrue);
    expect(
      (await auth.getStoredAccounts())
          .map((account) => account.privateKeyHex)
          .toSet(),
      keys.toSet(),
    );
    expect((await auth.isAuthenticated()).data, isTrue);
    final storedKey = (await auth.getCurrentUserPrivateKey()).data!;
    expect(
      auth.currentUserNpub,
      Nip19.encodePubKey(Bip340.getPublicKey(storedKey)),
    );
  });

  test(
    'corrupt recovery account storage is not overwritten during login',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'stored_accounts': 'corrupt backup',
      });
      final result = await auth.loginWithPrivateKey(privateKey);
      expect(result.isError, isTrue);
      expect(
        await const FlutterSecureStorage().read(key: 'stored_accounts'),
        'corrupt backup',
      );
      expect(auth.currentUserNpub, isNull);
    },
  );

  test(
    'switching rejects stored key mismatches and retains the active identity',
    () async {
      final active = await auth.loginWithMnemonic(mnemonic);
      final npub = Nip19.encodePubKey(Bip340.getPublicKey(privateKey));
      await const FlutterSecureStorage().write(
        key: 'stored_accounts',
        value: jsonEncode([
          {'npub': npub, 'privateKeyHex': '01'.padLeft(64, '0')},
        ]),
      );
      expect((await auth.switchAccount(npub)).isError, isTrue);
      expect(auth.currentUserNpub, active.data);
      expect((await auth.isAuthenticated()).data, isTrue);
    },
  );
}
