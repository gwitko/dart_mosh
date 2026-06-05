import 'dart:typed_data';

/// Authenticated encryption used by the Mosh packet cipher.
abstract interface class MoshAead {
  /// Encrypts and authenticates [plaintext] with [nonce].
  Uint8List seal({required Uint8List nonce, required Uint8List plaintext});

  /// Verifies and decrypts [ciphertextWithTag] with [nonce].
  Uint8List open({
    required Uint8List nonce,
    required Uint8List ciphertextWithTag,
  });
}

/// Encrypts and decrypts complete Mosh UDP packets.
abstract interface class MoshCipher {
  /// Frames and encrypts [plaintext] with the packet [nonce].
  Uint8List encrypt({required int nonce, required Uint8List plaintext});

  /// Decrypts a complete wire packet.
  Uint8List decrypt(Uint8List packet);
}
