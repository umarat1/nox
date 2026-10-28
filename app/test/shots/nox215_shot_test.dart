// 2.1.5: the phone list never shows the «СЕРВЕРЫ» header; ping progress sits in the
// subscription card's ⚡; ⋮ is on «Автовыбор» or, without it, on the first country card.
// Data: the real «Серверная» subscription (69 hosts, 5 countries, no Автовыбор).
// flutter test --update-goldens test/shots/nox215_shot_test.dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/country_groups.dart';
import 'package:nox/src/home.dart';
import 'package:nox/src/mock.dart';
import 'package:nox/src/pair.dart';
import 'package:nox/src/tour.dart';

import '../real_servers.dart';
import '../ui_util.dart';

class _Tolerant extends LocalFileComparator {
  _Tolerant(super.testFile);
  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final r = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    return r.passed || r.diffPercent < 0.02;
  }
}

class _PingApi extends MockApi {
  int done = 0, all = 0;
  @override
  Future<dynamic> call(String m, [List<dynamic> a = const []]) async {
    final r = await super.call(m, a);
    if (m == 'GetState' && all > 0) {
      return {...(r as Map), 'pinging': true, 'pingDone': done, 'pingAll': all};
    }
    return r;
  }
}

Future<NoxController> _app(
  WidgetTester t, {
  bool auto = false,
  bool ping = false,
  bool twoSubs = false,
  double h = 1500,
}) async {
  t.view.physicalSize = Size(411, h) * 2.625;
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  NoxController.forceAccordion = true;
  heroStyle = 'timer';
  final api = _PingApi();
  api.settings['theme'] = 'dark';
  api.status = 'connected';
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final list = realServers();
  if (twoSubs) {
    for (final s in list.skip(47)) {
      s['subId'] = 's2';
    }
  }
  api.servers
    ..clear()
    ..addAll([
      if (auto)
        {
          'id': 'auto',
          'subId': 's1',
          'name': 'Автовыбор',
          'type': 'Автовыбор',
          'host': '',
          'port': 0,
          'ping': 52,
          'outbound': {'type': '_balancer'},
        },
      ...list,
    ]);
  api.subs
    ..clear()
    ..addAll([
      {
        'id': 's1',
        'name': 'Серверная',
        'upload': 1.1e9.toInt(),
        'download': 13.1e9.toInt(),
        'total': 0,
        'expire': now + 86400 * 23,
        'updated': now - 600,
      },
      if (twoSubs)
        {
          'id': 's2',
          'name': 'Билайн',
          'upload': 0,
          'download': 2.4e9.toInt(),
          'total': 50e9.toInt(),
          'expire': 0,
          'updated': now - 3600,
        },
    ]);
  api.selected = 'm3';
  if (ping) {
    api.done = 41;
    api.all = 69;
  }
  final c = NoxController(api);
  await c.refresh();
  if (ping) c.pingWait = {for (final s in list.skip(41)) s['id'] as String};
  c.setAccOpen('TR', true);
  PairGlue.suggested = true;
  await t.pumpWidget(NoxApp(c: c));
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
  return c;
}

void main() {
  goldenFileComparator = _Tolerant(
    (goldenFileComparator as LocalFileComparator).basedir.resolve(
      'nox215_shot_test.dart',
    ),
  );
  setUpAll(() async {
    await loadFonts();
    final dir =
        '${Platform.environment['FLUTTER_ROOT'] ?? '/workspace/tools/flutter'}/bin/cache/artifacts/material_fonts';
    final l = FontLoader('Segoe UI');
    for (final f in ['Regular', 'Medium', 'Bold']) {
      l.addFont(
        Future.value(
          ByteData.view(File('$dir/Roboto-$f.ttf').readAsBytesSync().buffer),
        ),
      );
    }
    await l.load();
  });
  tearDown(() {
    NoxController.forceAccordion = false;
    heroStyle = 'timer';
  });

  testWidgets('215 real list, no Автовыбор, ping running', (t) async {
    final c = await _app(t, ping: true, h: 900);
    expect(c.visible().length, 69);
    expect(c.visible().any(NoxController.isBal), isFalse);
    expect(find.text('СЕРВЕРЫ'), findsNothing);
    expect(find.textContaining('Пинг 41/69'), findsNothing);
    expect(find.text('41/69'), findsOneWidget);
    expect(find.byKey(TourKeys.more), findsOneWidget); // on the first country card
    expect(find.byKey(TourKeys.ping), findsOneWidget); // the ⚡ / progress pill
    await expectLater(
      find.byType(NoxApp),
      matchesGoldenFile('215-real-ping.png'),
    );
  });

  testWidgets('215 real list, no Автовыбор, idle (tall)', (t) async {
    final c = await _app(t);
    expect(find.text('СЕРВЕРЫ'), findsNothing);
    final tree = groupServers(c.visible(), order: c.allServers);
    expect(tree.auto, isEmpty);
    expect(tree.groups.map((g) => g.title).toList(), [
      'Турция',
      'Индия',
      'Лондон',
      'Швейцария',
      'Чехия',
    ]);
    expect(tree.groups.fold<int>(0, (n, g) => n + g.count), 69);
    expect(find.byKey(TourKeys.more), findsOneWidget);
    await t.tap(find.byKey(TourKeys.more));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 80));
    }
    expect(find.text('Сортировка'), findsOneWidget);
    await expectLater(
      find.byType(NoxApp),
      matchesGoldenFile('215-real-menu.png'),
    );
  });

  testWidgets('215 real list with Автовыбор, ping running', (t) async {
    await _app(t, auto: true, ping: true);
    expect(find.text('СЕРВЕРЫ'), findsNothing);
    expect(find.text('41/69'), findsOneWidget);
    expect(find.byKey(TourKeys.more), findsOneWidget); // on the Автовыбор row
    await expectLater(
      find.byType(NoxApp),
      matchesGoldenFile('215-real-auto-ping.png'),
    );
  });

  testWidgets('215 two subscriptions: ⚡ and ⋮ in each card', (t) async {
    await _app(t, twoSubs: true, h: 1300);
    expect(find.text('СЕРВЕРЫ'), findsNothing);
    expect(find.byTooltip('Пинг'), findsNWidgets(2));
    expect(find.byTooltip('Меню списка'), findsNWidgets(3)); // 2 sub cards + 1st country
    await expectLater(
      find.byType(NoxApp),
      matchesGoldenFile('215-two-subs.png'),
    );
  });

  test('copy preview', () {
    final f = File('test/shots/215-real-ping.png');
    if (!f.existsSync()) return;
    f.copySync('/workspace/nox215-preview.png');
  });
}
