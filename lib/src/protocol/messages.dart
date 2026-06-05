import 'dart:typed_data';

import 'protobuf.dart';

sealed class MoshClientInstruction {
  const MoshClientInstruction();

  Uint8List encode();
}

class MoshKeystroke extends MoshClientInstruction {
  const MoshKeystroke(this.keys);

  final List<int> keys;

  @override
  Uint8List encode() {
    final keystroke = ProtoWriter()..bytes(_keysField, keys);
    return (ProtoWriter()..bytes(_keystrokeField, keystroke.takeBytes()))
        .takeBytes();
  }
}

class MoshResize extends MoshClientInstruction {
  const MoshResize({required this.columns, required this.rows});

  final int columns;
  final int rows;

  @override
  Uint8List encode() {
    final resize = ProtoWriter()
      ..int32(_resizeColumnsField, columns)
      ..int32(_resizeRowsField, rows);
    return (ProtoWriter()..bytes(_resizeField, resize.takeBytes())).takeBytes();
  }
}

class MoshUserMessage {
  const MoshUserMessage(this.instructions);

  final List<MoshClientInstruction> instructions;

  Uint8List encode() {
    final writer = ProtoWriter();
    for (final instruction in instructions) {
      writer.bytes(_instructionField, instruction.encode());
    }
    return writer.takeBytes();
  }
}

class MoshHostMessage {
  const MoshHostMessage({this.hostBytes = const <int>[], this.echoAck});

  final List<int> hostBytes;
  final int? echoAck;

  factory MoshHostMessage.decode(List<int> bytes) {
    final message = ProtoReader(bytes);
    final out = BytesBuilder(copy: false);
    int? echoAck;

    while (!message.isDone) {
      final field = message.nextField();
      if (field.number != _instructionField) {
        message.skip(field.wireType);
        continue;
      }

      final instruction = ProtoReader(message.readBytes());
      while (!instruction.isDone) {
        final instructionField = instruction.nextField();
        switch (instructionField.number) {
          case _hostOutputField:
            final hostBytes = ProtoReader(instruction.readBytes());
            while (!hostBytes.isDone) {
              final hostField = hostBytes.nextField();
              if (hostField.number == _hostBytesField) {
                out.add(hostBytes.readBytes());
              } else {
                hostBytes.skip(hostField.wireType);
              }
            }
          case _echoAckField:
            final ack = ProtoReader(instruction.readBytes());
            while (!ack.isDone) {
              final ackField = ack.nextField();
              if (ackField.number == _echoAckNumField) {
                echoAck = ack.readVarint();
              } else {
                ack.skip(ackField.wireType);
              }
            }
          default:
            instruction.skip(instructionField.wireType);
        }
      }
    }

    return MoshHostMessage(hostBytes: out.takeBytes(), echoAck: echoAck);
  }
}

const int _instructionField = 1;
const int _keystrokeField = 2;
const int _resizeField = 3;
const int _keysField = 4;
const int _resizeColumnsField = 5;
const int _resizeRowsField = 6;
const int _hostOutputField = 2;
const int _echoAckField = 7;
const int _echoAckNumField = 8;
const int _hostBytesField = 4;
