import 'package:nostr/nostr.dart';
import 'package:nostr_nip19/nostr_nip19.dart';

import '../../core/base/result.dart';

/// Service responsible for input validation
/// Provides validation for NSEC, NPUB, and other user inputs
class ValidationService {
  static final ValidationService _instance = ValidationService._internal();
  factory ValidationService() => _instance;
  ValidationService._internal();

  static ValidationService get instance => _instance;

  /// Validate NSEC (private key) format
  Result<void> validateNsec(String nsec) {
    if (nsec.trim().isEmpty) {
      return const Result.error('NSEC cannot be empty');
    }

    if (!nsec.startsWith('nsec1')) {
      return const Result.error('NSEC must start with "nsec1"');
    }

    if (nsec.length < 63) {
      return const Result.error('NSEC is too short');
    }

    try {
      // Try to decode to validate format
      Nip19.decodePrivkey(nsec);
      return const Result.success(null);
    } catch (e) {
      return const Result.error('Invalid NSEC format');
    }
  }

  /// Validate NPUB (public key) format
  /// Accepts both npub1 bech32 format and 64-character hex format
  Result<void> validateNpub(String npub) {
    if (npub.trim().isEmpty) {
      return const Result.error('NPUB cannot be empty');
    }

    // Handle npub1 bech32 format
    if (npub.startsWith('npub1')) {
      if (npub.length < 63) {
        return const Result.error('NPUB is too short');
      }

      try {
        // Try to decode to validate format
        decodeBasicBech32(npub, 'npub');
        return const Result.success(null);
      } catch (e) {
        return const Result.error('Invalid NPUB format');
      }
    }

    // Handle 64-character hex format (internal Nostr protocol format)
    else if (npub.length == 64) {
      try {
        // Validate hex format
        int.parse(npub, radix: 16);
        return const Result.success(null);
      } catch (e) {
        return const Result.error('Invalid hex public key format');
      }
    }

    // For compatibility, allow shorter formats that might be truncated IDs
    else if (npub.length >= 8) {
      // Accept as valid identifier (might be truncated for display)
      return const Result.success(null);
    }

    // Invalid format
    else {
      return const Result.error('NPUB must be in npub1 bech32 format or valid hex format');
    }
  }

  /// Validate private key in hex format
  Result<void> validatePrivateKeyHex(String privateKey) {
    if (privateKey.trim().isEmpty) {
      return const Result.error('Private key cannot be empty');
    }

    if (privateKey.length != 64) {
      return const Result.error('Private key must be 64 characters long');
    }

    try {
      // Validate hex format
      int.parse(privateKey, radix: 16);
      return const Result.success(null);
    } catch (e) {
      return const Result.error('Private key must be valid hexadecimal');
    }
  }

  /// Validate public key in hex format
  Result<void> validatePublicKeyHex(String publicKey) {
    if (publicKey.trim().isEmpty) {
      return const Result.error('Public key cannot be empty');
    }

    if (publicKey.length != 64) {
      return const Result.error('Public key must be 64 characters long');
    }

    try {
      // Validate hex format
      int.parse(publicKey, radix: 16);
      return const Result.success(null);
    } catch (e) {
      return const Result.error('Public key must be valid hexadecimal');
    }
  }

  /// Validate note content
  Result<void> validateNoteContent(String content) {
    if (content.trim().isEmpty) {
      return const Result.error('Note content cannot be empty');
    }

    if (content.length > 2000) {
      return const Result.error('Note content is too long (max 2000 characters)');
    }

    return const Result.success(null);
  }

  /// Validate profile name
  Result<void> validateProfileName(String name) {
    if (name.trim().isEmpty) {
      return const Result.error('Name cannot be empty');
    }

    if (name.length > 50) {
      return const Result.error('Name is too long (max 50 characters)');
    }

    return const Result.success(null);
  }

  /// Validate profile about/bio
  Result<void> validateProfileAbout(String about) {
    if (about.length > 500) {
      return const Result.error('About section is too long (max 500 characters)');
    }

    return const Result.success(null);
  }

