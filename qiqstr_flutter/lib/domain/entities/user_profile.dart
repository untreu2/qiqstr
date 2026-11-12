import 'package:equatable/equatable.dart';

class UserProfile extends Equatable {
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

  @override
  List<Object?> get props => [
        pubkey,
        name,
        displayName,
        about,
        picture,
        banner,
        nip05,
        lud16,
        website,
        location,
        createdAt,
      ];

  String get displayNameOrName => displayName ?? name ?? '';

  bool get hasProfileImage => picture != null && picture!.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'pubkey': pubkey,
      'name': ?name,
      'display_name': ?displayName,
      'about': ?about,
      'picture': ?picture,
      'banner': ?banner,
      'nip05': ?nip05,
      'lud16': ?lud16,
      'website': ?website,
      'location': ?location,
    };
  }
}
