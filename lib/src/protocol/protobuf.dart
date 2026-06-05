import 'dart:typed_data';

import '../exception.dart';

class ProtoField {
  const ProtoField(this.number, this.wireType);

  final int number;
  final int wireType;
}

class ProtoWriter {
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  void uint32(int field, int value) => _varintField(field, value);

  void uint64(int field, int value) => _varintField(field, value);

  void int32(int field, int value) => _varintField(field, value);

  void bytes(int field, List<int> value) {
    _tag(field, _wireTypeLengthDelimited);
    _varint(value.length);
    _bytes.add(value);
  }

  Uint8List takeBytes() => _bytes.takeBytes();

  void _varintField(int field, int value) {
    _tag(field, _wireTypeVarint);
    _varint(value);
  }

  void _tag(int field, int wireType) =>
      _varint((field << _wireTypeBits) | wireType);

  void _varint(int value) {
    if (value < 0) {
      throw MoshException('Negative protobuf varint is not supported: $value.');
    }
    var remaining = value;
    while (remaining >= _varintContinuationBit) {
      _bytes.addByte((remaining & _varintPayloadMask) | _varintContinuationBit);
      remaining >>= _varintPayloadBits;
    }
    _bytes.addByte(remaining);
  }
}

class ProtoReader {
  ProtoReader(List<int> bytes) : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;
  var _offset = 0;

  bool get isDone => _offset >= _bytes.length;

  ProtoField nextField() {
    final tag = readVarint();
    return ProtoField(tag >> _wireTypeBits, tag & _wireTypeMask);
  }

  int readVarint() {
    var shift = 0;
    var result = 0;
    while (shift < _maxVarintBits) {
      if (_offset >= _bytes.length) {
        throw const MoshException('Unexpected end of protobuf varint.');
      }
      final byte = _bytes[_offset++];
      result |= (byte & _varintPayloadMask) << shift;
      if ((byte & _varintContinuationBit) == 0) return result;
      shift += _varintPayloadBits;
    }
    throw const MoshException('Protobuf varint is too long.');
  }

  Uint8List readBytes() {
    final length = readVarint();
    if (_offset + length > _bytes.length) {
      throw const MoshException('Unexpected end of protobuf bytes field.');
    }
    final value = _bytes.sublist(_offset, _offset + length);
    _offset += length;
    return value;
  }

  void skip(int wireType) {
    switch (wireType) {
      case _wireTypeVarint:
        readVarint();
      case _wireTypeFixed64:
        _skipBytes(_fixed64Length);
      case _wireTypeLengthDelimited:
        _skipBytes(readVarint());
      case _wireTypeFixed32:
        _skipBytes(_fixed32Length);
      default:
        throw MoshException('Unsupported protobuf wire type: $wireType.');
    }
  }

  void _skipBytes(int length) {
    if (_offset + length > _bytes.length) {
      throw const MoshException('Unexpected end of protobuf field.');
    }
    _offset += length;
  }
}

const int _wireTypeVarint = 0;
const int _wireTypeFixed64 = 1;
const int _wireTypeLengthDelimited = 2;
const int _wireTypeFixed32 = 5;
const int _wireTypeBits = 3;
const int _wireTypeMask = 0x7;
const int _varintPayloadBits = 7;
const int _varintPayloadMask = 0x7f;
const int _varintContinuationBit = 0x80;
const int _maxVarintBits = 64;
const int _fixed32Length = 4;
const int _fixed64Length = 8;
