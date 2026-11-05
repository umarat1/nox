// 2.2.7 navy/purple nebula power rings — visual check.
// flutter test --update-goldens test/shots/navy_theme_shot_test.dart
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

Future<void> _shot(WidgetTester t, {required bool on, required String name}) async {
  t.view.physicalSize = const Size(411, 890) * 2.625;
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  NoxController.forceAccordion = true;
  heroStyle = 'ring';
  final api = MockApi();
  api.settings['theme'] = 'dark';
  api.settings['ui'] = <String, dynamic>{
    ...(api.settings['ui'] as Map),
    'tpl': 'purple',
  };
  api.status = on ? 'connected' : 'disconnected';
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
  PairGlue.suggested = true;
  await t.pumpWidget(NoxApp(c: c));
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(name));
}

void main() {
  goldenFileComparator = _Tolerant(
    (goldenFileComparator as LocalFileComparator).basedir.resolve(
      'navy_theme_shot_test.dart',
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

  testWidgets('navy purple home off', (t) async {
    await _shot(t, on: false, name: 'navy_home.png');
  });
  testWidgets('navy purple home on', (t) async {
    await _shot(t, on: true, name: 'navy_home_on.png');
  });
  testWidgets('navy purple desktop wide', (t) async {
    t.view.physicalSize = const Size(1280, 800) * 1.5;
    t.view.devicePixelRatio = 1.5;
    addTearDown(t.view.reset);
    NoxController.forceAccordion = true;
    heroStyle = 'ring';
    final api = MockApi();
    api.settings['theme'] = 'dark';
    api.settings['ui'] = <String, dynamic>{
      ...(api.settings['ui'] as Map),
      'tpl': 'purple',
    };
    api.status = 'disconnected';
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
    PairGlue.suggested = true;
    await t.pumpWidget(NoxApp(c: c));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('navy_pc.png'));
  });
}
