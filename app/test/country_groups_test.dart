import 'package:flutter_test/flutter_test.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/country_groups.dart';
import 'package:nox/src/regions.dart';

import 'sample_servers.dart';

void main() {
  String sum(ServerTree t) => [
    for (final g in t.groups)
      '${g.key}:${g.title}[${[for (final (c, l) in g.cats) '$c=${l.map((s) => s['id']).join('+')}'].join(' ')}]',
  ].join(' | ');

  test('countries in subscription order, protocols inside, qWDTT mapped', () {
    final all = sampleServers();
    final t = groupServers(all, order: all);
    expect(t.auto.map((s) => s['id']), ['a']);
    expect(
      sum(t),
      'TR:Турция[VLESS=t1 AnyTLS=t2 Hysteria2=t3 VLESS IPv6=t4 qWDTT=q1+q2] | '
      'IN:Индия[XHTTP=i1 TUIC=i2 Mieru=i3 qWDTT=q3] | '
      'GB:Лондон[Naive=l1 Trojan=l2] | '
      'JP:Япония[VLESS=j1] | '
      'FR:Франция[Hysteria2=f1] | '
      '_other:Другое[qWDTT=q4]',
    );
    final tr = t.groups.first;
    expect(tr.count, 6);
    expect(tr.bestPing, 59);
    expect(tr.has('q2'), true);
  });

  test('display order (ping sort) does not reorder countries', () {
    final all = sampleServers();
    final sorted = [...all]..sort((a, b) => (a['ping'] as int).compareTo(b['ping'] as int));
    final t = groupServers(sorted, order: all);
    expect(t.groups.map((g) => g.key).toList(), ['TR', 'IN', 'GB', 'JP', 'FR', '_other']);
  });

  test('МТС прокси filter: hidden protocols gone, empty countries dropped', () {
    final all = sampleServers();
    final vis = all.where(NoxController.mtsAllowed).toList();
    final t = groupServers(vis, order: all);
    expect(t.auto.length, 1);
    expect(
      sum(t),
      'TR:Турция[VLESS=t1 AnyTLS=t2 VLESS IPv6=t4] | IN:Индия[XHTTP=i1 Mieru=i3] | '
      'GB:Лондон[Naive=l1] | JP:Япония[VLESS=j1]',
    );
  });

  test('no flag: leading name, country word, host label, else Другое', () {
    final l = [
      sv('x1', 'Индия ipv6 vless', 'VLESS', {'type': 'vless'}),
      sv('x2', 'Server NL 2', 'VLESS', {'type': 'vless'}, host: 'nl2.host.io'),
      sv('x3', 'резерв германия', 'VLESS', {'type': 'vless'}),
      sv('x4', 'mystery', 'VLESS', {'type': 'vless'}, host: '1.2.3.4'),
    ];
    final t = groupServers(l);
    expect(sum(t), 'IN:Индия[VLESS IPv6=x1] | NL:Нидерланды[VLESS=x2] | DE:Германия[VLESS=x3] | _other:Другое[VLESS=x4]');
  });

  test('row names inside a country drop the flag and country word', () {
    expect(shortName('🇹🇷 Турция vless tcp tls 443'), 'vless tcp tls 443');
    expect(shortName('🇬🇧 Лондон naive 443'), 'Лондон naive 443'.substring(7));
    expect(shortName('qWDTT Турция 1'), 'qWDTT Турция 1');
    expect(shortName('🇮🇳 Индия'), 'Индия');
  });
}
