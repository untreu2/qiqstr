import 'package:isar/isar.dart';

part 'following_model.g.dart';

@collection
class FollowingModel {
  Id id = Isar.autoIncrement;

  @Index(unique: true, type: IndexType.hash)
  late String userPubkeyHex;

  late List<String> followingPubkeys;
  late DateTime updatedAt;
  late DateTime cachedAt;

  static FollowingModel fromFollowingModel(String userPubkeyHex, List<String> followingPubkeys) {
    return FollowingModel()
      ..userPubkeyHex = userPubkeyHex
      ..followingPubkeys = followingPubkeys
      ..updatedAt = DateTime.now()
      ..cachedAt = DateTime.now();
  }

  List<String> toFollowingList() {
    return List<String>.from(followingPubkeys);
  }

  bool isExpired(Duration ttl) {
    return DateTime.now().difference(cachedAt) > ttl;
  }

  FollowingModel copyWith({
    String? userPubkeyHex,
    List<String>? followingPubkeys,
    DateTime? updatedAt,
    DateTime? cachedAt,
  }) {
    return FollowingModel()
      ..userPubkeyHex = userPubkeyHex ?? this.userPubkeyHex
      ..followingPubkeys = followingPubkeys ?? this.followingPubkeys
      ..updatedAt = updatedAt ?? this.updatedAt
      ..cachedAt = cachedAt ?? this.cachedAt;
  }
}

