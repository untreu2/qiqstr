import 'package:isar/isar.dart';

part 'mute_model_isar.g.dart';

@collection
class MuteModelIsar {
  Id id = Isar.autoIncrement;

  @Index(unique: true, type: IndexType.hash)
  late String userPubkeyHex;

  late List<String> mutedPubkeys;
  late DateTime updatedAt;
  late DateTime cachedAt;

  static MuteModelIsar fromMuteModel(String userPubkeyHex, List<String> mutedPubkeys) {
    return MuteModelIsar()
      ..userPubkeyHex = userPubkeyHex
      ..mutedPubkeys = mutedPubkeys
      ..updatedAt = DateTime.now()
      ..cachedAt = DateTime.now();
  }

  List<String> toMuteList() {
    return List<String>.from(mutedPubkeys);
  }

  bool isExpired(Duration ttl) {
    return DateTime.now().difference(cachedAt) > ttl;
  }

  MuteModelIsar copyWith({
    String? userPubkeyHex,
    List<String>? mutedPubkeys,
    DateTime? updatedAt,
    DateTime? cachedAt,
  }) {
    return MuteModelIsar()
      ..userPubkeyHex = userPubkeyHex ?? this.userPubkeyHex
      ..mutedPubkeys = mutedPubkeys ?? this.mutedPubkeys
      ..updatedAt = updatedAt ?? this.updatedAt
      ..cachedAt = cachedAt ?? this.cachedAt;
  }
}

