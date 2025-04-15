import 'package:hive/hive.dart';

part 'following_model.g.dart';

@HiveType(typeId: 6)
class FollowingModel extends HiveObject {
  @HiveField(0)
  List<String> pubkeys;

  @HiveField(1)
  DateTime updatedAt;

  @HiveField(2)
  String npub;

  FollowingModel({
    required this.pubkeys,
    required this.updatedAt,
    required this.npub,
  });
}
