import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_mosh/dart_mosh.dart';
import 'package:test/test.dart';

void main() {
  group('MoshKey', () {
    test('round-trips canonical printable keys', () {
      final key = MoshKey(Uint8List.fromList(List<int>.generate(16, (i) => i)));

      expect(MoshKey.parse(key.printable).bytes, key.bytes);
      expect(key.printable, hasLength(22));
    });

    test('rejects non-canonical printable keys', () {
      expect(() => MoshKey.parse('short'), throwsA(isA<MoshException>()));
    });
  });

  group('MoshServerConfig', () {
    test('parses mosh-server startup output', () {
      final config = MoshServerConfig.parse(
        'noise\nMOSH CONNECT 60004 AAECAwQFBgcICQoLDA0ODw\n',
        host: 'example.com',
      );

      expect(config.host, 'example.com');
      expect(config.port, 60004);
      expect(config.key.bytes, List<int>.generate(16, (i) => i));
    });
  });

  group('MoshSshBootstrap', () {
    test('builds a shell-safe mosh-server command', () {
      final bootstrap = MoshSshBootstrap(
        locale: 'C.UTF-8',
        term: 'xterm-256color',
        serverPort: 60000,
        serverPortEnd: 60010,
      );

      expect(
        bootstrap.command(),
        'TERM=xterm-256color LC_ALL=C.UTF-8 mosh-server new -s -c 256 -l C.UTF-8 -p 60000:60010',
      );
    });
  });

  group('MoshNonce', () {
    test('round-trips a server-to-client nonce with the direction bit set', () {
      final wire = Uint8List.fromList([0x80, 0, 0, 0, 0, 0, 0, 5]);

      final nonce = MoshNonce.fromWire(wire);

      expect(nonce.wireBytes, wire);
      expect(nonce.aeadBytes, [0, 0, 0, 0, 0x80, 0, 0, 0, 0, 0, 0, 5]);
    });

    test('exposes the 63-bit sequence with the direction bit masked off', () {
      final wire = Uint8List.fromList([0x80, 0, 0, 0, 0, 0, 0, 5]);

      expect(MoshNonce.fromWire(wire).sequence, 5);
      expect(MoshNonce(5).sequence, 5);
    });
  });

  group('MoshReplayFilter', () {
    test('accepts a monotonically increasing sequence once each', () {
      final filter = MoshReplayFilter();

      expect(filter.accept(0), isTrue);
      expect(filter.accept(1), isTrue);
      expect(filter.accept(2), isTrue);
      expect(filter.accept(1), isFalse);
    });

    test('accepts in-window reordering but rejects duplicates', () {
      final filter = MoshReplayFilter();

      expect(filter.accept(5), isTrue);
      expect(filter.accept(3), isTrue);
      expect(filter.accept(4), isTrue);
      expect(filter.accept(3), isFalse);
    });

    test('rejects sequences below the window', () {
      final filter = MoshReplayFilter(windowSize: 4);

      expect(filter.accept(10), isTrue);
      expect(filter.accept(6), isFalse);
      expect(filter.accept(7), isTrue);
    });
  });

  group('MoshRttEstimator', () {
    test('defaults to a one-second RTO before any sample', () {
      final rtt = MoshRttEstimator();

      expect(rtt.hasSample, isFalse);
      expect(rtt.rto, MoshRttEstimator.maxRto);
    });

    test('seeds SRTT and RTTVAR from the first sample', () {
      final rtt = MoshRttEstimator()..sample(80);

      expect(rtt.hasSample, isTrue);
      expect(rtt.srtt, 80);
      expect(rtt.rttVar, 40);
      expect(rtt.rto, 240);
    });

    test('smooths later samples and clamps the send interval', () {
      final rtt = MoshRttEstimator()
        ..sample(100)
        ..sample(100);

      expect(rtt.srtt, closeTo(100, 0.001));
      expect(rtt.sendInterval, 50);
    });

    test('ignores implausible samples', () {
      final rtt = MoshRttEstimator()
        ..sample(-1)
        ..sample(60000);

      expect(rtt.hasSample, isFalse);
    });
  });

  group('MoshFragment', () {
    test('round-trips header fields and contents', () {
      final fragment = MoshFragment(
        id: 0x0102030405060708,
        fragmentNum: 3,
        isFinal: true,
        contents: Uint8List.fromList([9, 8, 7]),
      );

      final decoded = MoshFragment.decode(fragment.encode());

      expect(decoded.id, 0x0102030405060708);
      expect(decoded.fragmentNum, 3);
      expect(decoded.isFinal, isTrue);
      expect(decoded.contents, [9, 8, 7]);
    });

    test('splits a payload into final-terminated fragments', () {
      final payload = Uint8List.fromList(List<int>.generate(10, (i) => i));

      final fragments = moshFragments(42, payload, 4);

      expect(fragments.map((f) => f.fragmentNum), [0, 1, 2]);
      expect(fragments.map((f) => f.isFinal), [false, false, true]);
      expect(fragments.every((f) => f.id == 42), isTrue);
    });

    test('reassembles out-of-order fragments', () {
      final payload = Uint8List.fromList(List<int>.generate(10, (i) => i));
      final fragments = moshFragments(42, payload, 4);
      final assembly = MoshFragmentAssembly();

      expect(assembly.add(fragments[2]), isNull);
      expect(assembly.add(fragments[0]), isNull);
      expect(assembly.add(fragments[1]), payload);
    });

    test('reassembles two interleaved messages without dropping either', () {
      final payloadA = Uint8List.fromList(List<int>.generate(10, (i) => i));
      final payloadB = Uint8List.fromList(
        List<int>.generate(10, (i) => i + 100),
      );
      final a = moshFragments(7, payloadA, 4);
      final b = moshFragments(8, payloadB, 4);
      final assembly = MoshFragmentAssembly();

      expect(assembly.add(a[0]), isNull);
      expect(assembly.add(b[0]), isNull);
      expect(assembly.add(a[1]), isNull);
      expect(assembly.add(b[1]), isNull);
      expect(assembly.add(a[2]), payloadA);
      expect(assembly.add(b[2]), payloadB);
    });

    test('bounds memory by evicting the oldest partial messages', () {
      final assembly = MoshFragmentAssembly(maxConcurrent: 2);
      assembly.add(moshFragments(1, Uint8List.fromList([1, 2, 3, 4]), 2)[0]);
      assembly.add(moshFragments(2, Uint8List.fromList([1, 2, 3, 4]), 2)[0]);
      assembly.add(moshFragments(3, Uint8List.fromList([1, 2, 3, 4]), 2)[0]);

      expect(
        assembly.add(moshFragments(1, Uint8List.fromList([1, 2, 3, 4]), 2)[1]),
        isNull,
      );
    });
  });

  group('MoshTransportPacket', () {
    test('round-trips the timestamp header and payload', () {
      final packet = MoshTransportPacket(
        timestamp: 0x3c79,
        timestampReply: MoshTransportPacket.noTimestamp,
        payload: Uint8List.fromList([1, 2, 3, 4, 5]),
      );

      final decoded = MoshTransportPacket.decode(packet.encode());

      expect(decoded.timestamp, 0x3c79);
      expect(decoded.timestampReply, 0xffff);
      expect(decoded.payload, [1, 2, 3, 4, 5]);
    });
  });

  group('compression', () {
    test('round-trips through zlib', () {
      final data = Uint8List.fromList(utf8.encode('mosh ' * 64));

      expect(moshDecompress(moshCompress(data)), data);
    });
  });

  group('transport pipeline', () {
    test(
      'round-trips an instruction through compress, fragment, reassemble',
      () {
        final instruction = MoshTransportInstruction(
          oldNum: 2,
          newNum: 3,
          ackNum: 1,
          diff: List<int>.generate(64, (i) => i % 251),
        );

        final payload = moshCompress(instruction.encode());
        final fragments = moshFragments(7, payload, 16);
        final assembly = MoshFragmentAssembly();

        Uint8List? assembled;
        for (final fragment in fragments) {
          assembled = assembly.add(MoshFragment.decode(fragment.encode()));
        }

        final decoded = MoshTransportInstruction.decode(
          moshDecompress(assembled!),
        );
        expect(decoded.oldNum, 2);
        expect(decoded.newNum, 3);
        expect(decoded.ackNum, 1);
        expect(decoded.diff, instruction.diff);
      },
    );
  });

  group('protobuf codecs', () {
    test('encodes and decodes transport instructions', () {
      final instruction = MoshTransportInstruction(
        oldNum: 7,
        newNum: 8,
        ackNum: 3,
        throwawayNum: 1,
        diff: [1, 2, 3],
      );

      final decoded = MoshTransportInstruction.decode(instruction.encode());

      expect(decoded.protocolVersion, moshProtocolVersion);
      expect(decoded.oldNum, 7);
      expect(decoded.newNum, 8);
      expect(decoded.ackNum, 3);
      expect(decoded.throwawayNum, 1);
      expect(decoded.diff, [1, 2, 3]);
      expect(decoded.isShutdown, isFalse);
    });

    test('detects the server shutdown sentinel state number', () {
      // new_num (field 3) carrying uint64(-1) = 0xFFFFFFFFFFFFFFFF.
      final decoded = MoshTransportInstruction.decode(
        Uint8List.fromList([0x18, ...List<int>.filled(9, 0xff), 0x01]),
      );

      expect(decoded.newNum, MoshTransportInstruction.shutdownStateNum);
      expect(decoded.isShutdown, isTrue);
    });

    test('encodes user keystrokes and resize instructions', () {
      final message = MoshUserMessage([
        MoshKeystroke([0x61]),
        MoshResize(columns: 80, rows: 24),
      ]);

      expect(message.encode(), isNotEmpty);
    });

    test('decodes host bytes from upstream protobuf shape', () {
      final hostBytes = _writer()..bytes(4, [0x68, 0x69]);
      final instruction = _writer()..bytes(2, hostBytes.takeBytes());
      final message = _writer()..bytes(1, instruction.takeBytes());

      final decoded = MoshHostMessage.decode(message.takeBytes());

      expect(decoded.hostBytes, [0x68, 0x69]);
    });

    test('decodes an echo-ack from the host message', () {
      final ack = _writer()..varint(8, 42);
      final instruction = _writer()..bytes(7, ack.takeBytes());
      final message = _writer()..bytes(1, instruction.takeBytes());

      final decoded = MoshHostMessage.decode(message.takeBytes());

      expect(decoded.echoAck, 42);
    });
  });

  group('MoshPacketCipher', () {
    test('frames packets with the 8-byte wire nonce', () {
      final cipher = MoshPacketCipher(_EchoAead());

      final packet = cipher.encrypt(
        nonce: 0x0102,
        plaintext: Uint8List.fromList([1, 2, 3]),
      );

      expect(packet.take(8), [0, 0, 0, 0, 0, 0, 1, 2]);
      expect(cipher.decrypt(packet), [1, 2, 3]);
    });

    test('uses AES-OCB for real Mosh packet encryption', () {
      final key = MoshKey.parse('AAECAwQFBgcICQoLDA0ODw');
      final cipher = MoshPacketCipher.aesOcb(key);
      final plaintext = Uint8List.fromList([1, 2, 3, 4]);

      final packet = cipher.encrypt(nonce: 7, plaintext: plaintext);

      expect(packet.take(8), [0, 0, 0, 0, 0, 0, 0, 7]);
      expect(cipher.decrypt(packet), plaintext);
    });
  });

  group('MoshSession', () {
    test('send and resize return increasing input-state numbers', () async {
      final server = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(server.close);
      final key = MoshKey.parse('AAECAwQFBgcICQoLDA0ODw');
      final session = await MoshSession.connect(
        server: MoshServerConfig(
          host: '127.0.0.1',
          port: server.port,
          key: key,
        ),
        cipher: MoshPacketCipher.aesOcb(key),
        columns: 80,
        rows: 24,
      );
      addTearDown(session.close);

      final first = session.send([0x61]);
      final second = session.send([0x62]);
      final third = session.resize(100, 40);

      expect(second, greaterThan(first));
      expect(third, greaterThan(second));
    });

    test('uses a pre-resolved address instead of resolving the host', () async {
      final server = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(server.close);
      final ports = <int>[];
      server.listen((event) {
        if (event != RawSocketEvent.read) return;
        if (server.receive() != null) ports.add(1);
      });

      final key = MoshKey.parse('AAECAwQFBgcICQoLDA0ODw');
      final session = await MoshSession.connect(
        server: MoshServerConfig(
          host: 'mosh.invalid',
          port: server.port,
          key: key,
        ),
        cipher: MoshPacketCipher.aesOcb(key),
        address: InternetAddress.loopbackIPv4,
        columns: 80,
        rows: 24,
      );
      addTearDown(session.close);

      await _settle();
      expect(ports, isNotEmpty);
    });

    test(
      'rehome rebinds to a new source port and keeps transmitting',
      () async {
        final server = await RawDatagramSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(server.close);
        final ports = <int>[];
        server.listen((event) {
          if (event != RawSocketEvent.read) return;
          final datagram = server.receive();
          if (datagram != null) ports.add(datagram.port);
        });

        final key = MoshKey.parse('AAECAwQFBgcICQoLDA0ODw');
        final session = await MoshSession.connect(
          server: MoshServerConfig(
            host: '127.0.0.1',
            port: server.port,
            key: key,
          ),
          cipher: MoshPacketCipher.aesOcb(key),
          columns: 80,
          rows: 24,
        );
        addTearDown(session.close);

        await _settle();
        final before = ports.toSet();
        expect(before, isNotEmpty);

        await session.rehome();
        await _settle();

        expect(ports.toSet().difference(before), isNotEmpty);
      },
    );

    test('completes done when the server signals shutdown', () async {
      final server = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(server.close);
      final key = MoshKey.parse('AAECAwQFBgcICQoLDA0ODw');
      final cipher = MoshPacketCipher.aesOcb(key);

      server.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = server.receive();
        if (datagram == null) return;
        server.send(
          _serverShutdownPacket(cipher),
          datagram.address,
          datagram.port,
        );
      });

      final session = await MoshSession.connect(
        server: MoshServerConfig(
          host: '127.0.0.1',
          port: server.port,
          key: key,
        ),
        cipher: cipher,
        columns: 80,
        rows: 24,
      );
      addTearDown(session.close);

      await session.done.timeout(const Duration(seconds: 2));
    });
  });

  group('AesOcb', () {
    test('matches RFC 7253 empty plaintext vector', () {
      final ocb = AesOcb(_hex('000102030405060708090A0B0C0D0E0F'));

      expect(
        _hexString(
          ocb.seal(
            nonce: _hex('BBAA99887766554433221100'),
            plaintext: Uint8List(0),
          ),
        ),
        '785407BFFFC8AD9EDCC5520AC9111EE6',
      );
    });

    test('matches RFC 7253 associated-data and partial-plaintext vector', () {
      final ocb = AesOcb(
        _hex('000102030405060708090A0B0C0D0E0F'),
        associatedData: _hex('0001020304050607'),
      );
      final ciphertext = ocb.seal(
        nonce: _hex('BBAA99887766554433221101'),
        plaintext: _hex('0001020304050607'),
      );

      expect(
        _hexString(ciphertext),
        '6820B3657B6F615A5725BDA0D3B4EB3A257C9AF1F8F03009',
      );
      expect(
        ocb.open(
          nonce: _hex('BBAA99887766554433221101'),
          ciphertextWithTag: ciphertext,
        ),
        _hex('0001020304050607'),
      );
    });

    test('matches RFC 7253 full-block vector', () {
      final ocb = AesOcb(
        _hex('000102030405060708090A0B0C0D0E0F'),
        associatedData: _hex('000102030405060708090A0B0C0D0E0F'),
      );

      expect(
        _hexString(
          ocb.seal(
            nonce: _hex('BBAA99887766554433221104'),
            plaintext: _hex('000102030405060708090A0B0C0D0E0F'),
          ),
        ),
        '571D535B60B277188BE5147170A9A22C3AD7A4FF3835B8C5701C1CCEC8FC3358',
      );
    });

    test('matches RFC 7253 96-bit tag vector', () {
      final ocb = AesOcb(
        _hex('0F0E0D0C0B0A09080706050403020100'),
        associatedData: _hex(
          '000102030405060708090A0B0C0D0E0F'
          '101112131415161718191A1B1C1D1E1F'
          '2021222324252627',
        ),
        tagLength: 12,
      );

      expect(
        _hexString(
          ocb.seal(
            nonce: _hex('BBAA9988776655443322110D'),
            plaintext: _hex(
              '000102030405060708090A0B0C0D0E0F'
              '101112131415161718191A1B1C1D1E1F'
              '2021222324252627',
            ),
          ),
        ),
        '1792A4E31E0755FB03E31B22116E6C2DDF9EFD6E33D536F1'
        'A0124B0A55BAE884ED93481529C76B6AD0C515F4D1CDD4FD'
        'AC4F02AA',
      );
    });

    test('rejects tampered ciphertext', () {
      final ocb = AesOcb(_hex('000102030405060708090A0B0C0D0E0F'));
      final ciphertext = ocb.seal(
        nonce: _hex('BBAA99887766554433221103'),
        plaintext: _hex('0001020304050607'),
      );
      ciphertext[0] ^= 1;

      expect(
        () => ocb.open(
          nonce: _hex('BBAA99887766554433221103'),
          ciphertextWithTag: ciphertext,
        ),
        throwsA(isA<MoshException>()),
      );
    });
  });
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

