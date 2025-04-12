import 'package:hive/hive.dart';

part 'link_preview_model.g.dart';

@HiveType(typeId: 7)
class LinkPreviewModel extends HiveObject {
  @HiveField(0)
  String title;

  @HiveField(1)
  String? imageUrl;

  LinkPreviewModel({
    required this.title,
    this.imageUrl,
  });
}
