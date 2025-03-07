// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'repost_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RepostModelAdapter extends TypeAdapter<RepostModel> {
  @override
  final int typeId = 3;

  @override
  RepostModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RepostModel(
      id: fields[0] as String,
      originalNoteId: fields[1] as String,
      repostedBy: fields[2] as String,
      repostTimestamp: fields[3] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, RepostModel obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.originalNoteId)
      ..writeByte(2)
      ..write(obj.repostedBy)
      ..writeByte(3)
      ..write(obj.repostTimestamp);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RepostModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
