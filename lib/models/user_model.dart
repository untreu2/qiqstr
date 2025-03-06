import 'package:hive/hive.dart';

part 'user_model.g.dart';

@HiveType(typeId: 2)
class UserModel extends HiveObject {
  @HiveField(0)
  final String npub;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String about;

  @HiveField(3)
  final String nip05;

  @HiveField(4)
  final String banner;

  @HiveField(5)
  final String profileImage;

  @HiveField(6)
  final String lud16;

  @HiveField(7)
  final DateTime updatedAt;

  @HiveField(8)
  final String website;

  UserModel({
    required this.npub,
    required this.name,
    required this.about,
    required this.nip05,
    required this.banner,
    required this.profileImage,
    required this.lud16,
    required this.updatedAt,
    required this.website,
  });

  factory UserModel.fromCachedProfile(String npub, Map<String, String> data) {
    return UserModel(
      npub: npub,
      name: data['name'] ?? 'Anonymous',
      about: data['about'] ?? '',
      nip05: data['nip05'] ?? '',
      banner: data['banner'] ?? '',
      profileImage: data['profileImage'] ?? '',
      lud16: data['lud16'] ?? '',
      website: data['website'] ?? '',
      updatedAt: DateTime.now(),
    );
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      npub: json['npub'] as String,
      name: json['name'] as String,
      about: json['about'] as String,
      nip05: json['nip05'] as String,
      banner: json['banner'] as String,
      profileImage: json['profileImage'] as String,
      lud16: json['lud16'] as String? ?? '',
      website: json['website'] as String? ?? '',
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'npub': npub,
        'name': name,
        'about': about,
        'nip05': nip05,
        'banner': banner,
        'profileImage': profileImage,
        'lud16': lud16,
        'website': website,
        'updatedAt': updatedAt.toIso8601String(),
      };
}
