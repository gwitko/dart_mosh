import 'dart:typed_data';

import 'package:pointycastle/api.dart' show KeyParameter;
import 'package:pointycastle/block/aes.dart' show AESEngine;

import '../exception.dart';
import 'aead.dart';

/// Pure Dart AES-OCB implementation compatible with stock `mosh-server`.
class AesOcb implements MoshAead {
  /// Creates an AES-OCB cipher with a 128, 192, or 256 bit AES [key].
  AesOcb(
    Uint8List key, {
    this.associatedData = const <int>[],
    this.tagLength = _aesBlockLength,
  }) : _aes = _AesBlockCipher(key) {
    if (!_validKeyLengths.contains(key.length)) {
      throw const MoshException('AES-OCB keys must be 16, 24, or 32 bytes.');
    }
    if (tagLength <= 0 || tagLength > _maxTagLength) {
      throw const MoshException(
        'AES-OCB tagLength must be between 1 and 16 bytes.',
      );
    }
    _lStar = _aes.encryptBlock(Uint8List(_aesBlockLength));
    _lDollar = _double(_lStar);
    _lValues.add(_double(_lDollar));
    _associatedDataHash = _hash(Uint8List.fromList(associatedData));
  }

  /// Associated data authenticated with each message.
  final List<int> associatedData;

  /// Authentication tag length in bytes.
  final int tagLength;
  final _AesBlockCipher _aes;
  final List<Uint8List> _lValues = <Uint8List>[];
  late final Uint8List _lStar;
  late final Uint8List _lDollar;
  late final Uint8List _associatedDataHash;

  /// Encrypts [plaintext] and appends an authentication tag.
  @override
  Uint8List seal({required Uint8List nonce, required Uint8List plaintext}) {
    _checkNonce(nonce);

    var offset = _initialOffset(nonce);
    var checksum = Uint8List(_aesBlockLength);
    final ciphertext = BytesBuilder(copy: false);
    final fullBlocks = plaintext.length ~/ _aesBlockLength;
    final remainder = plaintext.length % _aesBlockLength;

    for (var i = 1; i <= fullBlocks; i++) {
      offset = _xor(offset, _lSub(_ntz(i)));
      final block = plaintext.sublist(
        (i - 1) * _aesBlockLength,
        i * _aesBlockLength,
      );
      ciphertext.add(_xor(offset, _aes.encryptBlock(_xor(block, offset))));
      checksum = _xor(checksum, block);
    }

    Uint8List tag;
    if (remainder > 0) {
      final partial = plaintext.sublist(fullBlocks * _aesBlockLength);
      final offsetStar = _xor(offset, _lStar);
      final pad = _aes.encryptBlock(offsetStar);
      ciphertext.add(_xorPrefix(partial, pad));
      checksum = _xor(checksum, _pad(partial));
      tag = _xor(
        _aes.encryptBlock(_xor(_xor(checksum, offsetStar), _lDollar)),
        _associatedDataHash,
      );
    } else {
      tag = _xor(
        _aes.encryptBlock(_xor(_xor(checksum, offset), _lDollar)),
        _associatedDataHash,
      );
    }

    ciphertext.add(tag.sublist(0, tagLength));
    return ciphertext.takeBytes();
  }

