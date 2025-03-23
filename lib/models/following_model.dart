import 'package:hive/hive.dart';

part 'following_model.g.dart';

@HiveType(typeId: 6)
class FollowingModel extends HiveObject {
  @HiveField(0)
  List<String> pubkeys;

  @HiveField(1)
  DateTime updatedAt;

  FollowingModel({
    required this.pubkeys,
    required this.updatedAt,
  });
}
