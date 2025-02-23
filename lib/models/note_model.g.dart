// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class NoteModelAdapter extends TypeAdapter<NoteModel> {
  @override
  final int typeId = 0;

  @override
  NoteModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return NoteModel(
      id: fields[0] as String,
      uniqueId: fields[1] as String,
      content: fields[2] as String,
      author: fields[3] as String,
      timestamp: fields[4] as DateTime,
      isRepost: fields[5] as bool,
      repostedBy: fields[6] as String?,
      repostTimestamp: fields[7] as DateTime?,
      repostCount: fields[8] as int,
      rawWs: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, NoteModel obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.uniqueId)
      ..writeByte(2)
      ..write(obj.content)
      ..writeByte(3)
      ..write(obj.author)
      ..writeByte(4)
      ..write(obj.timestamp)
      ..writeByte(5)
      ..write(obj.isRepost)
      ..writeByte(6)
      ..write(obj.repostedBy)
      ..writeByte(7)
      ..write(obj.repostTimestamp)
      ..writeByte(8)
      ..write(obj.repostCount)
      ..writeByte(9)
      ..write(obj.rawWs);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
