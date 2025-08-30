import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:nostr_nip19/nostr_nip19.dart';

class Nip05VerificationService {
  static final Nip05VerificationService _instance = Nip05VerificationService._internal();
  factory Nip05VerificationService() => _instance;
  Nip05VerificationService._internal();

  static Nip05VerificationService get instance => _instance;

  final Map<String, bool> _verificationCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};

  static const Duration _cacheTTL = Duration(hours: 1);

  Future<bool> verifyNip05(String nip05, String publicKeyHex) async {
    try {
      if (nip05.isEmpty || publicKeyHex.isEmpty) {
        return false;
      }

      final cacheKey = '$nip05:$publicKeyHex';
      if (_verificationCache.containsKey(cacheKey)) {
        final cacheTime = _cacheTimestamps[cacheKey];
        if (cacheTime != null && DateTime.now().difference(cacheTime) < _cacheTTL) {
          return _verificationCache[cacheKey]!;
        } else {
          _verificationCache.remove(cacheKey);
          _cacheTimestamps.remove(cacheKey);
        }
      }

      final parts = nip05.split('@');
      if (parts.length != 2) {
        _cacheResult(cacheKey, false);
        return false;
      }

      final localPart = parts[0];
      final domain = parts[1];

      if (!_isValidLocalPart(localPart)) {
        _cacheResult(cacheKey, false);
        return false;
      }

      final url = Uri.parse('https://$domain/.well-known/nostr.json?name=$localPart');

      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Qiqstr-NIP05-Verifier/1.0',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('NIP-05 verification request timed out');
        },
      );

      if (response.isRedirect) {
        print('[NIP-05] Verification failed: HTTP redirects are not allowed');
        _cacheResult(cacheKey, false);
        return false;
      }

      if (response.statusCode != 200) {
        print('[NIP-05] Verification failed: HTTP ${response.statusCode}');
        _cacheResult(cacheKey, false);
        return false;
      }

      Map<String, dynamic> jsonData;
      try {
        jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        print('[NIP-05] Verification failed: Invalid JSON response');
        _cacheResult(cacheKey, false);
        return false;
      }

      final names = jsonData['names'] as Map<String, dynamic>?;
      if (names == null) {
        print('[NIP-05] Verification failed: Missing "names" field');
        _cacheResult(cacheKey, false);
        return false;
      }

      final expectedPubkey = names[localPart] as String?;
      if (expectedPubkey == null) {
        print('[NIP-05] Verification failed: Local part "$localPart" not found in names');
        _cacheResult(cacheKey, false);
        return false;
      }

      final isVerified = expectedPubkey.toLowerCase() == publicKeyHex.toLowerCase();

      if (isVerified) {
        print('[NIP-05] Verification successful for $nip05');
      } else {
        print('[NIP-05] Verification failed: Public key mismatch');
        print('[NIP-05] Expected: $expectedPubkey');
        print('[NIP-05] Provided: $publicKeyHex');
      }

      _cacheResult(cacheKey, isVerified);
      return isVerified;
    } catch (e) {
      print('[NIP-05] Verification error for $nip05: $e');
      _cacheResult('$nip05:$publicKeyHex', false);
      return false;
    }
  }

  bool _isValidLocalPart(String localPart) {
    if (localPart.isEmpty) return false;

    final validPattern = RegExp(r'^[a-zA-Z0-9._-]+$');
    return validPattern.hasMatch(localPart);
  }

  void _cacheResult(String cacheKey, bool result) {
    _verificationCache[cacheKey] = result;
    _cacheTimestamps[cacheKey] = DateTime.now();
  }

  String? _npubToHex(String npub) {
    try {
      if (npub.startsWith('npub1')) {
        return decodeBasicBech32(npub, 'npub');
      }

      if (_isValidHex(npub)) {
        return npub;
      }
      return null;
    } catch (e) {
      print('[NIP-05] Error converting npub to hex: $e');
      return null;
    }
  }

  bool _isValidHex(String value) {
    if (value.isEmpty || value.length != 64) return false;
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
  }

  Future<bool> verifyNip05WithNpub(String nip05, String npub) async {
    final hexKey = _npubToHex(npub);
    if (hexKey == null) {
      print('[NIP-05] Invalid npub format: $npub');
      return false;
    }
    return await verifyNip05(nip05, hexKey);
  }

  void clearCache() {
    _verificationCache.clear();
    _cacheTimestamps.clear();
  }

  Map<String, dynamic> getCacheStats() {
    return {
      'cached_verifications': _verificationCache.length,
      'oldest_cache_entry':
          _cacheTimestamps.values.isEmpty ? null : _cacheTimestamps.values.reduce((a, b) => a.isBefore(b) ? a : b).toIso8601String(),
      'newest_cache_entry':
          _cacheTimestamps.values.isEmpty ? null : _cacheTimestamps.values.reduce((a, b) => a.isAfter(b) ? a : b).toIso8601String(),
    };
  }
}