  /// Validate URL format
  Result<void> validateUrl(String url) {
    if (url.trim().isEmpty) {
      return const Result.success(null); // Empty URL is valid
    }

    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme) {
        return const Result.error('URL must include protocol (http:// or https://)');
      }
      if (!['http', 'https'].contains(uri.scheme.toLowerCase())) {
        return const Result.error('URL must use HTTP or HTTPS protocol');
      }
      return const Result.success(null);
    } catch (e) {
      return const Result.error('Invalid URL format');
    }
  }

  /// Validate NIP-05 identifier format
  Result<void> validateNip05(String nip05) {
    if (nip05.trim().isEmpty) {
      return const Result.success(null); // Empty NIP-05 is valid
    }

    if (!nip05.contains('@')) {
      return const Result.error('NIP-05 must be in format: username@domain.com');
    }

    final parts = nip05.split('@');
    if (parts.length != 2 || parts.any((p) => p.isEmpty)) {
      return const Result.error('NIP-05 must be in format: username@domain.com');
    }

    final username = parts[0];
    final domain = parts[1];

    // Validate username part
    if (username.length > 64) {
      return const Result.error('NIP-05 username is too long (max 64 characters)');
    }

    // Basic domain validation
    if (!domain.contains('.')) {
      return const Result.error('NIP-05 domain must be valid domain name');
    }

    return const Result.success(null);
  }

  /// Validate Lightning Address (LUD-16)
  Result<void> validateLightningAddress(String lud16) {
    if (lud16.trim().isEmpty) {
      return const Result.success(null); // Empty LUD-16 is valid
    }

    if (!lud16.contains('@')) {
      return const Result.error('Lightning address must be in format: username@domain.com');
    }

    final parts = lud16.split('@');
    if (parts.length != 2 || parts.any((p) => p.isEmpty)) {
      return const Result.error('Lightning address must be in format: username@domain.com');
    }

    return const Result.success(null);
  }

  /// Validate relay URL
  Result<void> validateRelayUrl(String relayUrl) {
    if (relayUrl.trim().isEmpty) {
      return const Result.error('Relay URL cannot be empty');
    }

    try {
      final uri = Uri.parse(relayUrl);

      if (!['ws', 'wss'].contains(uri.scheme.toLowerCase())) {
        return const Result.error('Relay URL must use WebSocket protocol (ws:// or wss://)');
      }

      if (uri.host.isEmpty) {
        return const Result.error('Invalid relay URL format');
      }

      return const Result.success(null);
    } catch (e) {
      return const Result.error('Invalid relay URL format');
    }
  }

  /// Validate amount for zap (in satoshis)
  Result<void> validateZapAmount(int amount) {
    if (amount <= 0) {
      return const Result.error('Zap amount must be greater than 0');
    }

    if (amount > 100000000) {
      // 1 BTC in sats
      return const Result.error('Zap amount is too large (max 1 BTC)');
    }

    return const Result.success(null);
  }

  /// Validate general text input with length limits
  Result<void> validateText(
    String text, {
    bool required = false,
    int minLength = 0,
    int maxLength = 1000,
    String fieldName = 'Text',
  }) {
    if (required && text.trim().isEmpty) {
      return Result.error('$fieldName cannot be empty');
    }

    if (text.length < minLength) {
      return Result.error('$fieldName must be at least $minLength characters');
    }

    if (text.length > maxLength) {
      return Result.error('$fieldName must be no more than $maxLength characters');
    }

    return const Result.success(null);
  }
}

/// Helper class for validation results with user-friendly error messages
class ValidationResult {
  final bool isValid;
  final String? errorMessage;

  const ValidationResult._(this.isValid, this.errorMessage);

  factory ValidationResult.valid() => const ValidationResult._(true, null);

  factory ValidationResult.invalid(String message) => ValidationResult._(false, message);

  factory ValidationResult.fromResult(Result<void> result) {
    return result.fold(
      (_) => ValidationResult.valid(),
      (error) => ValidationResult.invalid(error),
    );
  }
}
