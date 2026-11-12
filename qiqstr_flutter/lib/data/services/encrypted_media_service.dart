import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../../core/base/result.dart';
import '../../src/rust/api/crypto.dart' as rust_crypto;
import 'package:convert/convert.dart';

class EncryptedFileMetadata {
  final String encryptedFilePath;
  final String encryptionKey;
  final String encryptionNonce;
  final String originalHash;
  final String encryptedHash;
  final int originalSize;
  final int encryptedSize;
  final String mimeType;

  EncryptedFileMetadata({
    required this.encryptedFilePath,
    required this.encryptionKey,
    required this.encryptionNonce,
    required this.originalHash,
    required this.encryptedHash,
    required this.originalSize,
    required this.encryptedSize,
    required this.mimeType,
  });
}

class EncryptedMediaService {
  static final EncryptedMediaService _instance =
      EncryptedMediaService._internal();
  factory EncryptedMediaService() => _instance;
  EncryptedMediaService._internal();

  final Map<String, String> _pathCache = {};
  int _cacheGeneration = 0;

  static String? _normalizeToHex(String input, List<int> byteLengths) {
    input = input.trim();
    if (byteLengths.contains(input.length ~/ 2) && input.length.isEven) {
      try {
        final bytes = hex.decode(input);
        if (byteLengths.contains(bytes.length)) return hex.encode(bytes);
      } catch (_) {}
    }

    try {
      final bytes = base64Decode(input);
      if (byteLengths.contains(bytes.length)) {
        return hex.encode(bytes);
      }
    } catch (_) {}

    return null;
  }

  static EncryptedMediaService get instance => _instance;

