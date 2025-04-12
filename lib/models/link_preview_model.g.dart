// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'link_preview_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LinkPreviewModelAdapter extends TypeAdapter<LinkPreviewModel> {
  @override
  final int typeId = 7;

  @override
  LinkPreviewModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LinkPreviewModel(
      title: fields[0] as String,
      imageUrl: fields[1] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, LinkPreviewModel obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.title)
      ..writeByte(1)
      ..write(obj.imageUrl);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkPreviewModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
