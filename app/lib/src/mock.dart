import 'dart:math';

import 'api.dart';

/// In-memory demo core: web preview, screenshots and widget tests (`--dart-define=NOX_MOCK=true`).
class MockApi implements NoxApi {
  final _rnd = Random(7);
  String status = const String.fromEnvironment(
    'NOX_MOCK_STATUS',
    defaultValue: 'connected',
  );
  String selected = 'b';
  String sort = const String.fromEnvironment('NOX_MOCK_SORT');
  late Map<String, dynamic> settings = {
    'mode': 'tun',
    'dns': 'cloudflare',
    'directRu': true,
    'pingMode': 'url',
    'autoSwitch': true,
    'theme': const String.fromEnvironment(
      'NOX_MOCK_THEME',
      defaultValue: 'dark',
    ),
    'proxyPort': 2080,
    'ui': {
      'view': const String.fromEnvironment(
        'NOX_MOCK_VIEW',
        defaultValue: 'list',
      ),
      'hideDead': const String.fromEnvironment(
        'NOX_MOCK_HIDE',
        defaultValue: '1',
      ),
    },
  };
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  late final List<Map<String, dynamic>> subs = [
    {
      'id': 's1',
      'name': 'iji.by · Мурад',
      'upload': 3.2e9.toInt(),
      'download': 21e9.toInt(),
      'total': 100e9.toInt(),
      'expire': now + 86400 * 23,
      'updated': now - 1500,
      'webPage': 'https://canada2.iji.by',
      'support': 'https://t.me/myvps05_bot',
      'announce': 'Новые серверы: SSTP — Лондон, США, Канада',
    },
  ];
  Map<String, dynamic> _s(
    String id,
    String name,
    String type,
    int ping,
    String host,
    int port,
  ) => {
    'id': id,
    'name': name,
    'type': type,
    'ping': ping,
    'host': host,
    'port': port,
    'subId': 's1',
    'outbound': {'type': type, 'server': host, 'p': id},
  };
  late final List<Map<String, dynamic>> servers = [
    _s('a', 'Автовыбор', 'Автовыбор', 84, '', 0),
    _s('b', '🇬🇧 Лондон 1', 'VLESS Reality', 62, '31.76.249.120', 443),
    _s('c', '🇬🇧 Лондон 2', 'VLESS', 71, '31.76.249.120', 8443),
    _s('d', '🇹🇷 Турция 1', 'VLESS', -1, '107.161.174.157', 443),
    _s('e', '🇺🇸 США', 'Trojan', 148, 'usa5.iji.by', 443),
    _s('f', '🇬🇧 Лондон qWDTT', 'qWDTT', 210, 'x', 56000),
    _s('g', '🇨🇦 Канада Hysteria2', 'Hysteria2', -2, 'canew.iji.by', 443),
    _s('h', '🇩🇪 Германия', 'Shadowsocks', 97, 'de.iji.by', 8388),
    _s('i', '🇨🇦 Канада SSTP', 'SSTP', 95, 'canew.iji.by', 14443),
    _s('j', '🇺🇸 США SSTP', 'SSTP', 131, 'usa5.iji.by', 14443),
  ];
  final since = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 754;

  @override
  String get transport => 'демо-режим';

  @override
  Future<dynamic> call(String m, [List<dynamic> a = const []]) async {
    switch (m) {
      case 'GetState':
        return {
          'version': '1.0.8',
          'core': 'sing-box 1.14.3 · Xray 26.3.27 · qWDTT 1.4.4 · SSTP',
          'status': status,
          'error': '',
          'notice': '',
          'pinging': false,
          'pingDone': 0,
          'pingAll': 0,
          'since': status == 'connected' ? since : 0,
          'selected': selected,
          'sort': sort,
          'settings': settings,
          'subs': subs,
          'servers': servers,
          'canUndo': 0,
          'os': 'windows',
          'update': const bool.fromEnvironment('NOX_MOCK_UPDATE')
              ? {'versionName': '1.0.1', 'notes': 'Исправления подключения'}
              : null,
        };
      case 'GetTraffic':
        // one sample per second, like the engine; values follow a smooth-ish pattern
        final seq = DateTime.now().millisecondsSinceEpoch ~/ 1000 - since + 1;
        int dn(int k) =>
            ((sin(k / 6) + 1.25) * 1.1e6 + sin(k / 2.3) * 2.5e5).toInt();
        int up(int k) => ((cos(k / 9) + 1.4) * 1.3e5).toInt();
        final n = min(120, seq);
        return {
          'Down': dn(seq - 1),
          'Up': up(seq - 1),
          'DownTotal': 1.7e9.toInt(),
          'UpTotal': 2.1e8.toInt(),
          'Seq': seq,
          'Hist': List.generate(n, (i) {
            final k = seq - n + i;
            return [up(k), dn(k)];
          }),
        };
      case 'Select':
        selected = a[0];
      case 'Connect':
        status = 'connected';
      case 'Disconnect':
        status = 'disconnected';
      case 'SaveSettings':
        settings = Map<String, dynamic>.from(a[0]);
        return '';
      case 'SetSort':
        sort = a[0];
      case 'PingServers':
        for (final s in servers) {
          if ((s['ping'] as int) > 0) s['ping'] = 40 + _rnd.nextInt(200);
        }
      case 'BestServer':
        return 'b';
      case 'Import':
        return {
          'added': 0,
          'errors': [],
          'msg': 'Демо-режим: импорт недоступен',
        };
      case 'CheckUpdateMsg':
        return 'У вас последняя версия';
      case 'GetLog':
        return '19:33:01 подключено: 🇬🇧 Лондон 1';
      case 'DeleteDead':
        return 0;
    }
    return null;
  }
}
