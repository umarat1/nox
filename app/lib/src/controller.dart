import 'dart:async';

import 'package:flutter/widgets.dart';

import 'api.dart';
import 'live_graph.dart';
import 'platform.dart';
import 'regions.dart';
import 'tour.dart';

typedef J = Map<String, dynamic>;

/// Polls the core and exposes state + list logic (chips, dedup, hide dead, sort) to the UI.
class NoxController extends ChangeNotifier {
  final NoxApi api;
  NoxController(this.api);

  J? state;
  J? traffic;
  final speed = SpeedSeries();
  String? fatal; // core unreachable
  Set<String> pingWait = {};
  Timer? _t1, _t2;
  bool _proxyApplied = false;
  String _lastStatus = '';

  J get s => state ?? const {};
  J get settings => (s['settings'] as Map?)?.cast<String, dynamic>() ?? {};
  Map<String, String> get ui =>
      ((settings['ui'] as Map?) ?? {}).map((k, v) => MapEntry('$k', '$v'));
  List<J> get servers => ((s['servers'] as List?) ?? [])
      .cast<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList();
  List<J> get subs => ((s['subs'] as List?) ?? [])
      .cast<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList();
  String get status => (s['status'] ?? 'disconnected') as String;
  bool get connected => status == 'connected';
  bool get busy => status == 'connecting' || status == 'disconnecting';
  String get selected => (s['selected'] ?? '') as String;
  J? get current => servers.where((x) => x['id'] == selected).firstOrNull;

  /// Android TV (leanback): two-pane layout and D-pad focus hints.
  bool isTv = false;

  /// The user declined the system VPN dialog.
  bool vpnDenied = false;

  String pref(String k, String d) => ui[k] ?? d;
  bool flag(String k, bool d) => ui.containsKey(k) ? ui[k] == '1' : d;

  /// Text size 0.85–1.30 (MediaQuery textScaler).
  double get fontScale =>
      (double.tryParse(pref('fontScale', '')) ?? (isTv ? 1.1 : 1.0)).clamp(
        0.85,
        1.30,
      );

  /// Overall UI zoom 0.80–1.30 (layout size / Transform).
  double get uiScale =>
      (double.tryParse(pref('uiScale', '')) ?? (isTv ? 1.15 : 1.0)).clamp(
        0.80,
        1.30,
      );

  /// Smooth 60fps+ animations (graph ticker); off = economy (ticker still vsync but UI can skip).
  bool get animSmooth => flag('anim60', true);

  /// First-launch coach marks (shown once per [tourVersion], upgraders included).
  bool tourForce = false, tourClosed = false;
  int tourRun = 0;
  bool get tourOn =>
      state != null &&
      fatal == null &&
      !tourClosed &&
      (tourForce || pref('tourV', '') != tourVersion);
  void endTour() {
    tourClosed = true;
    tourForce = false;
    notifyListeners();
    setPref('tourV', tourVersion);
  }

  void replayTour() {
    tourClosed = false;
    tourForce = true;
    tourRun++;
    notifyListeners();
  }

