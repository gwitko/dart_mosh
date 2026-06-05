import 'constants.dart';
import 'exception.dart';

/// Builds the SSH command used to start `mosh-server`.
class MoshSshBootstrap {
  /// Creates a bootstrap command builder.
  const MoshSshBootstrap({
    this.serverBinary = 'mosh-server',
    this.locale = 'en_US.UTF-8',
    this.term = 'xterm-256color',
    this.colors = moshDefaultColors,
    this.serverPort = moshDefaultServerPort,
    this.serverPortEnd = moshMaxServerPort,
    this.udpBindIp,
  });

  /// Remote executable name or path.
  final String serverBinary;

  /// Locale passed to `mosh-server`.
  final String locale;

  /// Terminal type passed through the SSH environment.
  final String term;

  /// Terminal color count passed with `-c`.
  final int colors;

  /// First UDP port to request from `mosh-server`.
  final int serverPort;

  /// Last UDP port to request from `mosh-server`.
  final int serverPortEnd;

  /// Optional UDP bind address passed with `-i`.
  final String? udpBindIp;

  /// Returns a shell-safe `mosh-server new` command.
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
