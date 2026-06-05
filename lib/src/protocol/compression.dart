import 'dart:io';
import 'dart:typed_data';

final ZLibCodec _zlib = ZLibCodec();

Uint8List moshCompress(List<int> data) =>
    Uint8List.fromList(_zlib.encode(data));

Uint8List moshDecompress(List<int> data) =>
    Uint8List.fromList(_zlib.decode(data));
