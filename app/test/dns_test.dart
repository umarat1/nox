import 'package:flutter_test/flutter_test.dart';
import 'package:nox/src/home.dart';

void main() {
  test('custom DNS validation', () {
    for (final ok in [
      '1.1.1.1',
      '77.88.8.8',
      'udp://9.9.9.9',
      '2606:4700::1111',
      'https://dns.adguard-dns.com/dns-query',
      'tls://dns.quad9.net',
    ]) {
      expect(validateDns(ok), isNull, reason: ok);
    }
    for (final bad in [
      '',
      '1.1.1',
      '300.1.1.1',
      'abc',
      '0.0.0.0',
      'https://',
    ]) {
      expect(validateDns(bad), isNotNull, reason: bad);
    }
  });
  test('dns labels', () {
    expect(dnsDesc({'dns': 'quad9'}), contains('9.9.9.9'));
    expect(dnsDesc({'dns': 'auto'}), startsWith('Авто'));
    expect(
      dnsDesc({'dns': 'custom', 'customDns': '10.0.0.1'}),
      'Свой: 10.0.0.1',
    );
  });
}
