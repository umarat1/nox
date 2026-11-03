// Renders the update dialog with real fonts to PNGs (flutter test --update-goldens test/shots).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/mock.dart';
import 'package:nox/src/pair.dart';

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
      'update_shots_test.dart',
    ),
  );
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
  for (final (name, size) in [('1400x860', const Size(1400, 860)), ('1100x700', const Size(1100, 700))]) {
    for (final st in ['connected', 'disconnected']) {
      testWidgets('desktop $name $st', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final api = MockApi();
        final c = NoxController(api);
        await c.refresh();
        if (st == 'connected') await c.call('Connect');
        await c.refresh();
        PairGlue.suggested = true;
        await t.pumpWidget(NoxApp(c: c));
        for (var i = 0; i < 12; i++) {
          await t.pump(const Duration(milliseconds: 150));
        }
        expect(t.takeException(), isNull);
        await expectLater(find.byType(NoxApp), matchesGoldenFile('1020-desktop-$name-$st.png'));
      });
    }
  }
}