  /// Verifies and decrypts [ciphertextWithTag].
  @override
  Uint8List open({
    required Uint8List nonce,
    required Uint8List ciphertextWithTag,
  }) {
    _checkNonce(nonce);
    if (ciphertextWithTag.length < tagLength) {
      throw const MoshException('AES-OCB ciphertext is shorter than its tag.');
    }

    final tagStart = ciphertextWithTag.length - tagLength;
    final ciphertext = ciphertextWithTag.sublist(0, tagStart);
    final receivedTag = ciphertextWithTag.sublist(tagStart);
    var offset = _initialOffset(nonce);
    var checksum = Uint8List(_aesBlockLength);
    final plaintext = BytesBuilder(copy: false);
    final fullBlocks = ciphertext.length ~/ _aesBlockLength;
    final remainder = ciphertext.length % _aesBlockLength;

    for (var i = 1; i <= fullBlocks; i++) {
      offset = _xor(offset, _lSub(_ntz(i)));
      final block = ciphertext.sublist(
        (i - 1) * _aesBlockLength,
        i * _aesBlockLength,
      );
      final plainBlock = _xor(offset, _aes.decryptBlock(_xor(block, offset)));
      plaintext.add(plainBlock);
      checksum = _xor(checksum, plainBlock);
    }

    Uint8List tag;
    if (remainder > 0) {
      final partial = ciphertext.sublist(fullBlocks * _aesBlockLength);
      final offsetStar = _xor(offset, _lStar);
      final pad = _aes.encryptBlock(offsetStar);
      final plainPartial = _xorPrefix(partial, pad);
      plaintext.add(plainPartial);
      checksum = _xor(checksum, _pad(plainPartial));
      tag = _xor(
        _aes.encryptBlock(_xor(_xor(checksum, offsetStar), _lDollar)),
        _associatedDataHash,
      );
    } else {
      tag = _xor(
        _aes.encryptBlock(_xor(_xor(checksum, offset), _lDollar)),
        _associatedDataHash,
      );
    }

    if (!_constantTimeEquals(receivedTag, tag.sublist(0, tagLength))) {
      throw const MoshException('AES-OCB authentication tag check failed.');
    }

    return plaintext.takeBytes();
  }

  void _checkNonce(Uint8List nonce) {
    if (nonce.isEmpty || nonce.length > _maxNonceLength) {
      throw const MoshException('AES-OCB nonces must be 1 to 15 bytes.');
    }
  }

  Uint8List _hash(Uint8List data) {
    var sum = Uint8List(_aesBlockLength);
    var offset = Uint8List(_aesBlockLength);
    final fullBlocks = data.length ~/ _aesBlockLength;
    final remainder = data.length % _aesBlockLength;

    for (var i = 1; i <= fullBlocks; i++) {
      offset = _xor(offset, _lSub(_ntz(i)));
      final block = data.sublist(
        (i - 1) * _aesBlockLength,
        i * _aesBlockLength,
      );
      sum = _xor(sum, _aes.encryptBlock(_xor(block, offset)));
    }

    if (remainder > 0) {
      offset = _xor(offset, _lStar);
      final partial = data.sublist(fullBlocks * _aesBlockLength);
      sum = _xor(sum, _aes.encryptBlock(_xor(_pad(partial), offset)));
    }

    return sum;
  }

  Uint8List _initialOffset(Uint8List nonce) {
    final formatted = Uint8List(_aesBlockLength);
    final tagBits = (tagLength * _bitsPerByte) % _blockBits;
    formatted[0] = tagBits << 1;
    formatted.setRange(_aesBlockLength - nonce.length, _aesBlockLength, nonce);

    final markerBit = _lastBlockBit - nonce.length * _bitsPerByte;
    formatted[markerBit ~/ _bitsPerByte] |=
        1 << (_lastByteBit - (markerBit % _bitsPerByte));

    final bottom = formatted[_lastBlockByte] & _bottomMask;
    final top = Uint8List.fromList(formatted);
    top[_lastBlockByte] &= _topMask;

    final ktop = _aes.encryptBlock(top);
    final stretch = Uint8List(_stretchLength);
    stretch.setRange(0, _aesBlockLength, ktop);
    for (var i = 0; i < _stretchTailLength; i++) {
      stretch[_aesBlockLength + i] = ktop[i] ^ ktop[i + 1];
    }

    return _sliceBits(stretch, bottom, _aesBlockLength);
  }

  Uint8List _lSub(int index) {
    while (_lValues.length <= index) {
      _lValues.add(_double(_lValues.last));
    }
    return _lValues[index];
  }
}

class _AesBlockCipher {
  _AesBlockCipher(Uint8List key) {
    final keyParameter = KeyParameter(key);
    _encrypt.init(true, keyParameter);
    _decrypt.init(false, keyParameter);
  }

