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
      timestamp: fields[3] as DateTime,
      isRepost: fields[4] as bool,
      repostedBy: fields[5] as String?,
      repostTimestamp: fields[6] as DateTime?,
      repostCount: fields[7] as int,
      rawWs: fields[8] as String?,
      reactionCount: fields[9] as int,
      replyCount: fields[10] as int,
      parsedContent: (fields[11] as Map?)?.cast<String, dynamic>(),
      hasMedia: fields[12] as bool,
      estimatedHeight: fields[13] as double?,
      isVideo: fields[14] as bool,
      videoUrl: fields[15] as String?,
      zapAmount: fields[16] as int,
      isReply: fields[17] as bool,
      parentId: fields[18] as String?,
      rootId: fields[19] as String?,
      replyIds: (fields[20] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, NoteModel obj) {
    writer
      ..writeByte(21)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.content)
      ..writeByte(2)
      ..write(obj.author)
      ..writeByte(3)
      ..write(obj.timestamp)
      ..writeByte(4)
      ..write(obj.isRepost)
      ..writeByte(5)
      ..write(obj.repostedBy)
      ..writeByte(6)
      ..write(obj.repostTimestamp)
      ..writeByte(7)
      ..write(obj.repostCount)
      ..writeByte(8)
      ..write(obj.rawWs)
      ..writeByte(9)
      ..write(obj.reactionCount)
      ..writeByte(10)
      ..write(obj.replyCount)
      ..writeByte(11)
      ..write(obj.parsedContent)
      ..writeByte(12)
      ..write(obj.hasMedia)
      ..writeByte(13)
      ..write(obj.estimatedHeight)
      ..writeByte(14)
      ..write(obj.isVideo)
      ..writeByte(15)
      ..write(obj.videoUrl)
      ..writeByte(16)
      ..write(obj.zapAmount)
      ..writeByte(17)
      ..write(obj.isReply)
      ..writeByte(18)
      ..write(obj.parentId)
      ..writeByte(19)
      ..write(obj.rootId)
      ..writeByte(20)
      ..write(obj.replyIds);
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
