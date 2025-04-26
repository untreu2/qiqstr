// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reply_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ReplyModelAdapter extends TypeAdapter<ReplyModel> {
  @override
  final int typeId = 2;

  @override
  ReplyModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ReplyModel(
      id: fields[0] as String,
      author: fields[1] as String,
      content: fields[2] as String,
      timestamp: fields[3] as DateTime,
      parentEventId: fields[4] as String,
      rootEventId: fields[5] as String?,
      fetchedAt: fields[6] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, ReplyModel obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.author)
      ..writeByte(2)
      ..write(obj.content)
      ..writeByte(3)
      ..write(obj.timestamp)
      ..writeByte(4)
      ..write(obj.parentEventId)
      ..writeByte(5)
      ..write(obj.rootEventId)
      ..writeByte(6)
      ..write(obj.fetchedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplyModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
