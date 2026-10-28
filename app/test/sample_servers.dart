// Sample subscription hosts (TR1-style names) for the accordion tests and screenshot.
Map<String, dynamic> sv(
  String id,
  String name,
  String type,
  Map<String, dynamic> ob, {
  int ping = 0,
  String host = '',
}) => {
  'id': id,
  'subId': 's1',
  'name': name,
  'type': type,
  'host': host,
  'port': 443,
  'ping': ping,
  'outbound': {...ob, 'server': host},
};

List<Map<String, dynamic>> sampleServers() => [
  sv('a', 'Автовыбор', 'Автовыбор', {'type': '_balancer'}, ping: 58),
  sv('t1', '🇹🇷 Турция vless tcp tls 443', 'VLESS Reality', {'type': 'vless'}, ping: 61, host: 'tr1.sessia.top'),
  sv('t2', '🇹🇷 Турция anytls 8443', 'AnyTLS', {'type': 'anytls'}, ping: 64, host: 'tr1.sessia.top'),
  sv('t3', '🇹🇷 Турция hysteria2 udp 443', 'Hysteria2', {'type': 'hysteria2'}, ping: 59, host: 'tr1.sessia.top'),
  sv('t4', '🇹🇷 Турция vless ipv6', 'VLESS', {'type': 'vless'}, ping: 70, host: '2a12:5940::1'),
  sv('i1', '🇮🇳 Индия vless xhttp 443', 'XHTTP', {'type': '_xray', 'xray': {'protocol': 'vless'}}, ping: 142, host: 'in.sessia.top'),
  sv('i2', '🇮🇳 Индия tuic 8443', 'TUIC', {'type': 'tuic'}, ping: 150, host: 'in.sessia.top'),
  sv('i3', '🇮🇳 Индия mieru 2999', 'Mieru', {'type': '_ext', 'kind': 'mihomo', 'cfg': {'type': 'mieru'}}, ping: 155, host: 'in.sessia.top'),
  sv('l1', '🇬🇧 Лондон naive 443', 'Naive', {'type': '_ext', 'kind': 'naive'}, ping: 48, host: 'uk.example.net'),
  sv('l2', '🇬🇧 Лондон trojan 443', 'Trojan', {'type': 'trojan'}, ping: 50, host: 'uk.example.net'),
  sv('j1', '🇯🇵 Япония vless reality', 'VLESS Reality', {'type': 'vless'}, ping: 210, host: 'jp.example.net'),
  sv('f1', '🇫🇷 Франция hysteria2', 'Hysteria2', {'type': 'hysteria2'}, ping: 75, host: 'fr.example.net'),
  // anti-block entries, named differently
  sv('q1', 'qWDTT Турция 1', 'qWDTT', {'type': '_qwdtt'}, ping: -3, host: 'vk-relay'),
  sv('q2', 'Антиблок 2', 'qWDTT', {'type': '_qwdtt'}, ping: -3, host: 'tr1.sessia.top'),
  sv('q3', 'wdtt-in-3', 'qWDTT', {'type': '_qwdtt'}, ping: -3, host: 'in2.sessia.top'),
  sv('q4', 'qwdtt резерв', 'qWDTT', {'type': '_qwdtt'}, ping: -3, host: '10.0.0.7'),
];
