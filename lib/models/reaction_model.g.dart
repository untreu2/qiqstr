part of 'reaction_model.dart';

class ReactionModelAdapter extends TypeAdapter<ReactionModel> {
  @override
  final int typeId = 1;

  @override
  ReactionModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ReactionModel(
      id: fields[0] as String,
      author: fields[1] as String,
      content: fields[2] as String,
      timestamp: fields[3] as DateTime,
      authorName: fields[4] as String,
      authorProfileImage: fields[5] as String,
    );
  }

  @override
  void write(BinaryWriter writer, ReactionModel obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.author)
      ..writeByte(2)
      ..write(obj.content)
      ..writeByte(3)
      ..write(obj.timestamp)
      ..writeByte(4)
      ..write(obj.authorName)
      ..writeByte(5)
      ..write(obj.authorProfileImage);
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