  Future<void> start() async {
    isTv = await isTvDevice();
    initPairLinks();
    await requestHighRefreshRate();
    await refresh();
    // first start of 1.0 on a PC that had 0.8 / VPS: take its subscriptions
    if (fatal == null && servers.isEmpty) {
      final legacy = await readLegacyState();
      if (legacy != null && await call('ImportLegacy', [legacy]) == true) {
        await legacyImported();
        await refresh();
        call('RefreshSubs'); // fresh server lists in the 1.0 format
      }
    }
    // autostart lives in HKCU\...\Run (per user); re-assert it so a migrated 0.8
    // setting or a moved install keeps working
    if (settings['autostart'] == true) await setUserAutostart(true);
    _t1 = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
    // speed samples twice a second between full refreshes, so the graph sees each new
    // engine sample within ~250 ms on average (smoother scrolling); skipped when hidden
    _t2 = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _pollTraffic(),
    );
  }

  bool _tBusy = false;
  Future<void> _pollTraffic() async {
    if (!connected || !windowShown.value || _tBusy) return;
    _tBusy = true;
    try {
      final t = await api.call('GetTraffic');
      if (t is Map && connected) {
        traffic = t.cast<String, dynamic>();
        speed.feed(traffic);
      }
    } catch (_) {
    } finally {
      _tBusy = false;
    }
  }

  @override
  void dispose() {
    _t1?.cancel();
    _t2?.cancel();
    super.dispose();
  }

  Future<dynamic> call(String m, [List<dynamic> a = const []]) async {
    if (m == 'Connect' && settings['mode'] != 'proxy' && !await prepareVpn()) {
      fatal = null;
      vpnDenied = true;
      notifyListeners();
      return null;
    }
    if (m == 'Connect') vpnDenied = false;
    try {
      final r = await api.call(m, a);
      fatal = null;
      return r;
    } on NoxError catch (e) {
      fatal = e.message;
      notifyListeners();
      return null;
    }
  }

  Future<void> refresh() async {
    final st = await call('GetState');
    if (st is Map) {
      state = st.cast<String, dynamic>();
      if (!s['pinging']) pingWait = {};
      if (connected) {
        final t = await call('GetTraffic');
        if (t is Map) traffic = t.cast<String, dynamic>();
        speed.feed(traffic);
      } else {
        traffic = null;
        speed.reset();
      }
      await _syncDesktop();
      _maybeCaptcha();
    }
    notifyListeners();
  }

  /// Desktop: the service cannot touch the user's proxy settings; do it here.
  Future<void> _syncDesktop() async {
    if (status != _lastStatus) {
      _lastStatus = status;
      updateTray(
        connected,
        current == null ? '' : dispName(current!['name'] ?? ''),
      );
    }
    final wantProxy =
        connected &&
        settings['mode'] == 'proxy' &&
        settings['noSysProxy'] != true;
    if (wantProxy != _proxyApplied) {
      _proxyApplied = wantProxy;
      await applySystemProxy(
        wantProxy,
        (settings['proxyPort'] as int?) ?? 10808,
      );
    }
  }

  /// qWDTT asked for VK's "I'm not a robot" check: open it once per request (Android).
  J? get captcha => (s['captcha'] as Map?)?.cast<String, dynamic>();
  int _captchaShown = 0;
  bool captchaOpen = false;
  void _maybeCaptcha({bool force = false}) {
    final c = captcha;
    if (c == null || !canCaptcha || captchaOpen) return;
    final id = (c['id'] as num?)?.toInt() ?? 0;
    if (id == _captchaShown && !force)
      return; // dismissed: the banner offers it again
    // Android blocks activity starts from the background: wait until Nox is in front
    final ls = WidgetsBinding.instance.lifecycleState;
    if (ls != null && ls != AppLifecycleState.resumed) return;
    _captchaShown = id;
    captchaOpen = true;
    solveCaptcha('${c['url']}').then((r) async {
      captchaOpen = false;
      await call('SolveCaptcha', [id, r]);
      await refresh();
    });
  }

  void openCaptcha() => _maybeCaptcha(force: true);

  Future<String?> saveSettings(J patch) async {
    final n = {...settings, ...patch};
    final old = settings['autostart'] == true;
    final r = await call('SaveSettings', [n]);
    if ((n['autostart'] == true) != old)
      await setUserAutostart(n['autostart'] == true);
    await refresh();
    return (r is String && r.isNotEmpty) ? r : null;
  }

  Future<void> setPref(String k, String v) => saveSettings({
    'ui': {...ui, k: v},
  });

  /// Update a ui pref and notify immediately; persist in background (for sliders).
  void setPrefLive(String k, String v) {
    final n = {
      ...settings,
      'ui': {...ui, k: v},
    };
    if (state != null) {
      state = {...s, 'settings': n};
      notifyListeners();
    }
    call('SaveSettings', [n]);
  }

  Future<void> toggle() async {
    if (status == 'disconnected') {
      await call('Connect');
    } else {
      await call('Disconnect');
    }
    await refresh();
  }

  Future<void> select(String id) async {
    await call('Select', [id]); // reconnects by itself when the VPN is on
    await refresh();
  }

  void ping(List<String> ids) {
    pingWait = ids.isEmpty
        ? servers.map((e) => e['id'] as String).toSet()
        : ids.toSet();
    call('PingServers', [ids]);
  }

  // ------------------------------------------------------------- list logic (as Android)
  static bool isBal(J s) => s['type'] == 'Автовыбор' || s['type'] == 'Balancer';
  static bool isQw(J s) => s['type'] == 'qWDTT';
  static String proto(J s) => isBal(s)
      ? ''
      : ((s['type'] ?? '') as String).replaceFirst(RegExp(r' Reality$'), '');

  /// Chips: Все → Автовыбор → Антиблок (qWDTT) → страны → протоколы.
  List<(String key, String label, String? iso)> chips() {
    final all = servers;
    final c = <(String, String, String?)>[('', 'Все', null)];
    if (all.any(isBal)) c.add(('_auto', '⚡ Автовыбор', null));
    // Murad: only this chip is called «Антиблок»; type, badge and server names stay qWDTT
    if (all.any(isQw)) c.add(('_qw', 'Антиблок', null));
    final rg = <String>{};
    for (final s in all) {
      if (isBal(s) || isQw(s)) continue;
      final r = region(s['name'] ?? '');
      if (r != null) rg.add(r);
    }
    final rl = rg.toList()
      ..sort((a, b) => (regionName[a] ?? a).compareTo(regionName[b] ?? b));
    for (final r in rl) {
      c.add(('rg:$r', regionName[r] ?? r, r));
    }
    final pr = <String>{};
    for (final s in all) {
      if (!isBal(s) && !isQw(s)) pr.add(proto(s));
    }
    for (final p in pr) {
      c.add(('pt:$p', p, null));
    }
    return c;
  }

  String get category {
    final c = pref('cat', '');
    return chips().any((e) => e.$1 == c) ? c : '';
  }

  bool match(J s, String c) {
    if (c.isEmpty) return true;
    if (c == '_auto') return isBal(s);
    if (c == '_qw') return isQw(s);
    if (c.startsWith('rg:'))
      return !isBal(s) && region(s['name'] ?? '') == c.substring(3);
    if (c.startsWith('pt:')) return !isBal(s) && proto(s) == c.substring(3);
    return true;
  }

  /// Dedup (identical outbounds collapse) + «Скрыть нерабочие» (on by default) + sorting.
  List<J> visible() {
    final hide = flag('hideDead', true),
        dedup = flag('dedup', true),
        cat = category;
    final seen = <String>{};
    final out = <J>[];
    for (final s in servers.where((x) => match(x, cat))) {
      final sel = s['id'] == selected;
      if (!sel && !isBal(s)) {
        final ob = Map<String, dynamic>.from((s['outbound'] as Map?) ?? {})
          ..remove('tag')
          ..remove('name');
        final k = '${s['subId']}|${_canon(ob)}';
        if (dedup && seen.contains(k)) continue;
        seen.add(k);
        if (hide && s['ping'] == -1) continue;
      }
      out.add(s);
    }
    final m = (s['sort'] ?? '') as String;
    if (m.isEmpty) return out;
    int rank(J x) {
      final p = (x['ping'] ?? 0) as int;
      return p > 0
          ? p
          : p == 0
          ? 1000000
          : p == -2 || p == -3
          ? 2000000
          : 3000000;
    }

    final idx = {for (var i = 0; i < out.length; i++) out[i]['id']: i};
    out.sort((a, b) {
      if (isBal(a) != isBal(b)) return isBal(a) ? -1 : 1;
      final r = m == 'ping'
          ? rank(a) - rank(b)
          : dispName(
              a['name'] ?? '',
            ).toLowerCase().compareTo(dispName(b['name'] ?? '').toLowerCase());
      return r != 0 ? r : idx[a['id']]! - idx[b['id']]!;
    });
    return out;
  }

  static String _canon(Object? v) {
    if (v is Map) {
      final k = v.keys.map((e) => '$e').toList()..sort();
      return '{${k.map((e) => '$e:${_canon(v[e])}').join(',')}}';
    }
    if (v is List) return '[${v.map(_canon).join(',')}]';
    return '$v';
  }
}
