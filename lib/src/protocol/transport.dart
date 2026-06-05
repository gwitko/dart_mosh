import 'dart:typed_data';

import '../constants.dart';
import 'protobuf.dart';

class MoshTransportInstruction {
  const MoshTransportInstruction({
    this.protocolVersion = moshProtocolVersion,
    this.oldNum = 0,
    this.newNum = 0,
    this.ackNum = 0,
    this.throwawayNum = 0,
    this.diff = const <int>[],
    this.chaff = const <int>[],
  });

  final int protocolVersion;
  final int oldNum;
  final int newNum;
  final int ackNum;
  final int throwawayNum;
  final List<int> diff;
  final List<int> chaff;

  Uint8List encode() {
    final writer = ProtoWriter();
    writer.uint32(_protocolVersionField, protocolVersion);
    writer.uint64(_oldNumField, oldNum);
    writer.uint64(_newNumField, newNum);
    writer.uint64(_ackNumField, ackNum);
    writer.uint64(_throwawayNumField, throwawayNum);
    if (diff.isNotEmpty) writer.bytes(_diffField, diff);
    if (chaff.isNotEmpty) writer.bytes(_chaffField, chaff);
    return writer.takeBytes();
  }

  factory MoshTransportInstruction.decode(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var protocolVersion = moshProtocolVersion;
    var oldNum = 0;
    var newNum = 0;
    var ackNum = 0;
    var throwawayNum = 0;
    var diff = const <int>[];
    var chaff = const <int>[];

    while (!reader.isDone) {
      final field = reader.nextField();
      switch (field.number) {
        case _protocolVersionField:
          protocolVersion = reader.readVarint();
        case _oldNumField:
          oldNum = reader.readVarint();
        case _newNumField:
          newNum = reader.readVarint();
        case _ackNumField:
          ackNum = reader.readVarint();
        case _throwawayNumField:
          throwawayNum = reader.readVarint();
        case _diffField:
          diff = reader.readBytes();
        case _chaffField:
          chaff = reader.readBytes();
        default:
          reader.skip(field.wireType);
      }
    }

    return MoshTransportInstruction(
      protocolVersion: protocolVersion,
      oldNum: oldNum,
      newNum: newNum,
      ackNum: ackNum,
      throwawayNum: throwawayNum,
      diff: diff,
      chaff: chaff,
    );
  }
}

const int _protocolVersionField = 1;
const int _oldNumField = 2;
const int _newNumField = 3;
const int _ackNumField = 4;
const int _throwawayNumField = 5;
const int _diffField = 6;
const int _chaffField = 7;
