// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audiobook.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AudiobookAdapter extends TypeAdapter<Audiobook> {
  @override
  final int typeId = 0;

  @override
  Audiobook read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Audiobook(
      id: fields[0] as String,
      title: fields[1] as String,
      author: fields[2] as String?,
      chapters: (fields[3] as List).cast<Chapter>(),
      totalDuration: fields[4] as Duration,
      coverArt: fields[8] as Uint8List?,
      tags: (fields[9] as List?)?.cast<String>(),
      isFavorited: fields[10] as bool,
      lastModified: fields[11] as int?,
      contentHash: fields[12] as String?,
      rating: fields[5] as double?,
      review: fields[6] as String?,
      reviewTimestamp: fields[7] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Audiobook obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.author)
      ..writeByte(3)
      ..write(obj.chapters)
      ..writeByte(4)
      ..write(obj.totalDuration)
      ..writeByte(5)
      ..write(obj.rating)
      ..writeByte(6)
      ..write(obj.review)
      ..writeByte(7)
      ..write(obj.reviewTimestamp)
      ..writeByte(8)
      ..write(obj.coverArt)
      ..writeByte(9)
      ..write(obj.tags.toList())
      ..writeByte(10)
      ..write(obj.isFavorited)
      ..writeByte(11)
      ..write(obj.lastModified)
      ..writeByte(12)
      ..write(obj.contentHash);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudiobookAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
