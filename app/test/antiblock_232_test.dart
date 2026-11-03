// 2.3.2: «Антиблок» (2.3.4: «Анти БПЛА», only qWDTT) and «МТС» buttons on the connect card, subscription filter,
// links row in Настройки, slider bar never covers the last row, speed graph fold.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/home.dart';
import 'package:nox/src/mock.dart';
import 'package:nox/src/pair.dart';
import 'package:nox/src/tour.dart';
import 'package:nox/src/platform.dart'
    show canInstallApks, debugAndroidOverride;
import 'package:nox/src/update_ui.dart';

import 'real_servers.dart';
import 'ui_util.dart';

class _Tolerant extends LocalFileComparator {
  _Tolerant(super.testFile);
  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final r = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    return r.passed || r.diffPercent < 0.5;
  }
}

List<Map<String, dynamic>> _panel() => [
  for (final (i, (n, ty)) in [
    ('🇫🇮 Финляндия qwdtt', 'qWDTT'),
    ('🇫🇮 Финляндия vless reality', 'VLESS'),
    ('🇩🇪 Германия qwdtt', 'qWDTT'),
    ('🇩🇪 Германия hysteria2', 'Hysteria2'),
    ('🇳🇱 Нидерланды vless xhttp', 'VLESS XHTTP'),
  ].indexed)
    {
      'id': 'x$i',
      'subId': 's2',
      'name': n,
      'type': ty,
      'host': 'x$i.example',
      'port': 443,
      'ping': 40 + i * 7,
      'outbound': {'type': 'vless', 'server': 'x$i.example'},
    },
];

Future<(NoxController, MockApi)> _app(
  WidgetTester t,
  String theme,
  String tpl, {
  Size size = const Size(411, 860),
  double font = 1,
  Map<String, String> ui = const {},
  MockApi? mock,
}) async {
  t.view.physicalSize = size * 2.625;
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  noTopBar = true;
  addTearDown(() => noTopBar = false);
  NoxController.forceAccordion = true;
  phoneTab.value = 0;
  srvQuery.value = '';
  final api = mock ?? MockApi();
  api.settings['theme'] = theme;
  api.settings['ui'] = {
    ...?(api.settings['ui'] as Map?)?.cast<String, String>(),
    'homeTpl': tpl,
    if (font != 1) 'fontScale': '$font',
    if (font != 1) 'uiScale': '$font',
    ...ui,
  };
  api.status = 'connected';
  api.subs.add({
    ...api.subs.first,
    'id': 's2',
    'name': 'X panel · umarat',
    'announce': null,
  });
  api.subs.first['name'] = 'Серверная';
  api.servers
    ..clear()
    ..addAll(realServers())
    ..addAll(_panel());
  api.selected = 'm3';
  final c = NoxController(api);
  await c.refresh();
  PairGlue.suggested = true;
  await t.pumpWidget(NoxApp(c: c));
  await _settle(t);
  return (c, api);
}

