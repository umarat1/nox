// Renders the Android accordion server list with sample hosts:
// flutter test --update-goldens test/shots/accordion_shot_test.dart
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
      'accordion_shot_test.dart',
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
  testWidgets('accordion phone list', (t) async {
    t.view.physicalSize = const Size(411, 1900) * 2.625;
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    NoxController.forceAccordion = true;
    final api = MockApi();
    api.servers
      ..clear()
      ..addAll(sampleServers());
    api.selected = 'i1';
    (api.settings['ui'] as Map)['accOpen'] = 'TR:1';
    (api.settings['ui'] as Map)['hdrCol'] = '1';
    final c = NoxController(api);
    await c.refresh();
    PairGlue.suggested = true;
    await t.pumpWidget(NoxApp(c: c));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('Турция'), findsOneWidget);
    expect(find.text('Индия'), findsOneWidget);
    expect(find.text('Все'), findsNothing); // no category tabs
    await expectLater(find.byType(NoxApp), matchesGoldenFile('213-accordion-phone.png'));
    // collapse Турция: state saved, body animates away
    await t.tap(find.text('Турция'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
    expect(c.accOpen['TR'], false);
    NoxController.forceAccordion = false;
  });
}
