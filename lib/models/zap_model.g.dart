// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'zap_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ZapModelAdapter extends TypeAdapter<ZapModel> {
  @override
  final int typeId = 5;

  @override
  ZapModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ZapModel(
      id: fields[0] as String,
      sender: fields[1] as String,
      recipient: fields[2] as String,
      targetEventId: fields[3] as String,
      timestamp: fields[4] as DateTime,
      bolt11: fields[5] as String,
      comment: fields[6] as String?,
      amount: fields[7] as int,
    );
  }

  @override
  void write(BinaryWriter writer, ZapModel obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.sender)
      ..writeByte(2)
      ..write(obj.recipient)
      ..writeByte(3)
      ..write(obj.targetEventId)
      ..writeByte(4)
      ..write(obj.timestamp)
      ..writeByte(5)
      ..write(obj.bolt11)
      ..writeByte(6)
      ..write(obj.comment)
      ..writeByte(7)
      ..write(obj.amount);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ZapModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
