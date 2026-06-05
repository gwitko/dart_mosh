import 'dart:typed_data';

import '../constants.dart';
import '../exception.dart';
import '../key.dart';
import '../nonce.dart';
import 'aead.dart';
import 'aes_ocb.dart';

class MoshPacketCipher implements MoshCipher {
  MoshPacketCipher(this.delegate);

  factory MoshPacketCipher.aesOcb(MoshKey key) {
    return MoshPacketCipher(AesOcb(key.bytes));
  }

  final MoshAead delegate;

  @override
  Uint8List encrypt({required int nonce, required Uint8List plaintext}) {
    final nonceBytes = MoshNonce(nonce).wireBytes;
    final encrypted = delegate.seal(
      nonce: MoshNonce(nonce).aeadBytes,
      plaintext: plaintext,
    );
    return Uint8List.fromList([...nonceBytes, ...encrypted]);
  }

  @override
  Uint8List decrypt(Uint8List packet) {
    if (packet.length < _minimumPacketLength) {
      throw const MoshException(
        'Mosh packet is too short to contain nonce and tag.',
      );
    }
    final nonce = MoshNonce.fromWire(packet.sublist(0, moshWireNonceLength));
    return delegate.open(
      nonce: nonce.aeadBytes,
      ciphertextWithTag: packet.sublist(moshWireNonceLength),
    );
  }
}

const int _minimumPacketLength = moshWireNonceLength + moshAeadTagLength;
