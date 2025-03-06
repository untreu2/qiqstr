// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'interaction_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class InteractionModelAdapter extends TypeAdapter<InteractionModel> {
  @override
  final int typeId = 4;

  @override
  InteractionModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return InteractionModel(
      id: fields[0] as String,
      kind: fields[1] as int,
      targetNoteId: fields[2] as String,
      author: fields[3] as String,
      content: fields[4] as String,
      timestamp: fields[5] as DateTime,
      fetchedAt: fields[6] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, InteractionModel obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.kind)
      ..writeByte(2)
      ..write(obj.targetNoteId)
      ..writeByte(3)
      ..write(obj.author)
      ..writeByte(4)
      ..write(obj.content)
      ..writeByte(5)
      ..write(obj.timestamp)
      ..writeByte(6)
      ..write(obj.fetchedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InteractionModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
