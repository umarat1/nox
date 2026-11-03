// 2.1.4 look: glass subscription card + restyled accordion, colour and monochrome themes.
// flutter test --update-goldens test/shots/preview214_shot_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
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

void main() {
  goldenFileComparator = _Tolerant(
    (goldenFileComparator as LocalFileComparator).basedir.resolve(
      'preview214_shot_test.dart',
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
  for (final th in ['dark', 'mono']) {
    testWidgets('2.1.4 preview $th', (t) async {
      t.view.physicalSize = const Size(411, 1500) * 2.625;
      t.view.devicePixelRatio = 2.625;
      addTearDown(t.view.reset);
      NoxController.forceAccordion = true;
      final api = MockApi();
      api.settings['theme'] = th;
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
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 120));
      }
      if (th == 'mono') expect(find.text('IN'), findsWidgets);
      await expectLater(
        find.byType(NoxApp),
        matchesGoldenFile('214-preview-$th.png'),
      );
      NoxController.forceAccordion = false;
    });
  }
}
