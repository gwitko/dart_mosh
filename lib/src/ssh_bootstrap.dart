import 'constants.dart';
import 'exception.dart';

class MoshSshBootstrap {
  const MoshSshBootstrap({
    this.serverBinary = 'mosh-server',
    this.locale = 'en_US.UTF-8',
    this.term = 'xterm-256color',
    this.colors = moshDefaultColors,
    this.serverPort = moshDefaultServerPort,
    this.serverPortEnd = moshMaxServerPort,
    this.udpBindIp,
  });

  final String serverBinary;
  final String locale;
  final String term;
  final int colors;
  final int serverPort;
  final int serverPortEnd;
  final String? udpBindIp;

  String command() {
    _checkPort(serverPort);
    _checkPort(serverPortEnd);
    if (serverPortEnd < serverPort) {
      throw const MoshException(
        'serverPortEnd must be greater than or equal to serverPort.',
      );
    }

    final args = <String>[
      _shellQuote(serverBinary),
      'new',
      '-s',
      '-c',
      '$colors',
      '-l',
      _shellQuote(locale),
      '-p',
      serverPort == serverPortEnd
          ? '$serverPort'
          : '$serverPort:$serverPortEnd',
    ];

    final bindIp = udpBindIp;
    if (bindIp != null && bindIp.isNotEmpty) {
      args
        ..add('-i')
        ..add(_shellQuote(bindIp));
    }

    return 'TERM=${_shellQuote(term)} LC_ALL=${_shellQuote(locale)} ${args.join(' ')}';
  }

  static void _checkPort(int port) {
    if (port < moshUdpMinPort || port > moshUdpMaxPort) {
      throw MoshException('Invalid UDP port: $port.');
    }
  }

  static String _shellQuote(String value) {
    if (RegExp(r'^[A-Za-z0-9_./:=+-]+$').hasMatch(value)) {
      return value;
    }
    return "'${value.replaceAll("'", r"'\''")}'";
  }
}