Future<void> _settle(WidgetTester t, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _shot(WidgetTester t, String name) =>
    expectLater(find.byType(NoxApp), matchesGoldenFile('shots/232-$name.png'));

/// RefreshSub waits on a gate so the spinner can be observed; answers ok or error.
class _GateApi extends MockApi {
  final calls = <List<dynamic>>[];
  Completer<dynamic> gate = Completer();
  @override
  Future<dynamic> call(String m, [List<dynamic> a = const []]) async {
    if (m == 'RefreshSub') {
      calls.add(a);
      return gate.future;
    }
    return super.call(m, a);
  }
}

/// An app update is available (as the engine reports it after latest.json).
class _UpdApi extends MockApi {
  final calls = <String>[];
  @override
  Future<dynamic> call(String m, [List<dynamic> a = const []]) async {
    calls.add(m);
    final r = await super.call(m, a);
    if (m == 'GetState' && r is Map) {
      return {
        ...r,
        'update': {'versionName': '2.3.3', 'notes': 'Исправления'},
      };
    }
    return r;
  }
}

/// Android engine with an update job: [job] is what GetState reports as updJob.
class _AutoApi extends MockApi {
  final calls = <String>[];
  Map<String, dynamic>? job;
  bool offer = true;
  _AutoApi(this.job);
  @override
  Future<dynamic> call(String m, [List<dynamic> a = const []]) async {
    calls.add(m);
    if (m == 'UpdateStart') {
      job = {...?job, 'active': true, 'stage': 'install'};
      return job;
    }
    if (m == 'UpdateProgress') return job ?? {'stage': '', 'total': -1};
    final r = await super.call(m, a);
    if (m == 'GetState' && r is Map) {
      return {
        ...r,
        'os': 'android',
        'update': offer
            ? {'versionName': '2.3.3', 'notes': 'Исправления'}
            : null,
        'updJob': job,
      };
    }
    return r;
  }
}

Map<String, dynamic> _dl(int pct) => {
  'active': true,
  'stage': 'download',
  'version': '2.3.3',
  'done': pct,
  'total': 100,
  'speed': 0,
  'auto': true,
  'ready': false,
  'error': '',
};

const _ready = {
  'active': false,
  'stage': 'ready',
  'version': '2.3.3',
  'done': 100,
  'total': 100,
  'speed': 0,
  'auto': true,
  'ready': true,
  'error': '',
};

void main() {
  goldenFileComparator = _Tolerant(
    (goldenFileComparator as LocalFileComparator).basedir.resolve(
      'antiblock_232_test.dart',
    ),
  );
  setUpAll(() async {
    await loadFonts();
    const cyr =
        '/usr/share/fonts/truetype/sand-box/google/Roboto/Roboto-VariableFont_wdth,wght.ttf';
    if (File(cyr).existsSync()) {
      for (final fam in ['Segoe UI', 'Roboto']) {
        await (FontLoader(fam)..addFont(
              Future.value(ByteData.view(File(cyr).readAsBytesSync().buffer)),
            ))
            .load();
      }
    }
  });

  for (final theme in ['dark', 'light']) {
    for (final tpl in ['button', 'slider']) {
      testWidgets('Антиблок + МТС on the card — $theme $tpl', (t) async {
        final (c, api) = await _app(t, theme, tpl);
        expect(find.byKey(const Key('hero-antiblock')), findsOneWidget);
        expect(find.byKey(const Key('hero-mts')), findsOneWidget);
        // subscription «Серверная» (index 0) selected by default: 69 servers
        expect(find.text('Все · 69'), findsOneWidget);
        await _shot(t, 'main-$theme-$tpl-off');
        await t.tap(find.byKey(const Key('hero-antiblock')));
        await _settle(t);
        expect(c.ui['antiblock'], '1');
        expect(
          (api.settings['ui'] as Map)['antiblock'],
          '1',
          reason: 'persisted',
        );
        final qw = phoneFilter(c, c.visible());
        expect(qw.every(NoxController.isQw), isTrue);
        expect(find.text('Все · ${qw.length}'), findsOneWidget);
        await _shot(t, 'main-$theme-$tpl-anti');
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('МТС button = old МТС action', (t) async {
    final (c, _) = await _app(t, 'dark', 'button');
    await t.tap(find.byKey(const Key('hero-mts')));
    await _settle(t);
    // mtsOn is Android-only; the saved setting is what the old button changed
    expect(c.settings['mtsProxy'], isTrue);
    t.takeException();
  });

  // 2.3.3: on Android the МТС button really toggles МТС mode (button state, filtered list
  // incl. AnyTLS) right away, even while the reconnect is still running.
  testWidgets('2.3.3 МТС button toggles МТС mode on Android, AnyTLS kept', (
    t,
  ) async {
    debugAndroidOverride = true;
    addTearDown(() => debugAndroidOverride = null);
    final (c, api) = await _app(t, 'dark', 'button');
    // real protocol per label (the shared mock fixtures all carry a vless outbound)
    const ob = {
      'vless': 'vless',
      'hysteria2': 'hysteria2',
      'trojan': 'trojan',
      'anytls': 'anytls',
      'tuic': 'tuic',
      'naive': 'naive',
      'mieru': '_ext',
      'qwdtt': '_qwdtt',
    };
    for (final x in api.servers) {
      final k = '${x['type']}'.toLowerCase().split(' ').first;
      x['outbound'] = k == 'mieru'
          ? {'type': '_ext', 'kind': 'mieru'}
          : {'type': ob[k] ?? 'vless'};
    }
    await c.refresh();
    await _settle(t);
    expect(c.mtsOn, isFalse);
    final before = c.servers.length;
    await t.tap(find.byKey(const Key('hero-mts')));
    await t.pump();
    expect(c.mtsOn, isTrue, reason: 'flips immediately on tap');
    await _settle(t);
    expect(api.settings['mtsProxy'], isTrue, reason: 'saved in the engine');
    expect(c.mtsOn, isTrue);
    final vis = c.servers;
    expect(vis.length, lessThan(before), reason: 'non-TCP protocols hidden');
    expect(vis.every(NoxController.mtsAllowed), isTrue);
    String ty(J x) =>
        '${(x['outbound'] as Map?)?['type'] ?? ''} ${x['type']}'.toLowerCase();
    expect(
      vis.any((x) => ty(x).contains('anytls')),
      isTrue,
      reason: 'AnyTLS stays in МТС mode',
    );
    expect(vis.any((x) => ty(x).contains('hysteria')), isFalse);
    expect(
      find.byTooltip('МТС прокси: вкл'),
      findsOneWidget,
      reason: 'button shows ON',
    );
    // dialogs/toasts from the toggle
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      await t.tap(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextButton),
            )
            .first,
      );
      await _settle(t);
    }
    await t.tap(find.byKey(const Key('hero-mts')));
    await t.pump();
    expect(c.mtsOn, isFalse);
    await _settle(t);
    expect(api.settings['mtsProxy'], isFalse);
    expect(c.servers.length, before);
    expect(find.byTooltip('МТС прокси: выкл'), findsOneWidget);
    t.takeException();
  });

  test('2.3.3 mtsAllowed: AnyTLS in every outbound shape', () {
    expect(
      NoxController.mtsAllowed({
        'type': 'AnyTLS',
        'outbound': {'type': 'anytls'},
      }),
      isTrue,
    );
    expect(
      NoxController.mtsAllowed({
        'type': 'AnyTLS',
        'outbound': {
          'type': '_ext',
          'kind': 'mihomo',
          'cfg': {'type': 'anytls'},
        },
      }),
      isTrue,
    );
    expect(
      NoxController.mtsAllowed({
        'type': 'AnyTLS',
        'outbound': {'type': '_x'},
      }),
      isTrue,
    );
    expect(
      NoxController.mtsAllowed({
        'type': 'Hysteria2',
        'outbound': {'type': 'hysteria2'},
      }),
      isFalse,
    );
  });

  // 2.3.3: real names/protocols from his subscriptions (X panel umarat + Серверная sub.txt)
  List<Map<String, dynamic>> realMts() => [
    for (final (i, (n, ty, ob, ping))
        in <(String, String, Map<String, dynamic>, int)>[
          (
            '🇫🇮 Финляндия · VLESS Reality',
            'VLESS Reality',
            {'type': 'vless'},
            180,
          ),
          (
            '🇫🇮 Финляндия · Shadowsocks',
            'Shadowsocks',
            {'type': 'shadowsocks'},
            20,
          ),
          (
            '🇫🇮 Финляндия · Hysteria 2',
            'Hysteria2',
            {'type': 'hysteria2'},
            15,
          ),
          ('🇫🇮 Финляндия · TUIC v5', 'TUIC', {'type': 'tuic'}, 16),
          ('🇫🇮 Финляндия · AnyTLS', 'AnyTLS', {'type': 'anytls'}, 95),
          (
            '🇫🇮 Финляндия · NaïveProxy',
            'Naive',
            {
              'type': '_ext',
              'kind': 'naive',
              'cfg': {'scheme': 'https'},
            },
            70,
          ),
          (
            '🇫🇮 Финляндия · HTTP/3 (Naïve QUIC)',
            'Naive',
            {
              'type': '_ext',
              'kind': 'naive',
              'cfg': {'scheme': 'quic'},
            },
            10,
          ),
          (
            '🇫🇮 Финляндия · mieru',
            'Mieru',
            {
              'type': '_ext',
              'kind': 'mihomo',
              'cfg': {'type': 'mieru', 'transport': 'TCP'},
            },
            60,
          ),
          (
            '🇫🇮 Финляндия · Juicity',
            'Juicity',
            {'type': '_ext', 'kind': 'juicity', 'cfg': {}},
            12,
          ),
          ('🇹🇷 Турция vless grpc tls', 'VLESS gRPC', {'type': 'vless'}, 0),
          ('🇹🇷 Турция anytls', 'AnyTLS', {'type': 'anytls'}, 140),
          (
            '🇮🇳 Индия naiveproxy',
            'Naive',
            {
              'type': '_ext',
              'kind': 'naive',
              'cfg': {'scheme': 'https'},
            },
            0,
          ),
          (
            '🇬🇧 Лондон mieru',
            'Mieru',
            {
              'type': '_ext',
              'kind': 'mihomo',
              'cfg': {'type': 'mieru', 'transport': 'TCP'},
            },
            55,
          ),
          ('🇨🇭 Швейцария vless tcp tls 443', 'VLESS', {'type': 'vless'}, 120),
          ('🇫🇮 Финляндия qwdtt', 'qWDTT', {'type': '_qwdtt'}, 30),
        ].indexed)
      {
        'id': 'r$i',
        'subId': 's2',
        'name': n,
        'type': ty,
        'host': 'r$i.example',
        'port': 443,
        'ping': ping,
        'outbound': {...ob, 'server': 'r$i.example'},
      },
  ];

  testWidgets(
    '2.3.3 МТС: list/Серверы/chips only МТС servers, fastest picked, exclusive with Антиблок',
    (t) async {
      debugAndroidOverride = true;
      addTearDown(() => debugAndroidOverride = null);
      // subscription «X panel» picked in the switcher + МТС + Антиблок combined
      final (c, api) = await _app(t, 'dark', 'slider', ui: {'subIdx': '1'});
      api.servers
        ..clear()
        ..addAll(realMts())
        ..addAll([
          for (final x in realServers().take(5))
            {...x, 'subId': api.subs.first['id']},
        ]);
      api.selected = 'r2'; // Hysteria 2: hidden by МТС
      await c.refresh();
      await _settle(t);
      final all =
          realMts().length; // the other subscription's 5 are filtered out
      expect(find.text('Все · $all'), findsOneWidget);
      await t.tap(find.byKey(const Key('hero-mts')));
      await _settle(t, 20);
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        await t.tap(
          find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(TextButton),
              )
              .first,
        );
        await _settle(t);
      }
      expect(c.mtsOn, isTrue);
      final names = phoneFilter(c, c.visible()).map((x) => x['name']).toSet();
      expect(names, {
        '🇫🇮 Финляндия · VLESS Reality',
        '🇫🇮 Финляндия · AnyTLS',
        '🇫🇮 Финляндия · NaïveProxy',
        '🇫🇮 Финляндия · mieru',
        '🇹🇷 Турция vless grpc tls',
        '🇹🇷 Турция anytls',
        '🇮🇳 Индия naiveproxy',
        '🇬🇧 Лондон mieru',
        '🇨🇭 Швейцария vless tcp tls 443',
      }, reason: 'SS/Hy2/TUIC/Naive QUIC/Juicity/qWDTT hidden');
      expect(
        find.text('Все · ${names.length}'),
        findsOneWidget,
        reason: 'chip count = МТС list',
      );
      expect(
        api.selected,
        'r12',
        reason: 'fastest МТС server (Лондон mieru, 55 ms)',
      );
      expect(find.byTooltip('МТС прокси: вкл'), findsOneWidget);
      await _shot(t, 'mts-on-dark');
      for (final n in [
        'Финляндия · Shadowsocks',
        'Финляндия · Hysteria 2',
        'Финляндия qwdtt',
      ]) {
        expect(find.text(n), findsNothing, reason: n);
      }
      phoneTab.value = 1;
      await _settle(t);
      expect(
        find.text('Все · ${names.length}'),
        findsOneWidget,
        reason: 'Серверы tab',
      );
      expect(find.text('Финляндия · Shadowsocks'), findsNothing);
      phoneTab.value = 0;
      await _settle(t);
      // Антиблок on → МТС off (qWDTT cannot go through МТС; together the list was empty)
      await t.tap(find.byKey(const Key('hero-antiblock')));
      await _settle(t, 20);
      expect(c.mtsOn, isFalse);
      expect(c.ui['antiblock'], '1');
      // МТС on → Антиблок off
      await t.tap(find.byKey(const Key('hero-mts')));
      await _settle(t, 20);
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        await t.tap(
          find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(TextButton),
              )
              .first,
        );
        await _settle(t);
      }
      expect(c.mtsOn, isTrue);
      expect(c.ui['antiblock'], '0');
      t.takeException();
    },
  );

  test('2.3.3 mtsAllowed: Naive/mieru TCP yes, Naive QUIC / mieru UDP no', () {
    J s(Map<String, dynamic> ob) => {'type': 'x', 'outbound': ob};
    expect(
      NoxController.mtsAllowed(
        s({
          'type': '_ext',
          'kind': 'naive',
          'cfg': {'scheme': 'https'},
        }),
      ),
      isTrue,
    );
    expect(
      NoxController.mtsAllowed(
        s({
          'type': '_ext',
          'kind': 'naive',
          'cfg': {'scheme': 'quic'},
        }),
      ),
      isFalse,
    );
    expect(
      NoxController.mtsAllowed(
        s({
          'type': '_ext',
          'kind': 'mihomo',
          'cfg': {'type': 'mieru', 'transport': 'TCP'},
        }),
      ),
      isTrue,
    );
    expect(
      NoxController.mtsAllowed(
        s({
          'type': '_ext',
          'kind': 'mihomo',
          'cfg': {'type': 'mieru', 'transport': 'UDP'},
        }),
      ),
      isFalse,
    );
    expect(
      NoxController.mtsAllowed(
        s({'type': '_ext', 'kind': 'juicity', 'cfg': {}}),
      ),
      isFalse,
    );
  });

  for (final w in [360.0, 412.0]) {
    for (final theme in ['dark', 'light']) {
      testWidgets(
        '2.3.3 full server names, end ellipsis — $theme ${w.toInt()} px',
        (t) async {
          final (c, api) = await _app(
            t,
            theme,
            'slider',
            size: Size(w, 800),
            ui: {'subIdx': '1'},
          );
          api.servers
            ..clear()
            ..addAll(realMts());
          api.selected = 'r9';
          await c.refresh();
          await _settle(t);
          // only the leading flag goes (it is the avatar); the country word stays
          final vert = find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          );
          for (final n in [
            'Финляндия · AnyTLS',
            'Турция vless grpc tls',
            'Лондон mieru',
            'Швейцария vless tcp tls 443',
          ]) {
            for (var k = 0; k < 30 && find.text(n).evaluate().isEmpty; k++) {
              await t.drag(vert.first, const Offset(0, -120));
              await t.pump(const Duration(milliseconds: 60));
            }
            expect(find.text(n), findsWidgets, reason: n);
          }
          expect(
            find.text('vless grpc tls'),
            findsNothing,
            reason: 'start of the name must not be cut',
          );
          expect(find.text('· AnyTLS'), findsNothing);
          await _shot(t, 'names-list-$theme-${w.toInt()}');
          for (final x in t.widgetList<Text>(
            find.text('Швейцария vless tcp tls 443'),
          )) {
            expect(
              x.overflow,
              TextOverflow.ellipsis,
              reason: 'cut at the end only',
            );
            expect(x.maxLines, 1);
          }
          phoneTab.value = 1;
          await _settle(t);
          expect(
            find.text('Турция vless grpc tls'),
            findsWidgets,
            reason: 'Серверы tab',
          );
          await _shot(t, 'names-$theme-${w.toInt()}');
          expect(t.takeException(), isNull, reason: 'no overflow');
          // debug-only semantics-geometry assert of the framework after a drag + tab switch
        },
        semanticsEnabled: false,
      );
    }
  }

  testWidgets('subscription filter + Антиблок empty state + Серверы', (
    t,
  ) async {
    final (c, api) = await _app(t, 'dark', 'slider');
    await t.tap(find.textContaining('X panel').first);
    await _settle(t);
    expect((api.settings['ui'] as Map)['subIdx'], '1');
    // 5 panel servers + the current row from «Серверная»
    expect(find.text('Все · 6'), findsOneWidget);
    await _shot(t, 'sub-filter-dark');
    await t.tap(find.byKey(const Key('hero-antiblock')));
    await _settle(t);
    expect(find.text('Все · 2'), findsOneWidget);
    await _shot(t, 'sub-anti-dark');
    // Серверы tab: same filter, same switcher
    phoneTab.value = 1;
    await _settle(t);
    expect(find.text('Все · 2'), findsOneWidget);
    await _shot(t, 'servers-sub-anti-dark');
    // nothing matches: real empty text + button that turns Антиблок off
    api.servers.removeWhere((s) => s['subId'] == 's2' && s['type'] == 'qWDTT');
    await c.refresh();
    await _settle(t);
    expect(find.textContaining('Нет серверов qWDTT'), findsOneWidget);
    await _shot(t, 'empty-dark');
    await t.tap(find.byKey(const Key('antiblock-off')));
    await _settle(t);
    expect(c.ui['antiblock'], '0');
    t.takeException();
  });

  testWidgets('graph fold persisted', (t) async {
    for (final tpl in ['button', 'slider']) {
      final (c, api) = await _app(t, 'dark', tpl);
      expect(find.byKey(const Key('hero-graph')), findsOneWidget);
      await _shot(t, 'graph-$tpl-open');
      await t.tap(find.byKey(const Key('hero-graph-toggle')));
      await _settle(t);
      expect(find.byKey(const Key('hero-graph')), findsNothing);
      expect((api.settings['ui'] as Map)['heroGraphOff'], '1');
      await _shot(t, 'graph-$tpl-closed');
      expect(c.flag('heroGraphOff', false), isTrue);
      expect(t.takeException(), isNull);
    }
  });

  for (final theme in ['dark', 'light']) {
    testWidgets('Настройки links row — $theme', (t) async {
      await _app(t, theme, 'button');
      await t.tap(find.byKey(TourKeys.settings));
      await _settle(t);
      for (final l in [
        'Поддержка',
        'sessia.top',
        'etv24.ru',
        'iji.by',
        'Донат',
      ]) {
        expect(find.byKey(Key('link-$l')), findsOneWidget, reason: l);
      }
      expect(find.text('Ссылки'), findsNothing);
      // let the logo asset decode before the shot
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 400)));
      await _settle(t);
      await _shot(t, 'settings-links-$theme');
      await t.drag(
        find.byKey(const Key('settings-links')),
        const Offset(-400, 0),
      );
      await _settle(t);
      await _shot(t, 'settings-links-$theme-end');
      expect(t.takeException(), isNull);
    });
  }

  for (final tpl in ['button', 'slider']) {
    testWidgets('360 px, 1.3× font: no overlap/overflow — $tpl', (t) async {
      await _app(
        t,
        'dark',
        tpl,
        size: const Size(360, 760),
        font: 1.3,
        ui: const {'antiblock': '1'},
      );
      expect(t.takeException(), isNull);
      final a = t.getRect(find.byKey(const Key('hero-antiblock')));
      final m = t.getRect(find.byKey(const Key('hero-mts')));
      final pill = t.getRect(find.byKey(const Key('status-pill')));
      expect(a.overlaps(pill), isFalse);
      expect(m.overlaps(pill), isFalse);
      // subscription row: switcher, ↻ and ⋯ fit inside the card
      final rb = t.getRect(find.byKey(const Key('sub-refresh-s1')));
      final db = t.getRect(find.byTooltip('Действия с подпиской').first);
      // labels don't fit at 1.3× → the switcher scrolls instead of «Се…»
      final segF = find.byKey(const Key('sub-seg-scroll'));
      expect(segF, findsOneWidget);
      final seg = t.getRect(segF);
      expect(rb.right, lessThanOrEqualTo(db.left));
      expect(seg.right, lessThanOrEqualTo(rb.left));
      expect(db.right, lessThanOrEqualTo(360));
      expect(
        find.textContaining('Серверная', findRichText: true),
        findsWidgets,
      );
      await _shot(t, 'small-$tpl');
      // the second subscription is reachable: scroll the switcher and pick it
      await t.drag(segF, const Offset(-300, 0));
      await _settle(t);
      await _shot(t, 'small-seg-scrolled-$tpl');
      await t.tap(find.textContaining('X panel', findRichText: true).first);
      await _settle(t);
      expect(find.byKey(const Key('sub-refresh-s2')), findsOneWidget);
      expect(t.takeException(), isNull);
      await _shot(t, 'small-sub2-$tpl');
      await t.tap(find.byKey(TourKeys.settings));
      await _settle(t);
      expect(t.takeException(), isNull);
      await _shot(t, 'small-settings-$tpl');
    });
  }

  for (final theme in ['dark', 'light']) {
    testWidgets('sub card ↻: refreshes selected sub, spins, toasts — $theme', (
      t,
    ) async {
      final api = _GateApi();
      await _app(t, theme, 'button', mock: api);
      // pick the second subscription, ↻ must refresh exactly that one
      await t.tap(find.textContaining('X panel').first);
      await _settle(t);
      final btn = find.byKey(const Key('sub-refresh-s2'));
      expect(btn, findsOneWidget);
      final dots = t.getRect(find.byTooltip('Действия с подпиской').first);
      final r = t.getRect(btn);
      expect(r.size, dots.size, reason: 'same size as ⋯');
      expect(r.right, lessThanOrEqualTo(dots.left));
      await t.tap(btn);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(api.calls.single, ['s2']);
      final rt = t.widget<RotationTransition>(
        find.descendant(of: btn, matching: find.byType(RotationTransition)),
      );
      expect(rt.turns.value, greaterThan(0), reason: 'spinning');
      await _shot(t, 'sub-refresh-busy-$theme');
      // a second tap while busy does nothing
      await t.tap(btn);
      await t.pump(const Duration(milliseconds: 100));
      expect(api.calls.length, 1);
      api.gate.complete(true);
      await _settle(t);
      expect(find.text('Обновлено'), findsOneWidget);
      await _shot(t, 'sub-refresh-ok-$theme');
      // error path
      ScaffoldMessenger.of(t.element(btn)).hideCurrentSnackBar();
      await _settle(t);
      api.gate = Completer();
      await t.tap(btn);
      await t.pump(const Duration(milliseconds: 200));
      api.gate.complete('Подписка недоступна: 403');
      await _settle(t);
      expect(find.text('Подписка недоступна: 403'), findsOneWidget);
      expect(api.calls.length, 2);
      // ⋯ menu still has «Обновить»
      await t.tap(find.byTooltip('Действия с подпиской').first);
      await _settle(t, 15);
      expect(find.textContaining('Обновить'), findsWidgets);
      expect(t.takeException(), isNull);
    });
  }

  for (final theme in ['dark', 'light']) {
    for (final tpl in ['button', 'slider']) {
      testWidgets('«Обновить до» pill above the status — $theme $tpl', (
        t,
      ) async {
        resetUpdateOffers();
        final api = _UpdApi();
        await _app(t, theme, tpl, mock: api);
        // the launch offer dialog (existing behaviour) — dismiss it
        final later = find.descendant(
          of: find.byType(UpdateOfferDialog),
          matching: find.text('Позже'),
        );
        if (later.evaluate().isNotEmpty) {
          await t.tap(later);
          await _settle(t);
        }
        final pill = find.byKey(const Key('hero-update'));
        expect(pill, findsOneWidget);
        expect(find.text('Обновить до 2.3.3'), findsOneWidget);
        final r = t.getRect(pill);
        final st = t.getRect(find.byKey(const Key('status-pill')));
        expect(r.bottom, lessThanOrEqualTo(st.top), reason: 'above the status');
        for (final k in ['hero-antiblock', 'hero-mts', 'hero-graph']) {
          expect(r.overlaps(t.getRect(find.byKey(Key(k)))), isFalse, reason: k);
        }
        await _shot(t, 'update-$theme-$tpl');
        await t.tap(pill);
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byType(UpdateDialog), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('«Обновить до»: 360 px, 1.3× — no collisions', (t) async {
    for (final tpl in ['button', 'slider']) {
      resetUpdateOffers();
      await _app(
        t,
        'dark',
        tpl,
        size: const Size(360, 760),
        font: 1.3,
        mock: _UpdApi(),
        ui: const {'antiblock': '1'},
      );
      final later = find.descendant(
        of: find.byType(UpdateOfferDialog),
        matching: find.text('Позже'),
      );
      if (later.evaluate().isNotEmpty) {
        await t.tap(later);
        await _settle(t);
      }
      expect(t.takeException(), isNull);
      final r = t.getRect(find.byKey(const Key('hero-update')));
      for (final k in [
        'hero-antiblock',
        'hero-mts',
        'hero-graph',
        'status-pill',
      ]) {
        expect(r.overlaps(t.getRect(find.byKey(Key(k)))), isFalse, reason: k);
      }
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(360));
      await _shot(t, 'update-small-$tpl');
      await t.drag(find.byType(Scrollable).first, const Offset(0, -330));
      await _settle(t);
      await _shot(t, 'update-small-banner-$tpl');
    }
  });

  // ------------------------------------------------ 2.3.2 auto-download
  for (final (theme, tpl) in [('dark', 'button'), ('light', 'slider')]) {
    testWidgets('auto-download: «Скачивание 42%» → «Установить» — $theme $tpl', (
      t,
    ) async {
      resetUpdateOffers();
      final api = _AutoApi(_dl(42));
      final (c, _) = await _app(t, theme, tpl, mock: api);
      // auto-download on (default «Всегда»): no launch offer dialog
      expect(find.byType(UpdateOfferDialog), findsNothing);
      expect(find.text('Скачивание 42%'), findsOneWidget);
      expect(find.byKey(const Key('hero-update-progress')), findsOneWidget);
      final r = t.getRect(find.byKey(const Key('hero-update')));
      for (final k in [
        'hero-antiblock',
        'hero-mts',
        'hero-graph',
        'status-pill',
      ]) {
        expect(r.overlaps(t.getRect(find.byKey(Key(k)))), isFalse, reason: k);
      }
      await _shot(t, 'autodl-progress-$theme-$tpl');
      // ready: the installer opens by itself, once per version per launch
      api.job = {..._ready};
      await c.refresh();
      await _settle(t);
      expect(find.byType(UpdateDialog), findsOneWidget);
      expect(api.calls.where((m) => m == 'UpdateStart').length, 1);
      // the user dismissed it: the pill offers «Установить 2.3.3», no second auto prompt
      Navigator.of(t.element(find.byType(UpdateDialog))).pop();
      api.job = {..._ready};
      await c.refresh();
      await _settle(t);
      await c.refresh();
      await _settle(t);
      expect(find.byType(UpdateDialog), findsNothing);
      expect(api.calls.where((m) => m == 'UpdateStart').length, 1);
      expect(find.text('Установить 2.3.3'), findsOneWidget);
      await _shot(t, 'autodl-ready-$theme-$tpl');
      await t.tap(find.byKey(const Key('hero-update')));
      await _settle(t);
      expect(find.byType(UpdateDialog), findsOneWidget);
      expect(api.calls.where((m) => m == 'UpdateStart').length, 2);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('auto-download: 360 px, 1.3× progress / ready pills', (t) async {
    for (final tpl in ['button', 'slider']) {
      resetUpdateOffers();
      canInstallApksProbe = () async => false; // keep the auto prompt away
      addTearDown(() => canInstallApksProbe = canInstallApks);
      final api = _AutoApi(_dl(42));
      final (c, _) = await _app(
        t,
        'dark',
        tpl,
        size: const Size(360, 760),
        font: 1.3,
        mock: api,
        ui: const {'antiblock': '1', 'unkAsked': '1'},
      );
      for (final (label, shot) in [
        ('Скачивание 42%', 'progress'),
        ('Установить 2.3.3', 'ready'),
      ]) {
        if (shot == 'ready') {
          api.job = {..._ready};
          await c.refresh();
          await _settle(t);
        }
        expect(find.text(label), findsOneWidget);
        expect(find.byType(UnknownSourcesDialog), findsNothing);
        final r = t.getRect(find.byKey(const Key('hero-update')));
        for (final k in [
          'hero-antiblock',
          'hero-mts',
          'hero-graph',
          'status-pill',
        ]) {
          expect(r.overlaps(t.getRect(find.byKey(Key(k)))), isFalse, reason: k);
        }
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(360));
        await _shot(t, 'autodl-small-$shot-$tpl');
      }
      expect(t.takeException(), isNull);
    }
  });

  testWidgets('auto-download: no install permission → explanation once', (
    t,
  ) async {
    resetUpdateOffers();
    canInstallApksProbe = () async => false;
    addTearDown(() => canInstallApksProbe = canInstallApks);
    final api = _AutoApi({..._ready});
    final (c, _) = await _app(t, 'dark', 'button', mock: api);
    expect(find.byType(UnknownSourcesDialog), findsOneWidget);
    expect(find.text('Разрешите установку обновлений'), findsOneWidget);
    await _shot(t, 'autodl-permission-dark');
    expect(c.flag('unkAsked', false), isTrue);
    await t.tap(find.text('Позже'));
    await _settle(t);
    expect(find.byType(UpdateDialog), findsNothing);
    // never again by itself (even on the next launch: persisted)…
    resetUpdateOffers();
    await c.refresh();
    await _settle(t);
    expect(find.byType(UnknownSourcesDialog), findsNothing);
    // …but the pill asks again, and «Открыть настройки» goes on to the installer step
    await t.tap(find.byKey(const Key('hero-update')));
    await _settle(t);
    expect(find.byType(UnknownSourcesDialog), findsOneWidget);
    await t.tap(find.byKey(const Key('unk-open')));
    await _settle(t);
    expect(find.byType(UpdateDialog), findsOneWidget);
    expect(api.calls.where((m) => m == 'UpdateStart').length, 1);
  });

  testWidgets('«Автоскачивание обновлений»: Всегда by default, 3 options', (
    t,
  ) async {
    resetUpdateOffers();
    final api = _AutoApi(null)..offer = false;
    final (c, _) = await _app(t, 'dark', 'button', mock: api);
    await t.tap(find.byKey(TourKeys.settings));
    await _settle(t);
    final item = find.text('Автоскачивание обновлений');
    await t.scrollUntilVisible(
      item,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await _settle(t);
    expect(find.text('Всегда'), findsOneWidget);
    await _shot(t, 'autodl-setting-dark');
    await t.tap(item);
    await _settle(t);
    for (final o in ['Всегда', 'Только Wi‑Fi', 'Выкл']) {
      expect(find.text(o), findsWidgets, reason: o);
    }
    await _shot(t, 'autodl-setting-sheet-dark');
    await t.tap(find.text('Только Wi‑Fi'));
    await _settle(t);
    expect(c.settings['autoDl'], 'wifi');
    expect(api.settings['autoDl'], 'wifi');
  });

  testWidgets('auto-download «Выкл»: launch offer as before', (t) async {
    resetUpdateOffers();
    final api = _AutoApi(null);
    api.settings['autoDl'] = 'off';
    await _app(t, 'dark', 'button', mock: api);
    expect(find.byType(UpdateOfferDialog), findsOneWidget);
  });

  // ------------------------------------------------ 2.3.2 hotspot sharing
  for (final (theme, size, font) in [
    ('dark', const Size(412, 915), 1.0),
    ('light', const Size(360, 760), 1.3),
  ]) {
    testWidgets(
      '«Раздача через точку доступа»: off → on, address + copy — $theme ${size.width.toInt()}/$font',
      (t) async {
        resetUpdateOffers();
        final api = _AutoApi(null)..offer = false;
        api.settings['proxyPort'] =
            10808; // engine default (core.DefaultSettings)
        final (c, _) = await _app(
          t,
          theme,
          'button',
          mock: api,
          size: size,
          font: font,
        );
        expect(c.settings['allowLan'], isNot(true)); // off by default
        await t.tap(find.byKey(TourKeys.settings));
        await _settle(t);
        final tile = find.byKey(const Key('hotspot-share'));
        await t.scrollUntilVisible(
          tile,
          300,
          scrollable: find.byType(Scrollable).last,
        );
        await _settle(t);
        expect(find.text('Раздача через точку доступа'), findsOneWidget);
        expect(find.byKey(const Key('hotspot-addr')), findsNothing);
        await t.tap(find.text('Раздача через точку доступа'));
        await _settle(t);
        expect(api.settings['allowLan'], isTrue);
        expect(
          t.widget<Text>(find.byKey(const Key('hotspot-addr'))).data,
          '192.168.127.211:10808',
        );
        expect(
          find.text('Укажите на устройстве: Wi‑Fi → Прокси → Вручную'),
          findsOneWidget,
        );
        await Scrollable.ensureVisible(
          t.element(find.byKey(const Key('hotspot-share'))),
          alignment: .3,
        );
        await _settle(t);
        String? clip;
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (m) async {
            if (m.method == 'Clipboard.setData')
              clip = (m.arguments as Map)['text'] as String?;
            return null;
          },
        );
        await t.tap(find.byKey(const Key('hotspot-copy')));
        await _settle(t);
        expect(clip, '192.168.127.211:10808');
        await t.pump(const Duration(seconds: 3));
        await _settle(t);
        await _shot(t, 'hotspot-$theme-${size.width.toInt()}');
        expect(t.takeException(), isNull);
        if (theme != 'dark') return;
        // login/password: generated, saved, shown on the tile
        await t.tap(find.byKey(const Key('hotspot-auth')));
        await _settle(t);
        expect(find.text('Раздача через точку доступа'), findsWidgets);
        await t.tap(find.byKey(const Key('share-gen')));
        await _settle(t);
        await _shot(t, 'hotspot-auth-dark');
        await t.tap(find.text('Готово'));
        await _settle(t);
        final u = '${api.settings['shareUser']}';
        expect(u, matches(RegExp(r'^pp[a-z2-9]{4}$')));
        expect('${api.settings['sharePass']}'.length, 12);
        expect(find.text('Логин: $u ›'), findsOneWidget);
        // off again: the address row goes away
        await t.tap(find.text('Раздача через точку доступа'));
        await _settle(t);
        expect(api.settings['allowLan'], isFalse);
        expect(find.byKey(const Key('hotspot-addr')), findsNothing);
      },
    );
  }

  testWidgets('no update → no pill', (t) async {
    await _app(t, 'dark', 'button');
    expect(find.byKey(const Key('hero-update')), findsNothing);
  });

  testWidgets('slider: last row scrolls fully above the bar and the nav', (
    t,
  ) async {
    await _app(t, 'dark', 'slider');
    await t.fling(find.byType(Scrollable).first, const Offset(0, -20000), 8000);
    await _settle(t, 30);
    final dock = t.getRect(find.byKey(const Key('slider-dock')));
    final end = t.getRect(find.byKey(const Key('list-end')));
    expect(end.top, lessThanOrEqualTo(dock.top), reason: '$end vs $dock');
    await _shot(t, 'slider-end-dark');
  });

  // 2.3.4: «Анти БПЛА» caption under the shield; same toggle, renamed texts.
  for (final theme in ['dark', 'light']) {
    for (final w in [360.0, 412.0]) {
      testWidgets('2.3.4 «Анти БПЛА» caption — $theme ${w.toInt()} px', (
        t,
      ) async {
        final (c, _) = await _app(t, theme, 'button', size: Size(w, 800));
        final cap = find.byKey(const Key('hero-antiblock-caption'));
        expect(cap, findsOneWidget);
        expect(find.text('Анти БПЛА'), findsWidgets);
        expect(find.textContaining('Антиблок'), findsNothing);
        final b = t.getRect(find.byKey(const Key('hero-antiblock')));
        final r = t.getRect(cap);
        final pill = t.getRect(find.byKey(const Key('status-pill')));
        final m = t.getRect(find.byKey(const Key('hero-mts')));
        expect(r.top, greaterThanOrEqualTo(b.bottom));
        expect((r.center.dx - b.center.dx).abs(), lessThan(1));
        expect(r.left, greaterThan(0));
        expect(r.overlaps(pill), isFalse);
        expect(b.overlaps(pill), isFalse);
        expect(
          (m.top - b.top).abs(),
          lessThan(0.5),
          reason: 'МТС on the shield line',
        );
        await expectLater(
          find.byType(NoxApp),
          matchesGoldenFile('shots/234-main-$theme-${w.toInt()}-off.png'),
        );
        await t.tap(find.byKey(const Key('hero-antiblock')));
        await _settle(t);
        expect(c.ui['antiblock'], '1');
        expect(
          find.textContaining('Анти БПЛА: в списке только серверы qWDTT'),
          findsWidgets,
        );
        await _settle(t, 60);
        await expectLater(
          find.byType(NoxApp),
          matchesGoldenFile('shots/234-main-$theme-${w.toInt()}-on.png'),
        );
        expect(t.takeException(), isNull);
      });
    }
  }
}
