// Renders the update dialog with real fonts to PNGs (flutter test --update-goldens test/shots).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/mock.dart';
import 'package:nox/src/pair.dart';
import 'package:nox/src/theme.dart';
import 'package:nox/src/update_ui.dart';

import '../ui_util.dart';

void main() {
  setUpAll(() async {
    await loadFonts();
    // Android has no Segoe UI either: the app falls back to Roboto there
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
  final states = <String, Map<String, dynamic>>{
    'download': {
      'active': true,
      'stage': 'download',
      'version': '1.0.11',
      'done': 61341696,
      'total': 141069353,
      'speed': 3.4 * 1048576,
      'resumed': false,
      'error': '',
    },
    'verify': {
      'active': true,
      'stage': 'verify',
      'version': '1.0.11',
      'done': 141069353,
      'total': 141069353,
      'speed': 0.0,
      'error': '',
    },
    'error': {
      'active': false,
      'stage': 'error',
      'version': '1.0.11',
      'done': 80000000,
      'total': 141069353,
      'speed': 0.0,
      'error': 'загрузка прервалась: connection reset by peer',
    },
    'canceled': {
      'active': false,
      'stage': 'canceled',
      'version': '1.0.11',
      'done': 61341696,
      'total': 141069353,
      'speed': 0.0,
      'error': '',
    },
  };
  for (final (dev, size, tv) in [
    ('phone', const Size(411, 860), false),
    ('tv', const Size(960, 540), true),
  ]) {
    for (final e in states.entries) {
      testWidgets('shot $dev ${e.key}', (t) async {
        t.view.physicalSize = size * 2.625;
        t.view.devicePixelRatio = 2.625;
        addTearDown(t.view.reset);
        final api = MockApi();
        final c = NoxController(api);
        c.isTv = tv;
        await c.refresh();
        PairGlue.suggested = true;
        await t.pumpWidget(NoxApp(c: c));
        await t.pump(const Duration(milliseconds: 300));
        openUpdate(
          t.element(find.byType(Scaffold).first),
          c,
          Pal.of(c.settings['theme']),
        );
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 120));
        }
        api.upd = e.value;
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 120));
        }
        await expectLater(
          find.byType(NoxApp),
          matchesGoldenFile('111-update-$dev-${e.key}.png'),
        );
      });
    }
  }
}
