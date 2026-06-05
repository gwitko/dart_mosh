import 'dart:io';
import 'dart:typed_data';

final ZLibCodec _zlib = ZLibCodec();

/// Compresses a Mosh transport instruction payload with zlib.
Uint8List moshCompress(List<int> data) =>
    Uint8List.fromList(_zlib.encode(data));

/// Decompresses a zlib-compressed Mosh transport instruction payload.
Uint8List moshDecompress(List<int> data) =>
    Uint8List.fromList(_zlib.decode(data));
