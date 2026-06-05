import 'dart:typed_data';

import '../constants.dart';
import '../exception.dart';
import '../key.dart';
import '../nonce.dart';
import 'aead.dart';
import 'aes_ocb.dart';

/// Mosh packet cipher that prepends the 8-byte wire nonce to each packet.
class MoshPacketCipher implements MoshCipher {
  /// Creates a packet cipher backed by [delegate].
  MoshPacketCipher(this.delegate);

  /// Creates the standard AES-OCB Mosh packet cipher.
  factory MoshPacketCipher.aesOcb(MoshKey key) {
    return MoshPacketCipher(AesOcb(key.bytes));
  }

  /// AEAD implementation used for packet payloads.
  final MoshAead delegate;

  /// Encrypts a transport packet and prefixes its wire nonce.
  @override
  Uint8List encrypt({required int nonce, required Uint8List plaintext}) {
    final nonceBytes = MoshNonce(nonce).wireBytes;
    final encrypted = delegate.seal(
      nonce: MoshNonce(nonce).aeadBytes,
      plaintext: plaintext,
    );
    return Uint8List.fromList([...nonceBytes, ...encrypted]);
  }

  /// Decrypts a packet produced by `mosh-server`.
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
