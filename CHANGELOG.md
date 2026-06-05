# Changelog

## 0.0.2

- Added public API documentation.
- Added package example.

## 0.0.1

Initial release.

- Added `mosh-server` bootstrap command helpers.
- Added `MOSH CONNECT` parsing and printable key support.
- Added Mosh packet encryption with pure Dart AES-OCB.
- Added transport framing, compression, fragmentation, replay protection, and
  protobuf codecs.
- Added `MoshSession` for UDP terminal I/O, resize, retransmit, acknowledgements,
  and rehoming.
