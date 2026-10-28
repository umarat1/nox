// 2.1.4 round 2: templates, raised list, connection-card variants 1/2/3.
// flutter test --update-goldens test/shots/preview214v2_shot_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/home.dart';
import 'package:nox/src/mock.dart';
import 'package:nox/src/pair.dart';
import 'package:nox/src/theme.dart';

import '../sample_servers.dart';
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

Future<NoxController> _app(
  WidgetTester t, {
  String tpl = 'glass',
  String hero = 'classic',
  double h = 1500,
}) async {
  t.view.physicalSize = Size(411, h) * 2.625;
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  NoxController.forceAccordion = true;
  heroStyle = hero;
  final api = MockApi();
  api.settings['theme'] = 'dark';
  api.settings['ui'] = <String, dynamic>{
    ...(api.settings['ui'] as Map),
    'tpl': tpl,
  };
  api.status = 'connected';
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  api.servers
    ..clear()
    ..addAll(sampleServers().where((s) => s['id'] != 'q3'));
  api.subs
    ..clear()
    ..addAll([
      {
        'id': 's1',
        'name': 'sessia.top',
        'upload': 1.1e9.toInt(),
        'download': 13.1e9.toInt(),
        'total': 0,
        'expire': 0,
        'updated': now - 600,
      },
    ]);
  api.selected = 'i1';
  final c = NoxController(api);
  await c.refresh();
  // a few lone spikes: the calm sparkline must not jump on them
  final d = c.speed.down;
  for (final k in [d.length - 9, d.length - 22, d.length - 31]) {
    if (k > 0) d[k] *= 6;
  }
  PairGlue.suggested = true;
  expect(c.pref('tpl', ''), tpl);
  expect(c.tourOn, isFalse);
  await t.pumpWidget(NoxApp(c: c));
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
  return c;
}

void main() {
  goldenFileComparator = _Tolerant(
    (goldenFileComparator as LocalFileComparator).basedir.resolve(
      'preview214v2_shot_test.dart',
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
    heroStyle = 'classic';
  });
  for (final tpl in templates.map((t) => t.key)) {
    testWidgets('v2 home $tpl', (t) async {
      await _app(t, tpl: tpl);
      expect(find.text('СЕРВЕРЫ'), findsNothing);
      if (tpl == 'mono') expect(find.text('IN'), findsWidgets);
      await expectLater(
        find.byType(NoxApp),
        matchesGoldenFile('214v2-home-$tpl.png'),
      );
    });
  }
  testWidgets('v2 template picker', (t) async {
    final c = await _app(t, tpl: 'glass', h: 1250);
    final ctx = t.element(find.byType(Scaffold).first);
    templateSheet(ctx, c, Pal.of('dark', 'glass'));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 80));
    }
    expect(find.text('Изумруд'), findsOneWidget);
    await t.tap(find.text('Океан'));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 80));
    }
    expect(c.pref('tpl', 'glass'), 'ocean');
    await t.tap(find.text('Стекло'));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 80));
    }
    await expectLater(
      find.byType(NoxApp),
      matchesGoldenFile('214v2-templates.png'),
    );
  });
  for (final hs in ['ring', 'compact', 'timer']) {
    testWidgets('v2 conn $hs', (t) async {
      await _app(t, hero: hs, h: 1000);
      await expectLater(
        find.byType(NoxApp),
        matchesGoldenFile('214v2-conn-$hs.png'),
      );
    });
  }
}
