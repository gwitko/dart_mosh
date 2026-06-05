import 'constants.dart';
import 'exception.dart';
import 'key.dart';

class MoshServerConfig {
  const MoshServerConfig({
    required this.host,
    required this.port,
    required this.key,
    this.rawOutput = '',
  });

  final String host;
  final int port;
  final MoshKey key;
  final String rawOutput;

  static final RegExp _connectPattern = RegExp(
    'MOSH CONNECT\\s+(\\d{1,5})\\s+([A-Za-z0-9+/]{$moshPrintableKeyLength})',
    multiLine: true,
  );

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
