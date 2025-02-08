// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reaction_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ReactionModelAdapter extends TypeAdapter<ReactionModel> {
  @override
  final int typeId = 1;

  @override
  ReactionModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ReactionModel(
      id: fields[0] as String,
      targetEventId: fields[1] as String,
      author: fields[2] as String,
      content: fields[3] as String,
      timestamp: fields[4] as DateTime,
      fetchedAt: fields[5] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, ReactionModel obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.targetEventId)
      ..writeByte(2)
      ..write(obj.author)
      ..writeByte(3)
      ..write(obj.content)
      ..writeByte(4)
      ..write(obj.timestamp)
      ..writeByte(5)
      ..write(obj.fetchedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReactionModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
