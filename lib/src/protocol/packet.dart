import 'dart:typed_data';

import '../exception.dart';

class MoshTransportPacket {
  const MoshTransportPacket({
    required this.timestamp,
    required this.timestampReply,
    required this.payload,
  });

  static const int headerLength = 4;
  static const int noTimestamp = 0xffff;

  final int timestamp;
  final int timestampReply;
  final Uint8List payload;

  Uint8List encode() {
    final out = Uint8List(headerLength + payload.length);
    final header = ByteData.view(out.buffer, out.offsetInBytes, headerLength);
    header.setUint16(_timestampOffset, timestamp & noTimestamp, Endian.big);
    header.setUint16(
      _timestampReplyOffset,
      timestampReply & noTimestamp,
      Endian.big,
    );
    out.setRange(headerLength, out.length, payload);
    return out;
  }

  factory MoshTransportPacket.decode(Uint8List bytes) {
    if (bytes.length < headerLength) {
      throw const MoshException(
        'Mosh transport packet is shorter than its header.',
      );
    }
    final view = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
    return MoshTransportPacket(
      timestamp: view.getUint16(_timestampOffset, Endian.big),
      timestampReply: view.getUint16(_timestampReplyOffset, Endian.big),
      payload: Uint8List.fromList(bytes.sublist(headerLength)),
    );
  }
}

const int _timestampOffset = 0;
const int _timestampReplyOffset = 2;
