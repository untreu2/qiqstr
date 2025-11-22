import 'package:isar/isar.dart';

part 'user_model_isar.g.dart';

@collection
class UserModelIsar {
  Id id = Isar.autoIncrement;

  @Index(unique: true, type: IndexType.hash)
  late String pubkeyHex; // Primary identifier - always hex format

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

  static UserModelIsar fromUserModel(String pubkeyHex, Map<String, String> profileData) {
    return UserModelIsar()
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

  bool isExpired(Duration ttl) {
    return DateTime.now().difference(cachedAt) > ttl;
  }
}

