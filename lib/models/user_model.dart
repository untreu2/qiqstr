class UserModel {
  final String npub;
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
    required this.npub,
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
      nip05Verified: data.containsKey('nip05Verified') ? data['nip05Verified'] == 'true' : false,
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
      nip05Verified: json.containsKey('nip05Verified') ? (json['nip05Verified'] as bool? ?? false) : false,
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
        'nip05Verified': nip05Verified,
      };
}
