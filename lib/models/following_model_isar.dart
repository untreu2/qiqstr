import 'package:isar/isar.dart';

part 'following_model_isar.g.dart';

@collection
class FollowingModelIsar {
  Id id = Isar.autoIncrement;

  @Index(unique: true, type: IndexType.hash)
  late String userPubkeyHex;

  late List<String> followingPubkeys;
  late DateTime updatedAt;
  late DateTime cachedAt;

  static FollowingModelIsar fromFollowingModel(String userPubkeyHex, List<String> followingPubkeys) {
    return FollowingModelIsar()
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

  FollowingModelIsar copyWith({
    String? userPubkeyHex,
    List<String>? followingPubkeys,
    DateTime? updatedAt,
    DateTime? cachedAt,
  }) {
    return FollowingModelIsar()
      ..userPubkeyHex = userPubkeyHex ?? this.userPubkeyHex
      ..followingPubkeys = followingPubkeys ?? this.followingPubkeys
      ..updatedAt = updatedAt ?? this.updatedAt
      ..cachedAt = cachedAt ?? this.cachedAt;
  }
}