  Future<Result<EncryptedFileMetadata>> encryptMediaFile(
    String filePath,
  ) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return Result.error('File not found: $filePath');
      }

      final originalBytes = await file.readAsBytes();
      final originalSize = originalBytes.length;
      final mimeType = _detectMimeType(filePath);
      final originalHash = rust_crypto.sha256Hash(data: originalBytes);

      final encryptionKey = rust_crypto.generateAesKey();
      final encryptionNonce = rust_crypto.generateAesNonce();

      final encryptedBase64 = rust_crypto.aesGcmEncrypt(
        data: originalBytes,
        keyHex: encryptionKey,
        nonceHex: encryptionNonce,
      );

      final encryptedBytes = base64Decode(encryptedBase64);
      final encryptedSize = encryptedBytes.length;

      final encryptedHash = rust_crypto.sha256Hash(data: encryptedBytes);

      final tempDir = await getTemporaryDirectory();
      final encryptedFileName =
          'encrypted_${DateTime.now().millisecondsSinceEpoch}_${encryptedHash.substring(0, 8)}';
      final encryptedFile = File('${tempDir.path}/$encryptedFileName');
      await encryptedFile.writeAsBytes(encryptedBytes);

      return Result.success(
        EncryptedFileMetadata(
          encryptedFilePath: encryptedFile.path,
          encryptionKey: encryptionKey,
          encryptionNonce: encryptionNonce,
          originalHash: originalHash,
          encryptedHash: encryptedHash,
          originalSize: originalSize,
          encryptedSize: encryptedSize,
          mimeType: mimeType,
        ),
      );
    } catch (e) {
      return Result.error('Failed to encrypt file: $e');
    }
  }

  Future<Result<String>> decryptMediaFile({
    required Uint8List encryptedBytes,
    required String decryptionKey,
    required String decryptionNonce,
    required String originalHash,
    required String fileExtension,
  }) async {
    final generation = _cacheGeneration;
    try {
      if (!_isValidCacheName(originalHash, fileExtension)) {
        return Result.error('Invalid media hash or file extension');
      }
      originalHash = originalHash.toLowerCase();
      fileExtension = fileExtension.toLowerCase();
      final cacheDir = await getTemporaryDirectory();
      final decryptedCacheDir = Directory('${cacheDir.path}/decrypted_media');
      final decryptedFileName = 'decrypted_$originalHash.$fileExtension';
      final decryptedFile = File(
        '${decryptedCacheDir.path}/$decryptedFileName',
      );

      final normalizedKey = _normalizeToHex(decryptionKey, [32]);
      final normalizedNonce = _normalizeToHex(decryptionNonce, [12, 16]);
      if (normalizedKey == null) {
        return Result.error('Invalid encryption key');
      }
      if (normalizedNonce == null) {
        return Result.error('Invalid encryption nonce');
      }

      final encryptedBase64 = base64Encode(encryptedBytes);

      final decryptedBytes = rust_crypto.aesGcmDecrypt(
        encryptedBase64: encryptedBase64,
        keyHex: normalizedKey,
        nonceHex: normalizedNonce,
      );

      final verifyHash = rust_crypto.sha256Hash(data: decryptedBytes);
      if (verifyHash.toLowerCase() != originalHash.toLowerCase()) {
        return Result.error(
          'Hash mismatch: expected $originalHash, got $verifyHash. '
          'File may be corrupted or tampered with.',
        );
      }

      if (!await decryptedCacheDir.exists()) {
        await decryptedCacheDir.create(recursive: true);
      }
      if (generation != _cacheGeneration) {
        return Result.error('Media cache was cleared');
      }
      await decryptedFile.writeAsBytes(decryptedBytes);
      if (generation != _cacheGeneration) {
        if (await decryptedFile.exists()) await decryptedFile.delete();
        return Result.error('Media cache was cleared');
      }
      _pathCache['$originalHash.$fileExtension'] = decryptedFile.path;
      return Result.success(decryptedFile.path);
    } catch (e) {
      return Result.error('Failed to decrypt file: $e');
    }
  }

  Future<String?> getDecryptedCachePath(
    String originalHash,
    String fileExtension,
  ) async {
    final generation = _cacheGeneration;
    try {
      if (!_isValidCacheName(originalHash, fileExtension)) return null;
      originalHash = originalHash.toLowerCase();
      fileExtension = fileExtension.toLowerCase();
      final cacheKey = '$originalHash.$fileExtension';
      final cacheDir = await getTemporaryDirectory();
      final decryptedCacheDir = Directory('${cacheDir.path}/decrypted_media');
      final decryptedFile = File(
        _pathCache[cacheKey] ?? '${decryptedCacheDir.path}/decrypted_$cacheKey',
      );
      if (await decryptedFile.exists()) {
        final hash = rust_crypto.sha256Hash(
          data: await decryptedFile.readAsBytes(),
        );
        if (generation != _cacheGeneration) return null;
        if (hash != originalHash) {
          _pathCache.remove(cacheKey);
          await decryptedFile.delete();
          return null;
        }
        _pathCache[cacheKey] = decryptedFile.path;
        return decryptedFile.path;
      }
      _pathCache.remove(cacheKey);
      return null;
    } catch (_) {
      return null;
    }
  }

  bool _isValidCacheName(String hash, String extension) =>
      RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) &&
      RegExp(r'^[a-zA-Z0-9]{1,10}$').hasMatch(extension);

  Future<void> cleanupEncryptedFile(String encryptedFilePath) async {
    try {
      final file = File(encryptedFilePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Silently fail cleanup
    }
  }

  Future<Result<void>> clearDecryptedMediaCache() async {
    _cacheGeneration++;
    try {
      _pathCache.clear();

      final cacheDir = await getTemporaryDirectory();
      final decryptedCacheDir = Directory('${cacheDir.path}/decrypted_media');

      if (await decryptedCacheDir.exists()) {
        await decryptedCacheDir.delete(recursive: true);
      }

      return Result.success(null);
    } catch (e) {
      return Result.error('Failed to clear cache: $e');
    }
  }

  String _detectMimeType(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();

    // Image formats
    if (['jpg', 'jpeg'].contains(extension)) return 'image/jpeg';
    if (extension == 'png') return 'image/png';
    if (extension == 'gif') return 'image/gif';
    if (extension == 'webp') return 'image/webp';
    if (extension == 'heic') return 'image/heic';

    // Video formats
    if (extension == 'mp4') return 'video/mp4';
    if (extension == 'mov') return 'video/quicktime';
    if (extension == 'avi') return 'video/x-msvideo';
    if (extension == 'webm') return 'video/webm';

    // Audio formats
    if (extension == 'mp3') return 'audio/mpeg';
    if (extension == 'wav') return 'audio/wav';
    if (extension == 'ogg') return 'audio/ogg';
    if (extension == 'm4a') return 'audio/mp4';

    // Default
    return 'application/octet-stream';
  }

  String getFileExtensionFromMimeType(String mimeType) {
    final normalized = mimeType.split(';').first.trim().toLowerCase();
    return const {
          'image/jpeg': 'jpg',
          'image/png': 'png',
          'image/gif': 'gif',
          'image/webp': 'webp',
          'image/heic': 'heic',
          'video/mp4': 'mp4',
          'video/quicktime': 'mov',
          'video/x-msvideo': 'avi',
          'video/webm': 'webm',
          'audio/mpeg': 'mp3',
          'audio/wav': 'wav',
          'audio/ogg': 'ogg',
          'audio/mp4': 'm4a',
        }[normalized] ??
        'bin';
  }
}
