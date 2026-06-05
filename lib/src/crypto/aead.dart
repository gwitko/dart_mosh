import 'dart:typed_data';

abstract interface class MoshAead {
  Uint8List seal({required Uint8List nonce, required Uint8List plaintext});

  Uint8List open({
    required Uint8List nonce,
    required Uint8List ciphertextWithTag,
  });
}

abstract interface class MoshCipher {
  Uint8List encrypt({required int nonce, required Uint8List plaintext});

  Uint8List decrypt(Uint8List packet);
}