  final AESEngine _encrypt = AESEngine();
  final AESEngine _decrypt = AESEngine();

  Uint8List encryptBlock(Uint8List block) => _process(_encrypt, block);

  Uint8List decryptBlock(Uint8List block) => _process(_decrypt, block);

  Uint8List _process(AESEngine engine, Uint8List block) {
    if (block.length != _aesBlockLength) {
      throw const MoshException('AES block input must be exactly 16 bytes.');
    }
    final out = Uint8List(_aesBlockLength);
    engine.processBlock(block, 0, out, 0);
    return out;
  }
}

Uint8List _double(Uint8List block) {
  var carry = 0;
  final out = Uint8List(_aesBlockLength);
  for (var i = _lastBlockByte; i >= 0; i--) {
    final value = block[i];
    out[i] = ((value << 1) & _byteMask) | carry;
    carry = (value & _highBit) == 0 ? 0 : 1;
  }
  if (carry != 0) {
    out[_lastBlockByte] ^= _ocbReductionPolynomial;
  }
  return out;
}

Uint8List _xor(List<int> left, List<int> right) {
  if (left.length != right.length) {
    throw const MoshException(
      'Cannot xor byte strings with different lengths.',
    );
  }
  final out = Uint8List(left.length);
  for (var i = 0; i < left.length; i++) {
    out[i] = left[i] ^ right[i];
  }
  return out;
}

Uint8List _xorPrefix(List<int> left, List<int> right) {
  if (left.length > right.length) {
    throw const MoshException('Cannot xor prefix longer than source.');
  }
  final out = Uint8List(left.length);
  for (var i = 0; i < left.length; i++) {
    out[i] = left[i] ^ right[i];
  }
  return out;
}

Uint8List _pad(List<int> bytes) {
  if (bytes.length >= _aesBlockLength) {
    throw const MoshException('OCB padding is only for partial blocks.');
  }
  final out = Uint8List(_aesBlockLength);
  out.setRange(0, bytes.length, bytes);
  out[bytes.length] = _highBit;
  return out;
}

Uint8List _sliceBits(Uint8List source, int bitOffset, int length) {
  final out = Uint8List(length);
  for (var i = 0; i < length * _bitsPerByte; i++) {
    final sourceBit = bitOffset + i;
    final bit =
        (source[sourceBit ~/ _bitsPerByte] >>
            (_lastByteBit - (sourceBit % _bitsPerByte))) &
        _lowBit;
    out[i ~/ _bitsPerByte] |= bit << (_lastByteBit - (i % _bitsPerByte));
  }
  return out;
}

const int _aesBlockLength = 16;
const int _aes192KeyLength = 24;
const int _aes256KeyLength = 32;
const int _maxTagLength = _aesBlockLength;
const int _maxNonceLength = _aesBlockLength - 1;
const int _bitsPerByte = 8;
const int _blockBits = _aesBlockLength * _bitsPerByte;
const int _lastBlockBit = _blockBits - 1;
const int _lastByteBit = _bitsPerByte - 1;
const int _lastBlockByte = _aesBlockLength - 1;
const int _byteMask = 0xff;
const int _highBit = 0x80;
const int _lowBit = 0x01;
const int _bottomMask = 0x3f;
const int _topMask = 0xc0;
const int _stretchTailLength = 8;
const int _stretchLength = _aesBlockLength + _stretchTailLength;
const int _ocbReductionPolynomial = 0x87;
const Set<int> _validKeyLengths = {
  _aesBlockLength,
  _aes192KeyLength,
  _aes256KeyLength,
};

int _ntz(int value) {
  if (value <= 0) {
    throw const MoshException('ntz is only defined for positive integers.');
  }
  var count = 0;
  var remaining = value;
  while ((remaining & 1) == 0) {
    count++;
    remaining >>= 1;
  }
  return count;
}

bool _constantTimeEquals(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < left.length; i++) {
    diff |= left[i] ^ right[i];
  }
  return diff == 0;
}
