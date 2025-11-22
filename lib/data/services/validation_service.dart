import 'package:ndk/ndk.dart';

import '../../core/base/result.dart';

class ValidationService {
  static final ValidationService _instance = ValidationService._internal();
  factory ValidationService() => _instance;
  ValidationService._internal();

  static ValidationService get instance => _instance;

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
      Nip19.decode(nsec);
      return const Result.success(null);
    } catch (e) {
      return const Result.error('Invalid NSEC format');
    }
  }

  Result<void> validateNpub(String npub) {
    if (npub.trim().isEmpty) {
      return const Result.error('NPUB cannot be empty');
    }

    if (npub.startsWith('npub1')) {
      if (npub.length < 63) {
        return const Result.error('NPUB is too short');
      }

      try {
        Nip19.decode(npub);
        return const Result.success(null);
      } catch (e) {
        return const Result.error('Invalid NPUB format');
      }
    }

    else if (npub.length == 64) {
      try {
        int.parse(npub, radix: 16);
        return const Result.success(null);
      } catch (e) {
        return const Result.error('Invalid hex public key format');
      }
    }

    else if (npub.length >= 8) {
      return const Result.success(null);
    }

    else {
      return const Result.error('NPUB must be in npub1 bech32 format or valid hex format');
    }
  }

  Result<void> validatePrivateKeyHex(String privateKey) {
    if (privateKey.trim().isEmpty) {
      return const Result.error('Private key cannot be empty');
    }

    if (privateKey.length != 64) {
      return const Result.error('Private key must be 64 characters long');
    }

    try {
      int.parse(privateKey, radix: 16);
      return const Result.success(null);
    } catch (e) {
      return const Result.error('Private key must be valid hexadecimal');
    }
  }

  Result<void> validatePublicKeyHex(String publicKey) {
    if (publicKey.trim().isEmpty) {
      return const Result.error('Public key cannot be empty');
    }

    if (publicKey.length != 64) {
      return const Result.error('Public key must be 64 characters long');
    }

    try {
      int.parse(publicKey, radix: 16);
      return const Result.success(null);
    } catch (e) {
      return const Result.error('Public key must be valid hexadecimal');
    }
  }

  Result<void> validateNoteContent(String content) {
    if (content.trim().isEmpty) {
      return const Result.error('Note content cannot be empty');
    }

    if (content.length > 2000) {
      return const Result.error('Note content is too long (max 2000 characters)');
    }

    return const Result.success(null);
  }

  Result<void> validateProfileName(String name) {
    if (name.trim().isEmpty) {
      return const Result.error('Name cannot be empty');
    }

    if (name.length > 50) {
      return const Result.error('Name is too long (max 50 characters)');
    }

    return const Result.success(null);
  }

  Result<void> validateProfileAbout(String about) {
    if (about.length > 500) {
      return const Result.error('About section is too long (max 500 characters)');
    }

    return const Result.success(null);
  }

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

    if (username.length > 64) {
      return const Result.error('NIP-05 username is too long (max 64 characters)');
    }

    if (!domain.contains('.')) {
      return const Result.error('NIP-05 domain must be valid domain name');
    }

    return const Result.success(null);
  }

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

  Result<void> validateZapAmount(int amount) {
    if (amount <= 0) {
      return const Result.error('Zap amount must be greater than 0');
    }

    if (amount > 100000000) {
      return const Result.error('Zap amount is too large (max 1 BTC)');
    }

    return const Result.success(null);
  }

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
