import 'dart:convert';

import 'package:dart_mosh/dart_mosh.dart';

Future<void> main() async {
  final bootstrap = MoshSshBootstrap(locale: 'C.UTF-8', term: 'xterm-256color');

  print('Run over SSH: ${bootstrap.command()}');

  const output = 'MOSH CONNECT 60001 AAECAwQFBgcICQoLDA0ODw';
  final server = MoshServerConfig.parse(output, host: 'example.com');

  final session = await MoshSession.connect(
    server: server,
    cipher: MoshPacketCipher.aesOcb(server.key),
    columns: 120,
    rows: 40,
  );

  session.stdout.listen((bytes) {
    print(utf8.decode(bytes, allowMalformed: true));
  });

  session.send(utf8.encode('echo hello from mosh\r'));
  await session.close();
}
