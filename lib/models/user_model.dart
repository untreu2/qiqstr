import 'package:hive/hive.dart';

part 'user_model.g.dart';

@HiveType(typeId: 3)
class UserModel extends HiveObject {
  @HiveField(0)
  final String npub;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String profileImage;

  @HiveField(3)
  final String nip05;

  @HiveField(4)
  final String about;

  UserModel({
    required this.npub,
    required this.name,
    required this.profileImage,
    required this.nip05,
    required this.about,
  });
}
