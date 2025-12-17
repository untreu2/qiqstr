import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:nostr_nip19/nostr_nip19.dart';

part 'user_model.g.dart';

@collection
class UserModel {
  Id id = Isar.autoIncrement;

  @Index(unique: true, type: IndexType.hash)
  late String pubkeyHex;

  late String name;
  late String about;
  late String nip05;
  late String banner;
  late String profileImage;
  late String lud16;
  late DateTime updatedAt;
  late String website;
  late bool nip05Verified;

  int? followerCount;

  late DateTime cachedAt;

  String get npub {
    try {
      if (pubkeyHex.startsWith('npub1')) {
        return pubkeyHex;
      }
      return encodeBasicBech32(pubkeyHex, 'npub');
    } catch (e) {
      return pubkeyHex;
    }
  }

  static UserModel fromCachedProfile(String pubkeyHex, Map<String, String> data) {
    return UserModel()
      ..pubkeyHex = _ensureHexFormat(pubkeyHex)
      ..name = data['name'] ?? 'Anonymous'
      ..about = data['about'] ?? ''
      ..nip05 = data['nip05'] ?? ''
      ..banner = data['banner'] ?? ''
      ..profileImage = data['profileImage'] ?? ''
      ..lud16 = data['lud16'] ?? ''
      ..website = data['website'] ?? ''
      ..updatedAt = DateTime.now()
      ..nip05Verified = data.containsKey('nip05Verified') ? data['nip05Verified'] == 'true' : false
      ..followerCount = data['followerCount'] != null ? int.tryParse(data['followerCount']!) : null
      ..cachedAt = DateTime.now();
  }

  static UserModel fromUserModel(String pubkeyHex, Map<String, String> profileData) {
    return UserModel()
      ..pubkeyHex = pubkeyHex
      ..name = profileData['name'] ?? 'Anonymous'
      ..about = profileData['about'] ?? ''
      ..nip05 = profileData['nip05'] ?? ''
      ..banner = profileData['banner'] ?? ''
      ..profileImage = profileData['profileImage'] ?? ''
      ..lud16 = profileData['lud16'] ?? ''
      ..website = profileData['website'] ?? ''
      ..updatedAt = DateTime.now()
      ..nip05Verified = profileData['nip05Verified'] == 'true'
      ..followerCount = profileData['followerCount'] != null ? int.tryParse(profileData['followerCount']!) : null
      ..cachedAt = DateTime.now();
  }

  static UserModel fromJson(Map<String, dynamic> json) {
    final identifier = json['pubkeyHex'] as String? ?? json['npub'] as String;

    return UserModel()
      ..pubkeyHex = _ensureHexFormat(identifier)
      ..name = json['name'] as String
      ..about = json['about'] as String
      ..nip05 = json['nip05'] as String
      ..banner = json['banner'] as String
      ..profileImage = json['profileImage'] as String
      ..lud16 = json['lud16'] as String? ?? ''
      ..website = json['website'] as String? ?? ''
      ..updatedAt = DateTime.parse(json['updatedAt'] as String)
      ..nip05Verified = json.containsKey('nip05Verified') ? (json['nip05Verified'] as bool? ?? false) : false
      ..cachedAt = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
        'pubkeyHex': pubkeyHex,
        'npub': npub,
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

  Map<String, String> toProfileData() {
    return {
      'name': name,
      'about': about,
      'nip05': nip05,
      'banner': banner,
      'profileImage': profileImage,
      'lud16': lud16,
      'website': website,
      'nip05Verified': nip05Verified.toString(),
      if (followerCount != null) 'followerCount': followerCount.toString(),
    };
  }

  static String _ensureHexFormat(String identifier) {
    try {
      if (identifier.startsWith('npub1')) {
        return decodeBasicBech32(identifier, 'npub');
      } else if (identifier.length == 64 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(identifier)) {
        return identifier;
      }
    } catch (e) {
      if (kDebugMode) {
        print('[UserModel] Warning: Could not convert identifier to hex: $e');
      }
    }
    return identifier;
  }

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
    int? followerCount,
    DateTime? cachedAt,
  }) {
    return UserModel()
      ..pubkeyHex = pubkeyHex ?? this.pubkeyHex
      ..name = name ?? this.name
      ..about = about ?? this.about
      ..nip05 = nip05 ?? this.nip05
      ..banner = banner ?? this.banner
      ..profileImage = profileImage ?? this.profileImage
      ..lud16 = lud16 ?? this.lud16
      ..updatedAt = updatedAt ?? this.updatedAt
      ..website = website ?? this.website
      ..nip05Verified = nip05Verified ?? this.nip05Verified
      ..followerCount = followerCount ?? this.followerCount
      ..cachedAt = cachedAt ?? this.cachedAt;
  }

  bool isExpired(Duration ttl) {
    return DateTime.now().difference(cachedAt) > ttl;
  }

  UserModel();

  factory UserModel.create({
    required String pubkeyHex,
    required String name,
    String about = '',
    String nip05 = '',
    String banner = '',
    String profileImage = '',
    String lud16 = '',
    DateTime? updatedAt,
    String website = '',
    bool nip05Verified = false,
    int? followerCount,
  }) {
    return UserModel()
      ..pubkeyHex = pubkeyHex
      ..name = name
      ..about = about
      ..nip05 = nip05
      ..banner = banner
      ..profileImage = profileImage
      ..lud16 = lud16
      ..updatedAt = updatedAt ?? DateTime.now()
      ..website = website
      ..nip05Verified = nip05Verified
      ..followerCount = followerCount
      ..cachedAt = DateTime.now();
  }
}
