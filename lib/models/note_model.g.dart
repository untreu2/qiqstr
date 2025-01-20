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
      content: fields[1] as String,
      author: fields[2] as String,
      authorName: fields[3] as String,
      authorProfileImage: fields[4] as String,
      timestamp: fields[5] as DateTime,
      isRepost: fields[6] as bool,
      repostedBy: fields[7] as String?,
      repostedByName: fields[8] as String?,
      repostedByProfileImage: fields[9] as String?,
      repostTimestamp: fields[10] as DateTime?,
      repostCount: fields[11] as int,
    );
  }

  @override
  void write(BinaryWriter writer, NoteModel obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.content)
      ..writeByte(2)
      ..write(obj.author)
      ..writeByte(3)
      ..write(obj.authorName)
      ..writeByte(4)
      ..write(obj.authorProfileImage)
      ..writeByte(5)
      ..write(obj.timestamp)
      ..writeByte(6)
      ..write(obj.isRepost)
      ..writeByte(7)
      ..write(obj.repostedBy)
      ..writeByte(8)
      ..write(obj.repostedByName)
      ..writeByte(9)
      ..write(obj.repostedByProfileImage)
      ..writeByte(10)
      ..write(obj.repostTimestamp)
      ..writeByte(11)
      ..write(obj.repostCount);
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
