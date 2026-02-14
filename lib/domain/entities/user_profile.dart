class UserProfile {
  final String pubkey;
  final String? name;
  final String? displayName;
  final String? about;
  final String? picture;
  final String? banner;
  final String? nip05;
  final String? lud16;
  final String? website;
  final String? location;
  final int? createdAt;

  const UserProfile({
    required this.pubkey,
    this.name,
    this.displayName,
    this.about,
    this.picture,
    this.banner,
    this.nip05,
    this.lud16,
    this.website,
    this.location,
    this.createdAt,
  });

  UserProfile copyWith({
    String? pubkey,
    String? name,
    String? displayName,
    String? about,
    String? picture,
    String? banner,
    String? nip05,
    String? lud16,
    String? website,
    String? location,
    int? createdAt,
  }) {
    return UserProfile(
      pubkey: pubkey ?? this.pubkey,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      about: about ?? this.about,
      picture: picture ?? this.picture,
      banner: banner ?? this.banner,
      nip05: nip05 ?? this.nip05,
      lud16: lud16 ?? this.lud16,
      website: website ?? this.website,
      location: location ?? this.location,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  String get displayNameOrName => displayName ?? name ?? '';

  bool get hasProfileImage => picture != null && picture!.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'pubkeyHex': pubkey,
      'pubkey': pubkey,
      if (name != null) 'name': name!,
      if (displayName != null) 'display_name': displayName!,
      if (displayName != null) 'displayName': displayName!,
      if (about != null) 'about': about!,
      if (picture != null) 'profileImage': picture!,
      if (picture != null) 'picture': picture!,
      if (banner != null) 'banner': banner!,
      if (nip05 != null) 'nip05': nip05!,
      if (lud16 != null) 'lud16': lud16!,
      if (website != null) 'website': website!,
      if (location != null) 'location': location!,
    };
  }
}
