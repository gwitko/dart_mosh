import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'constants.dart';
import 'exception.dart';

/// A 128-bit printable Mosh session key.
class MoshKey {
  /// Creates a key from exactly 16 raw bytes.
  MoshKey(Uint8List bytes) : bytes = Uint8List.fromList(bytes) {
    if (bytes.length != moshKeyLength) {
      throw const MoshException('Mosh keys must be exactly 16 bytes.');
    }
  }

  /// Parses the 22-character base64 key printed by `mosh-server`.
  factory MoshKey.parse(String printableKey) {
    if (printableKey.length != moshPrintableKeyLength) {
      throw const MoshException('Mosh printable keys must be 22 characters.');
    }

    final normalized = '$printableKey==';
    final decoded = base64.decode(normalized);
    final key = MoshKey(Uint8List.fromList(decoded));
    if (key.printable != printableKey) {
      throw const MoshException('Mosh printable key is not canonical base64.');
    }
    return key;
  }

  /// Creates a random Mosh key.
  factory MoshKey.random([Random? random]) {
    final rng = random ?? Random.secure();
    return MoshKey(
      Uint8List.fromList(
        List<int>.generate(moshKeyLength, (_) => rng.nextInt(moshByteModulus)),
      ),
    );
  }

  /// Raw 16-byte key material.
  final Uint8List bytes;

  /// Canonical 22-character printable form used by `MOSH CONNECT`.
  String get printable =>
      base64.encode(bytes).substring(0, moshPrintableKeyLength);
}
