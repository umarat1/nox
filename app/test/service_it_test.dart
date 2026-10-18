// Integration: the Dart client against a real noxd (go/build/noxd run). Skipped if not running.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox/src/platform_io.dart';

void main() {
  final has = File(ServiceApi.ipcPath()).existsSync();
  test('ServiceApi talks to noxd', () async {
    final api = ServiceApi();
    final st = await api.call('GetState') as Map;
    expect(st['version'], '1.0.1');
    final r =
        await api.call('Import', [
              'sstp://u:p@vpn.example.com:14443#%F0%9F%87%A8%F0%9F%87%A6%20SSTP',
            ])
            as Map;
    expect(r['added'], greaterThanOrEqualTo(0));
    final st2 = await api.call('GetState') as Map;
    expect((st2['servers'] as List).any((s) => s['type'] == 'SSTP'), isTrue);
  }, skip: has ? false : 'noxd not running');
}
