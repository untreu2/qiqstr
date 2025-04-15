// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'following_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FollowingModelAdapter extends TypeAdapter<FollowingModel> {
  @override
  final int typeId = 6;

  @override
  FollowingModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FollowingModel(
      pubkeys: (fields[0] as List).cast<String>(),
      updatedAt: fields[1] as DateTime,
      npub: fields[2] as String,
    );
  }

  @override
  void write(BinaryWriter writer, FollowingModel obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.pubkeys)
      ..writeByte(1)
      ..write(obj.updatedAt)
      ..writeByte(2)
      ..write(obj.npub);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FollowingModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
