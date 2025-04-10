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
      targetEventId: fields[1] as String,
      sender: fields[2] as String,
      recipient: fields[3] as String,
      bolt11: fields[4] as String,
      timestamp: fields[5] as DateTime,
      fetchedAt: fields[6] as DateTime,
      amount: fields[7] as int,
      memo: fields[8] as String,
    );
  }

  @override
  void write(BinaryWriter writer, ZapModel obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.targetEventId)
      ..writeByte(2)
      ..write(obj.sender)
      ..writeByte(3)
      ..write(obj.recipient)
      ..writeByte(4)
      ..write(obj.bolt11)
      ..writeByte(5)
      ..write(obj.timestamp)
      ..writeByte(6)
      ..write(obj.fetchedAt)
      ..writeByte(7)
      ..write(obj.amount)
      ..writeByte(8)
      ..write(obj.memo);
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
