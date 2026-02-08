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
  static final EncryptedMediaService _instance = EncryptedMediaService._internal();
  factory EncryptedMediaService() => _instance;
  EncryptedMediaService._internal();

  
  static String _normalizeToHex(String input, int expectedByteLength) {
    if (input.length == expectedByteLength * 2) {
      try {
        hex.decode(input);
        return input;
      } catch (_) {}
    }
    
    try {
      final bytes = base64Decode(input);
      if (bytes.length == expectedByteLength) {
        return hex.encode(bytes);
      }
    } catch (_) {}
    
    return input;
  }

  static EncryptedMediaService get instance => _instance;

  
  Future<Result<EncryptedFileMetadata>> encryptMediaFile(String filePath) async {
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
      final encryptedFileName = 'encrypted_${DateTime.now().millisecondsSinceEpoch}_${encryptedHash.substring(0, 8)}';
      final encryptedFile = File('${tempDir.path}/$encryptedFileName');
      await encryptedFile.writeAsBytes(encryptedBytes);

      return Result.success(EncryptedFileMetadata(
        encryptedFilePath: encryptedFile.path,
        encryptionKey: encryptionKey,
        encryptionNonce: encryptionNonce,
        originalHash: originalHash,
        encryptedHash: encryptedHash,
        originalSize: originalSize,
        encryptedSize: encryptedSize,
        mimeType: mimeType,
      ));
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
    try {
      // Normalize key to hex format (handles both hex and base64)
      final normalizedKey = _normalizeToHex(decryptionKey, 32); // 32 bytes for AES-256
      
      // Amethyst uses 16-byte nonces, we use 12-byte nonces
      // Try both (Rust will handle 16-byte by truncating to 12)
      String normalizedNonce;
      if (decryptionNonce.length == 32) {
        // Already 16 bytes in hex format (Amethyst style)
        normalizedNonce = decryptionNonce;
      } else if (decryptionNonce.length == 24) {
        // Already 12 bytes in hex format (our style)
        normalizedNonce = decryptionNonce;
      } else {
        // Try to normalize (could be base64)
        normalizedNonce = _normalizeToHex(decryptionNonce, 12);
        if (normalizedNonce.length != 24 && normalizedNonce.length != 32) {
          normalizedNonce = _normalizeToHex(decryptionNonce, 16);
        }
      }
      
      if (normalizedKey.length != 64) {
        return Result.error(
          'Invalid key after normalization: ${normalizedKey.length} chars (expected 64 hex). '
          'Original: ${decryptionKey.length} chars'
        );
      }
      
      if (normalizedNonce.length != 24 && normalizedNonce.length != 32) {
        return Result.error(
          'Invalid nonce after normalization: ${normalizedNonce.length} chars (expected 24 or 32 hex). '
          'Original: ${decryptionNonce.length} chars, value: $decryptionNonce'
        );
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
          'File may be corrupted or tampered with.'
        );
      }

      final cacheDir = await getTemporaryDirectory();
      final decryptedCacheDir = Directory('${cacheDir.path}/decrypted_media');
      if (!await decryptedCacheDir.exists()) {
        await decryptedCacheDir.create(recursive: true);
      }

      final decryptedFileName = 'decrypted_${originalHash.substring(0, 16)}.$fileExtension';
      final decryptedFile = File('${decryptedCacheDir.path}/$decryptedFileName');

      if (await decryptedFile.exists()) {
        return Result.success(decryptedFile.path);
      }

      await decryptedFile.writeAsBytes(decryptedBytes);
      return Result.success(decryptedFile.path);
    } catch (e, stackTrace) {
      return Result.error('Failed to decrypt file: $e\nStack: $stackTrace');
    }
  }

  
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
    try {
      final cacheDir = await getTemporaryDirectory();
      final decryptedCacheDir = Directory('${cacheDir.path}/decrypted_media');
      
      if (await decryptedCacheDir.exists()) {
        await decryptedCacheDir.delete(recursive: true);
      }
      
      return const Result.success(null);
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
    if (mimeType.startsWith('image/')) {
      final subtype = mimeType.split('/').last;
      if (subtype == 'jpeg') return 'jpg';
      return subtype;
    }
    
    if (mimeType.startsWith('video/')) {
      final subtype = mimeType.split('/').last;
      if (subtype == 'quicktime') return 'mov';
      if (subtype == 'x-msvideo') return 'avi';
      return subtype;
    }
    
    if (mimeType.startsWith('audio/')) {
      final subtype = mimeType.split('/').last;
      if (subtype == 'mpeg') return 'mp3';
      return subtype;
    }
    
    return 'bin';
  }
}
