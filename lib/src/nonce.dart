import 'dart:typed_data';

import 'constants.dart';
import 'exception.dart';

class MoshNonce {
  MoshNonce(int value) : wireBytes = _encode(value) {
    if (value < 0) {
      throw const MoshException('Mosh nonce cannot be negative.');
    }
  }

  MoshNonce.fromWire(Uint8List bytes) : wireBytes = Uint8List.fromList(bytes) {
    if (bytes.length != moshWireNonceLength) {
      throw const MoshException('Mosh wire nonces are exactly 8 bytes.');
    }
  }

  final Uint8List wireBytes;

  Uint8List get aeadBytes => Uint8List.fromList([
    ...List<int>.filled(moshAeadNoncePrefixLength, 0),
    ...wireBytes,
  ]);

  int get sequence {
    var value = 0;
    for (final byte in wireBytes) {
      value = (value << _bitsPerByte) | byte;
    }
    return value & _sequenceMask;
  }

  static Uint8List _encode(int value) {
    final data = Uint8List(moshWireNonceLength);
    var remaining = value;
    for (var i = moshWireNonceLength - 1; i >= 0; i--) {
      data[i] = remaining & _byteMask;
      remaining >>= _bitsPerByte;
    }
    return data;
  }
}

const int _bitsPerByte = 8;
const int _byteMask = 0xff;
const int _sequenceMask = 0x7fffffffffffffff;
