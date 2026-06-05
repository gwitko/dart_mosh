# dart_mosh

Dart building blocks for talking to `mosh-server`.

This package handles the Mosh UDP side: keys, nonces, AES-OCB packets,
fragmentation, compression, protobuf messages, acks, retransmits, resize, and
basic session rehoming.

It does not open SSH connections or provide a terminal UI. Your app starts
`mosh-server`, parses its `MOSH CONNECT` line, then passes the result here.

```dart
final output = await ssh.run(MoshSshBootstrap().command());
final server = MoshServerConfig.parse(output, host: 'example.com');

final session = await MoshSession.connect(
  server: server,
  cipher: MoshPacketCipher.aesOcb(server.key),
  columns: 120,
  rows: 40,
);

session.stdout.listen(terminal.writeBytes);
await session.send(utf8.encode('ls\r'));
```

Used by Conduit for Mosh transport.
