import 'constants.dart';
import 'exception.dart';
import 'key.dart';

/// Connection details parsed from a `MOSH CONNECT` line.
class MoshServerConfig {
  /// Creates a server configuration.
  const MoshServerConfig({
    required this.host,
    required this.port,
    required this.key,
    this.rawOutput = '',
  });

  /// Hostname or IP address of the server.
  final String host;

  /// UDP port printed by `mosh-server`.
  final int port;

  /// Session key printed by `mosh-server`.
  final MoshKey key;

  /// Full raw bootstrap output used to create this config.
  final String rawOutput;

  static final RegExp _connectPattern = RegExp(
    'MOSH CONNECT\\s+(\\d{1,5})\\s+([A-Za-z0-9+/]{$moshPrintableKeyLength})',
    multiLine: true,
  );

  /// Parses `mosh-server` startup output.
  factory MoshServerConfig.parse(String output, {required String host}) {
    final match = _connectPattern.firstMatch(output);
    if (match == null) {
      throw MoshException(
        'Could not find a MOSH CONNECT line in mosh-server output.',
        output,
      );
    }

    final port = int.parse(match.group(_portGroup)!);
    if (port < moshUdpMinPort || port > moshUdpMaxPort) {
      throw MoshException('mosh-server returned an invalid UDP port: $port.');
    }

    return MoshServerConfig(
      host: host,
      port: port,
      key: MoshKey.parse(match.group(_keyGroup)!),
      rawOutput: output,
    );
  }
}

const int _portGroup = 1;
const int _keyGroup = 2;
