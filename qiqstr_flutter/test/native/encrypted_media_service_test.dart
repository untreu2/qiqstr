import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/data/services/encrypted_media_service.dart';
import '../support/native_rust.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = EncryptedMediaService.instance;
  late Directory temporary;
  const key = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';
  const nonce = 'AAECAwQFBgcICQoLDA0ODw==';
  const encrypted = 'Fx7JAFiQLwj8i69INsxB1jrHc8Dg3ulUDIquG4MYqQbWtA==';
  const hash =
      'c079a3589412389aa566ec4193a874453106a1896f569a380ce8801e06685e68';

  setUpAll(initializeNativeRust);
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('qiqstr_media_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temporary.path,
        );
  });
  tearDown(() async {
    await service.clearDecryptedMediaCache();
    await temporary.delete(recursive: true);
  });

  Future<String> decryptFixture() async {
    final result = await service.decryptMediaFile(
      encryptedBytes: base64Decode(encrypted),
      decryptionKey: key,
      decryptionNonce: nonce,
      originalHash: hash,
      fileExtension: 'bin',
    );
    expect(result.isSuccess, isTrue, reason: result.error);
    return result.data!;
  }

  test('decrypts interoperable AES-GCM with a base64 16-byte nonce', () async {
    final path = await decryptFixture();
    expect(await File(path).readAsString(), 'private attachment');
    expect(path, contains(hash));
  });

  test(
    'cached plaintext cannot bypass key and ciphertext authentication',
    () async {
      await decryptFixture();
      final result = await service.decryptMediaFile(
        encryptedBytes: Uint8List(20),
        decryptionKey: key,
        decryptionNonce: nonce,
        originalHash: hash,
        fileExtension: 'bin',
      );
      expect(result.isError, isTrue);
    },
  );

  test('rejects tampered cached files and unsafe file extensions', () async {
    final path = await decryptFixture();
    await File(path).writeAsString('tampered');
    expect(await service.getDecryptedCachePath(hash, 'bin'), isNull);
    expect(await File(path).exists(), isFalse);
    expect(await service.getDecryptedCachePath(hash, '../../private'), isNull);
    expect(service.getFileExtensionFromMimeType('image/../../private'), 'bin');
    expect(
      service.getFileExtensionFromMimeType('IMAGE/JPEG; charset=utf-8'),
      'jpg',
    );
    expect(service.getFileExtensionFromMimeType('audio/mp4'), 'm4a');
  });

  test('clearing the cache invalidates a pending decrypt', () async {
    final directoryRequested = Completer<void>();
    final directory = Completer<String>();
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) {
            if (++calls == 1) {
              directoryRequested.complete();
              return directory.future;
            }
            return Future.value(temporary.path);
          },
        );
    final pending = service.decryptMediaFile(
      encryptedBytes: base64Decode(encrypted),
      decryptionKey: key,
      decryptionNonce: nonce,
      originalHash: hash,
      fileExtension: 'bin',
    );
    await directoryRequested.future;
    await service.clearDecryptedMediaCache();
    directory.complete(temporary.path);
    expect((await pending).isError, isTrue);
    expect(await service.getDecryptedCachePath(hash, 'bin'), isNull);
  });

  test('encrypts local attachments and restores the exact bytes', () async {
    final source = File('${temporary.path}/picture.png');
    final bytes = Uint8List.fromList(List.generate(256, (index) => index));
    await source.writeAsBytes(bytes);
    final encryptedResult = await service.encryptMediaFile(source.path);
    expect(encryptedResult.isSuccess, isTrue, reason: encryptedResult.error);
    final metadata = encryptedResult.data!;
    final result = await service.decryptMediaFile(
      encryptedBytes: await File(metadata.encryptedFilePath).readAsBytes(),
      decryptionKey: metadata.encryptionKey,
      decryptionNonce: metadata.encryptionNonce,
      originalHash: metadata.originalHash,
      fileExtension: 'png',
    );
    expect(result.isSuccess, isTrue, reason: result.error);
    expect(await File(result.data!).readAsBytes(), bytes);
    expect(metadata.mimeType, 'image/png');
    await service.cleanupEncryptedFile(metadata.encryptedFilePath);
    expect(await File(metadata.encryptedFilePath).exists(), isFalse);
  });
}
