import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'constants.dart';
import 'crypto/aead.dart';
import 'exception.dart';
import 'nonce.dart';
import 'protocol/compression.dart';
import 'protocol/fragment.dart';
import 'protocol/messages.dart';
import 'protocol/packet.dart';
import 'protocol/replay.dart';
import 'protocol/rtt.dart';
import 'protocol/transport.dart';
import 'server_config.dart';

/// UDP Mosh session for terminal input, output, acknowledgements, and rehoming.
class MoshSession {
  MoshSession._({
    required RawDatagramSocket socket,
    required InternetAddress remoteAddress,
    required int remotePort,
    required MoshCipher cipher,
    required int sendMtu,
    required Duration ackInterval,
    int? columns,
    int? rows,
  }) : _socket = socket,
       _remoteAddress = remoteAddress,
       _remotePort = remotePort,
       _cipher = cipher,
       _sendMtu = sendMtu,
       _ackInterval = ackInterval.inMilliseconds {
    _socketSub = _socket.listen(_handleSocketEvent, onError: _stderr.add);
    if (columns != null && rows != null) {
      _pending.add(MoshResize(columns: columns, rows: rows));
    }
    _transmit(_clock.elapsedMilliseconds);
    _scheduleNext();
  }

  static const int _ackDelay = 100;

  RawDatagramSocket _socket;
  final InternetAddress _remoteAddress;
  final int _remotePort;
  final MoshCipher _cipher;
  final int _sendMtu;
  final int _ackInterval;
  final _stdout = StreamController<List<int>>.broadcast();
  final _stderr = StreamController<Object>.broadcast();
  final _echoAcks = StreamController<int>.broadcast();
  final _done = Completer<void>();
  final _assembly = MoshFragmentAssembly();
  final _replay = MoshReplayFilter();
  final _rtt = MoshRttEstimator();
  final _pending = <MoshClientInstruction>[];
  final _clock = Stopwatch()..start();
  final _random = Random.secure();
  late StreamSubscription<RawSocketEvent> _socketSub;
  Timer? _timer;
  var _closed = false;
  var _rehoming = false;
  var _sendSeq = 0;
  var _fragmentId = 0;
  var _assumedAckNum = 0;
  var _serverAckedNum = 0;
  var _receivedStateNum = 0;
  var _lastSentNum = 0;
  var _lastSendTime = 0;
  var _peerTimestamp = MoshTransportPacket.noTimestamp;
  var _peerTimestampAt = 0;
  var _ackDeadline = -1;

  /// Stream of host output bytes.
  Stream<List<int>> get stdout => _stdout.stream;

  /// Stream of non-fatal socket, parse, and crypto errors.
  Stream<Object> get errors => _stderr.stream;

  /// Stream of echo acknowledgement numbers from the server.
  Stream<int> get echoAcks => _echoAcks.stream;

  /// Completes when the session is closed.
  Future<void> get done => _done.future;

  /// Current smoothed round-trip time, if a sample has been received.
  Duration? get smoothedRtt => _rtt.hasSample
      ? Duration(microseconds: (_rtt.srtt * 1000).round())
      : null;

  /// Opens a UDP session to [server].
  static Future<MoshSession> connect({
    required MoshServerConfig server,
    required MoshCipher cipher,
    InternetAddress? address,
    int? columns,
    int? rows,
    InternetAddress? localAddress,
    int localPort = 0,
    int sendMtu = moshDefaultSendMtu,
    Duration ackInterval = const Duration(seconds: 3),
  }) async {
    final remote = address ?? (await InternetAddress.lookup(server.host)).first;
    final bindAddress =
        localAddress ??
        (remote.type == InternetAddressType.IPv6
            ? InternetAddress.anyIPv6
            : InternetAddress.anyIPv4);
    final socket = await RawDatagramSocket.bind(bindAddress, localPort);
    return MoshSession._(
      socket: socket,
      remoteAddress: remote,
      remotePort: server.port,
      cipher: cipher,
      sendMtu: sendMtu,
      ackInterval: ackInterval,
      columns: columns,
      rows: rows,
    );
  }

  /// Queues terminal input bytes and returns the resulting input state number.
  int send(List<int> data) {
    if (data.isEmpty) return _assumedAckNum + _pending.length;
    _pending.add(MoshKeystroke(List<int>.of(data)));
    _pump();
    return _assumedAckNum + _pending.length;
  }

  /// Queues a terminal resize and returns the resulting input state number.
  int resize(int columns, int rows) {
    _pending.add(MoshResize(columns: columns, rows: rows));
    _pump();
    return _assumedAckNum + _pending.length;
  }

  /// Rebinds the local UDP socket while keeping the Mosh session state.
  Future<void> rehome({
    InternetAddress? localAddress,
    int localPort = 0,
  }) async {
    if (_closed) {
      throw const MoshException('The Mosh session is closed.');
    }
    if (_rehoming) return;
    _rehoming = true;
    try {
      final bindAddress =
          localAddress ??
          (_remoteAddress.type == InternetAddressType.IPv6
              ? InternetAddress.anyIPv6
              : InternetAddress.anyIPv4);
      final socket = await RawDatagramSocket.bind(bindAddress, localPort);
      if (_closed) {
        socket.close();
        return;
      }
      await _socketSub.cancel();
      _socket.close();
      _socket = socket;
      _socketSub = _socket.listen(_handleSocketEvent, onError: _stderr.add);
      _transmit(_clock.elapsedMilliseconds);
      _scheduleNext();
    } finally {
      _rehoming = false;
    }
  }