/// Builds an encrypted server-to-client packet carrying the Mosh shutdown
/// sentinel (a transport instruction whose new state number is `uint64(-1)`).
Uint8List _serverShutdownPacket(MoshPacketCipher cipher) {
  // Transport instruction: new_num (field 3) = 0xFFFFFFFFFFFFFFFF.
  final instruction = Uint8List.fromList([
    0x18,
    ...List<int>.filled(9, 0xff),
    0x01,
  ]);
  final fragment = moshFragments(
    0,
    moshCompress(instruction),
    moshDefaultSendMtu,
  ).first;
  final packet = MoshTransportPacket(
    timestamp: 0,
    timestampReply: MoshTransportPacket.noTimestamp,
    payload: fragment.encode(),
  );
  return cipher.encrypt(nonce: 1, plaintext: packet.encode());
}

Uint8List _hex(String hex) {
  final normalized = hex.replaceAll(RegExp(r'\s+'), '');
  final out = Uint8List(normalized.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(normalized.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _hexString(List<int> bytes) {
  return bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join();
}

_TestProtoWriter _writer() => _TestProtoWriter();

class _TestProtoWriter {
  final _bytes = BytesBuilder(copy: false);

  void bytes(int field, List<int> value) {
    _varint((field << 3) | 2);
    _varint(value.length);
    _bytes.add(value);
  }

  void varint(int field, int value) {
    _varint(field << 3);
    _varint(value);
  }

  Uint8List takeBytes() => _bytes.takeBytes();

  void _varint(int value) {
    var remaining = value;
    while (remaining >= 0x80) {
      _bytes.addByte((remaining & 0x7f) | 0x80);
      remaining >>= 7;
    }
    _bytes.addByte(remaining);
  }
}

class _EchoAead implements MoshAead {
  @override
  Uint8List open({
    required Uint8List nonce,
    required Uint8List ciphertextWithTag,
  }) {
    expect(nonce, hasLength(12));
    return ciphertextWithTag.sublist(0, ciphertextWithTag.length - 16);
  }

  @override
  Uint8List seal({required Uint8List nonce, required Uint8List plaintext}) {
    expect(nonce, hasLength(12));
    return Uint8List.fromList([...plaintext, ...List<int>.filled(16, 0xaa)]);
  }
}
