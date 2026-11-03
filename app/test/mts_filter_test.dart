import 'package:flutter_test/flutter_test.dart';
import 'package:nox/src/controller.dart';

void main() {
  bool ok(String type, Map<String, dynamic> ob) =>
      NoxController.mtsAllowed({'type': type, 'outbound': ob});
  test('МТС прокси filter keeps AnyTLS, mieru, VLESS and proxies', () {
    expect(ok('VLESS Reality', {'type': 'vless'}), true);
    expect(ok('VLESS', {'type': 'vless', 'transport': {'type': 'quic'}}), false);
    expect(ok('AnyTLS', {'type': 'AnyTLS'}), true);
    expect(ok('HTTP', {'type': 'http'}), true);
    expect(ok('SOCKS5', {'type': 'socks'}), true);
    expect(ok('SOCKS5', {'type': 'socks', 'network': 'udp'}), false);
    expect(ok('Mieru', {'type': '_ext', 'kind': 'mihomo', 'cfg': {'type': 'mieru'}}), true);
    expect(ok('Naive', {'type': '_ext', 'kind': 'naive'}), true);
    expect(ok('Juicity', {'type': '_ext', 'kind': 'juicity'}), false);
    expect(ok('XHTTP', {'type': '_xray', 'xray': {'protocol': 'vless'}}), true);
    expect(ok('XHTTP', {'type': '_xray', 'xray': {'protocol': 'trojan'}}), false);
    for (final t in ['trojan', 'hysteria2', 'hysteria', 'tuic', 'wireguard', 'vmess', 'shadowsocks', 'ssh', '_qwdtt', '_sstp']) {
      expect(ok(t, {'type': t}), false, reason: t);
    }
    expect(ok('Автовыбор', {'type': '_balancer'}), true);
    expect(ok('Mieru', {}), true); // label fallback
    expect(ok('qWDTT', {}), false);
  });
}