  /// Closes the UDP socket and all streams.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    await _socketSub.cancel();
    _socket.close();
    await _stdout.close();
    await _stderr.close();
    await _echoAcks.close();
    if (!_done.isCompleted) _done.complete();
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _closed) return;

    Datagram? datagram;
    while ((datagram = _socket.receive()) != null) {
      try {
        _handleDatagram(datagram!.data);
      } catch (error) {
        _stderr.add(error);
      }
    }
    _pump();
  }

  void _handleDatagram(Uint8List data) {
    final plaintext = _cipher.decrypt(data);
    if (!_replay.accept(
      MoshNonce.fromWire(data.sublist(0, moshWireNonceLength)).sequence,
    )) {
      return;
    }

    final packet = MoshTransportPacket.decode(plaintext);
    _peerTimestamp = packet.timestamp;
    _peerTimestampAt = _clock.elapsedMilliseconds;
    if (packet.timestampReply != MoshTransportPacket.noTimestamp) {
      final now16 = _clock.elapsedMilliseconds & _timestampMask;
      _rtt.sample((now16 - packet.timestampReply) & _timestampMask);
    }

    final assembled = _assembly.add(MoshFragment.decode(packet.payload));
    if (assembled == null) return;

    final transport = MoshTransportInstruction.decode(
      moshDecompress(assembled),
    );
    if (transport.protocolVersion != moshProtocolVersion) {
      throw MoshException(
        'Unsupported Mosh protocol version: ${transport.protocolVersion}.',
      );
    }

    if (transport.ackNum > _serverAckedNum) {
      _serverAckedNum = transport.ackNum;
      while (_pending.isNotEmpty && _assumedAckNum < _serverAckedNum) {
        _pending.removeAt(0);
        _assumedAckNum++;
      }
    }

    if (transport.newNum > _receivedStateNum &&
        transport.oldNum == _receivedStateNum) {
      if (transport.diff.isNotEmpty) {
        final host = MoshHostMessage.decode(transport.diff);
        if (host.hostBytes.isNotEmpty) {
          _stdout.add(Uint8List.fromList(host.hostBytes));
        }
        if (host.echoAck != null) {
          _echoAcks.add(host.echoAck!);
        }
      }
      _receivedStateNum = transport.newNum;
      if (_ackDeadline < 0) {
        _ackDeadline = _clock.elapsedMilliseconds + _ackDelay;
      }
    }
  }

  void _pump() {
    if (_closed || _timer == null) return;
    final now = _clock.elapsedMilliseconds;
    if (_shouldSend(now)) {
      _transmit(now);
    }
    _scheduleNext();
  }

  bool _shouldSend(int now) {
    final currentNum = _assumedAckNum + _pending.length;
    if (currentNum > _lastSentNum && now >= _lastSendTime + _rtt.sendInterval) {
      return true;
    }
    if (_pending.isNotEmpty && now >= _lastSendTime + _rtt.rto) {
      return true;
    }
    if (_ackDeadline >= 0 && now >= _ackDeadline) {
      return true;
    }
    return now >= _lastSendTime + _ackInterval;
  }

  void _scheduleNext() {
    if (_closed) return;
    final now = _clock.elapsedMilliseconds;
    final currentNum = _assumedAckNum + _pending.length;
    var next = _lastSendTime + _ackInterval;
    if (currentNum > _lastSentNum) {
      next = min(next, _lastSendTime + _rtt.sendInterval);
    }
    if (_pending.isNotEmpty) {
      next = min(next, _lastSendTime + _rtt.rto);
    }
    if (_ackDeadline >= 0) {
      next = min(next, _ackDeadline);
    }

    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: max(0, next - now)), _pump);
  }

  void _transmit(int now) {
    if (_closed) {
      throw const MoshException('The Mosh session is closed.');
    }

    final oldNum = _assumedAckNum;
    final newNum = _assumedAckNum + _pending.length;
    final diff = _pending.isEmpty
        ? const <int>[]
        : MoshUserMessage(List<MoshClientInstruction>.of(_pending)).encode();

    final instruction = MoshTransportInstruction(
      oldNum: oldNum,
      newNum: newNum,
      ackNum: _receivedStateNum,
      throwawayNum: oldNum,
      diff: diff,
      chaff: _chaff(),
    );

    final payload = moshCompress(instruction.encode());
    final timestampReply = _replyTimestamp(now);
    for (final fragment in moshFragments(_fragmentId++, payload, _sendMtu)) {
      final transport = MoshTransportPacket(
        timestamp: now & _timestampMask,
        timestampReply: timestampReply,
        payload: fragment.encode(),
      );
      final packet = _cipher.encrypt(
        nonce: _sendSeq++,
        plaintext: transport.encode(),
      );
      _socket.send(packet, _remoteAddress, _remotePort);
    }

    _lastSentNum = newNum;
    _lastSendTime = now;
    _ackDeadline = -1;
  }

  List<int> _chaff() {
    final length = _random.nextInt(_maxChaffLength + 1);
    return List<int>.generate(length, (_) => _random.nextInt(moshByteModulus));
  }

  int _replyTimestamp(int now) {
    if (_peerTimestamp == MoshTransportPacket.noTimestamp) {
      return MoshTransportPacket.noTimestamp;
    }
    final age = now - _peerTimestampAt;
    if (age < 0 || age >= _maxTimestampReplyAgeMs) {
      return MoshTransportPacket.noTimestamp;
    }
    return (_peerTimestamp + age) & _timestampMask;
  }
}

const int _timestampMask = MoshTransportPacket.noTimestamp;
const int _maxChaffLength = 16;
const int _maxTimestampReplyAgeMs = 1000;
