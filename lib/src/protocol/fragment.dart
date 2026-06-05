import 'dart:math';
import 'dart:typed_data';

import '../constants.dart';
import '../exception.dart';

class MoshFragment {
  const MoshFragment({
    required this.id,
    required this.fragmentNum,
    required this.isFinal,
    required this.contents,
  });

  static const int headerLength = 10;
  static const int maxFragmentNum = 0x7fff;
  static const int finalFlag = 0x8000;

  final int id;
  final int fragmentNum;
  final bool isFinal;
  final Uint8List contents;

  Uint8List encode() {
    final out = Uint8List(headerLength + contents.length);
    final header = ByteData.view(out.buffer, out.offsetInBytes, headerLength);
    header.setUint64(_idOffset, id, Endian.big);
    header.setUint16(
      _fragmentNumOffset,
      (isFinal ? finalFlag : 0) | (fragmentNum & maxFragmentNum),
      Endian.big,
    );
    out.setRange(headerLength, out.length, contents);
    return out;
  }

  factory MoshFragment.decode(Uint8List bytes) {
    if (bytes.length < headerLength) {
      throw const MoshException('Mosh fragment is shorter than its header.');
    }
    final view = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
    final combined = view.getUint16(_fragmentNumOffset, Endian.big);
    return MoshFragment(
      id: view.getUint64(_idOffset, Endian.big),
      fragmentNum: combined & maxFragmentNum,
      isFinal: (combined & finalFlag) != 0,
      contents: Uint8List.fromList(bytes.sublist(headerLength)),
    );
  }
}

const int _idOffset = 0;
const int _fragmentNumOffset = 8;

List<MoshFragment> moshFragments(int id, Uint8List payload, int mtu) {
  if (mtu <= 0) {
    throw const MoshException('Fragment MTU must be positive.');
  }
  final fragments = <MoshFragment>[];
  var offset = 0;
  var fragmentNum = 0;
  do {
    final end = min(offset + mtu, payload.length);
    fragments.add(
      MoshFragment(
        id: id,
        fragmentNum: fragmentNum,
        isFinal: end >= payload.length,
        contents: Uint8List.fromList(payload.sublist(offset, end)),
      ),
    );
    offset = end;
    fragmentNum++;
  } while (offset < payload.length);
  return fragments;
}

class MoshFragmentAssembly {
  MoshFragmentAssembly({this.maxConcurrent = moshDefaultFragmentAssemblyLimit});

  final int maxConcurrent;
  final Map<int, _PartialMessage> _pending = <int, _PartialMessage>{};

  Uint8List? add(MoshFragment fragment) {
    final partial = _pending.putIfAbsent(fragment.id, _PartialMessage.new);
    partial.parts[fragment.fragmentNum] = fragment.contents;
    if (fragment.isFinal) {
      partial.total = fragment.fragmentNum + 1;
    }

    final assembled = partial.assemble();
    if (assembled != null) {
      _pending.removeWhere((id, _) => id <= fragment.id);
      return assembled;
    }

    while (_pending.length > maxConcurrent) {
      _pending.remove(_pending.keys.first);
    }
    return null;
  }
}

class _PartialMessage {
  final Map<int, Uint8List> parts = <int, Uint8List>{};
  int? total;

  Uint8List? assemble() {
    final expected = total;
    if (expected == null || parts.length < expected) {
      return null;
    }

    final builder = BytesBuilder(copy: false);
    for (var i = 0; i < expected; i++) {
      final part = parts[i];
      if (part == null) return null;
      builder.add(part);
    }
    return builder.takeBytes();
  }
}
