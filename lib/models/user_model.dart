import 'package:flutter/foundation.dart';
import 'package:nostr_nip19/nostr_nip19.dart';

class UserModel {
  final String pubkeyHex; // Primary identifier - always hex format
  final String name;
  final String about;
  final String nip05;
  final String banner;
  final String profileImage;
  final String lud16;
  final DateTime updatedAt;
  final String website;
  final bool nip05Verified;

  UserModel({
    required this.pubkeyHex,
    required this.name,
    required this.about,
    required this.nip05,
    required this.banner,
    required this.profileImage,
    required this.lud16,
    required this.updatedAt,
    required this.website,
    this.nip05Verified = false,
  });

  /// Get npub (bech32) format for display purposes
  String get npub {
    try {
      if (pubkeyHex.startsWith('npub1')) {
        return pubkeyHex; // Already in npub format
      }
      return encodeBasicBech32(pubkeyHex, 'npub');
    } catch (e) {
      return pubkeyHex; // Fallback to hex if conversion fails
    }
  }

  /// Create from cached profile data with hex pubkey
  factory UserModel.fromCachedProfile(String pubkeyHex, Map<String, String> data) {
    return UserModel(
      pubkeyHex: _ensureHexFormat(pubkeyHex),
      name: data['name'] ?? 'Anonymous',
      about: data['about'] ?? '',
      nip05: data['nip05'] ?? '',
      banner: data['banner'] ?? '',
      profileImage: data['profileImage'] ?? '',
      lud16: data['lud16'] ?? '',
      website: data['website'] ?? '',
      updatedAt: DateTime.now(),
      nip05Verified: data.containsKey('nip05Verified') ? data['nip05Verified'] == 'true' : false,
    );
  }

  /// Create from JSON (for backward compatibility)
  factory UserModel.fromJson(Map<String, dynamic> json) {
    // Handle both old 'npub' and new 'pubkeyHex' fields
    final identifier = json['pubkeyHex'] as String? ?? json['npub'] as String;

    return UserModel(
      pubkeyHex: _ensureHexFormat(identifier),
      name: json['name'] as String,
      about: json['about'] as String,
      nip05: json['nip05'] as String,
      banner: json['banner'] as String,
      profileImage: json['profileImage'] as String,
      lud16: json['lud16'] as String? ?? '',
      website: json['website'] as String? ?? '',
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      nip05Verified: json.containsKey('nip05Verified') ? (json['nip05Verified'] as bool? ?? false) : false,
    );
  }

  /// Convert to JSON format
  Map<String, dynamic> toJson() => {
        'pubkeyHex': pubkeyHex,
        'npub': npub, // Include npub for backward compatibility
        'name': name,
        'about': about,
        'nip05': nip05,
        'banner': banner,
        'profileImage': profileImage,
        'lud16': lud16,
        'website': website,
        'updatedAt': updatedAt.toIso8601String(),
        'nip05Verified': nip05Verified,
      };

  /// Convert identifier to hex format
  static String _ensureHexFormat(String identifier) {
    try {
      if (identifier.startsWith('npub1')) {
        return decodeBasicBech32(identifier, 'npub');
      } else if (identifier.length == 64 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(identifier)) {
        return identifier; // Already hex
      }
    } catch (e) {
      // If conversion fails, return the original
      if (kDebugMode) {
        print('[UserModel] Warning: Could not convert identifier to hex: $e');
      }
    }
    return identifier;
  }

  /// Copy with method for updates
  UserModel copyWith({
    String? pubkeyHex,
    String? name,
    String? about,
    String? nip05,
    String? banner,
    String? profileImage,
    String? lud16,
    DateTime? updatedAt,
    String? website,
    bool? nip05Verified,
  }) {
    return UserModel(
      pubkeyHex: pubkeyHex ?? this.pubkeyHex,
      name: name ?? this.name,
      about: about ?? this.about,
      nip05: nip05 ?? this.nip05,
      banner: banner ?? this.banner,
      profileImage: profileImage ?? this.profileImage,
      lud16: lud16 ?? this.lud16,
      updatedAt: updatedAt ?? this.updatedAt,
      website: website ?? this.website,
      nip05Verified: nip05Verified ?? this.nip05Verified,
    );
  }
}
