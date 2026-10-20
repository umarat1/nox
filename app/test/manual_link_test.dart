import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/src/home.dart';

void main() {
  test('manual links for every protocol', () {
    final v = {'name': 'Мой', 'host': '1.2.3.4', 'port': '443', 'user': 'u', 'pass': 'p@ss', 'uuid': '8c6fffb3-c3e8-460e-9d80-000000000000',
      'security': 'tls', 'type': 'ws', 'path': '/x', 'sni': 'a.com', 'method': 'aes-128-gcm', 'priv': 'cHJpdg==', 'pub': 'cHVi', 'addr': '10.0.0.2/32',
      'psk': 'k', 'cc': 'bbr', 'proto': 'TCP', 'mux': 'MULTIPLEXING_LOW', 'ver': '4', 'obfs': 'none', 'alpn': 'h3', 'fp': 'chrome'};
    final out = [for (final p in manualProtocols) manualLink(p, v)];
    File('/tmp/manual_links.txt').writeAsStringSync(out.join('\n'));
    expect(out.every((l) => l.contains('://')), isTrue);
  });
}
