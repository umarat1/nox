import 'controller.dart';
import 'regions.dart';

/// One country in the accordion: entries grouped by protocol category.
class CountryGroup {
  /// ISO code, or [otherKey] for «Другое».
  final String key;
  final String title;
  final List<(String, List<J>)> cats;
  const CountryGroup(this.key, this.title, this.cats);
  static const otherKey = '_other';
  String? get iso => key == otherKey ? null : key;
  List<J> get all => [for (final (_, l) in cats) ...l];
  int get count => all.length;
  bool has(String id) => all.any((s) => s['id'] == id);

  /// Best (lowest) measured ping of the group, null if none measured.
  int? get bestPing {
    int? b;
    for (final s in all) {
      final p = s['ping'];
      if (p is int && p > 0 && (b == null || p < b)) b = p;
    }
    return b;
  }
}

/// «Автовыбор» items (top) + countries in subscription order, «Другое» last.
class ServerTree {
  final List<J> auto;
  final List<CountryGroup> groups;
  const ServerTree(this.auto, this.groups);
}

String _host(J s) {
  final h = '${s['host'] ?? ''}'.trim();
  if (h.isNotEmpty) return h.toLowerCase();
  final o = s['outbound'];
  return o is Map ? '${o['server'] ?? ''}'.toLowerCase() : '';
}

/// ISO from a host's first label: «tr1.sessia.top», «de-2.x.y», «in.x.y» → TR/DE/IN.
String? hostIso(String host) {
  if (host.isEmpty || RegExp(r'^[\d.:\[\]]+$').hasMatch(host)) return null;
  final m = RegExp(r'^([a-z]{2})(?:\d+|-[^.]*)?\.').firstMatch(host);
  if (m == null) return null;
  final iso = m.group(1)!.toUpperCase();
  return regionName.containsKey(iso) ? iso : null;
}

/// Protocol category inside a country: «VLESS», «AnyTLS», «Hysteria2», «VLESS IPv6», «qWDTT».
String categoryOf(J s) {
  if (NoxController.isQw(s)) return 'qWDTT';
  var c = NoxController.proto(s).trim();
  if (c.isEmpty) c = 'Другое';
  final n = '${s['name'] ?? ''}'.toLowerCase();
  final h = _host(s);
  if (n.contains('ipv6') || n.contains('ip6') || h.contains(':')) c = '$c IPv6';
  return c;
}

/// Country of a non-qWDTT server: flag/leading name, else a country word anywhere.
String? countryOf(J s) {
  final n = '${s['name'] ?? ''}';
  return region(n) ?? regionAnywhere(n);
}

/// Group [list] (display order, already filtered) into the accordion tree.
/// [order] is the subscription order (all servers) used to order countries.
ServerTree groupServers(List<J> list, {List<J>? order}) {
  final auto = <J>[];
  final key = <String, String>{}; // id → group key
  final byHost = <String, String>{};
  final rest = <J>[];
  for (final s in list) {
    if (NoxController.isBal(s)) {
      auto.add(s);
    } else {
      rest.add(s);
    }
  }
  // 1) regular servers: flag / country name
  for (final s in rest) {
    if (NoxController.isQw(s)) continue;
    final iso = countryOf(s) ?? hostIso(_host(s));
    key[s['id']] = iso ?? CountryGroup.otherKey;
    final h = _host(s);
    if (iso != null && h.isNotEmpty) byHost.putIfAbsent(h, () => iso);
  }
  // 2) qWDTT: name/flag, then same host as a known server, then host label
  for (final s in rest) {
    if (!NoxController.isQw(s)) continue;
    final h = _host(s);
    key[s['id']] =
        countryOf(s) ?? byHost[h] ?? hostIso(h) ?? CountryGroup.otherKey;
  }
  // country order: first regular entry in subscription order, qWDTT-only countries after
  final src = order ?? list;
  final idx = <String, int>{};
  for (final (i, s) in src.indexed) {
    idx.putIfAbsent('${s['id']}', () => i);
  }
  final rank = <String, int>{};
  for (final s in rest) {
    final k = key[s['id']]!;
    final i = (idx['${s['id']}'] ?? 1 << 20) + (NoxController.isQw(s) ? 1 << 24 : 0);
    if (!rank.containsKey(k) || i < rank[k]!) rank[k] = i;
  }
  final keys = rank.keys.toList()
    ..sort((a, b) {
      if (a == CountryGroup.otherKey) return 1;
      if (b == CountryGroup.otherKey) return -1;
      return rank[a]!.compareTo(rank[b]!);
    });
  final groups = <CountryGroup>[];
  for (final k in keys) {
    final members = rest.where((s) => key[s['id']] == k).toList();
    final cats = <String, List<J>>{};
    for (final s in members.where((s) => !NoxController.isQw(s))) {
      cats.putIfAbsent(categoryOf(s), () => []).add(s);
    }
    final qw = members.where(NoxController.isQw).toList();
    if (qw.isNotEmpty) cats['qWDTT'] = qw; // anti-block entries last inside the country
    groups.add(CountryGroup(k, _title(k, members), [
      for (final e in cats.entries) (e.key, e.value),
    ]));
  }
  return ServerTree(auto, groups);
}

/// «Лондон» when the hosts say so, else the table name («Турция»).
String _title(String k, List<J> members) {
  if (k == CountryGroup.otherKey) return 'Другое';
  for (final s in members.where((s) => !NoxController.isQw(s))) {
    final w = dispName('${s['name'] ?? ''}')
        .split(RegExp(r'[^\p{L}]+', unicode: true))
        .firstWhere((x) => x.isNotEmpty, orElse: () => '');
    if (w.isNotEmpty && aliasIso(w) == k) {
      return w[0].toUpperCase() + w.substring(1);
    }
  }
  return regionName[k] ?? k;
}
