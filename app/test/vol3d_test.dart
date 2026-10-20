@TestOn('linux')
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/home.dart';
import 'package:nox/src/mock.dart';
import 'package:nox/src/live_graph.dart';
import 'dart:math' as math;
import 'package:nox/src/theme.dart';

Future<void> _loadFonts() async {
  final root =
      Platform.environment['FLUTTER_ROOT'] ?? '/workspace/tools/flutter';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in ['Regular', 'Medium', 'Bold']) {
    final b = File('$dir/Roboto-$f.ttf').readAsBytesSync();
    roboto.addFont(Future.value(ByteData.view(b.buffer)));
  }
  await roboto.load();
  for (final fam in ['Segoe UI', 'Roboto']) {
    final l = FontLoader(fam);
    for (final f in ['DejaVuSans.ttf', 'DejaVuSans-Bold.ttf']) {
      final b = File('/usr/share/fonts/truetype/dejavu/$f').readAsBytesSync();
      l.addFont(Future.value(ByteData.view(b.buffer)));
    }
    await l.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.view(
          File('$dir/MaterialIcons-Regular.otf').readAsBytesSync().buffer,
        ),
      ),
    );
  await icons.load();
  final mono = FontLoader('monospace');
  for (final f in ['DejaVuSansMono.ttf', 'DejaVuSansMono-Bold.ttf']) {
    final b = File('/usr/share/fonts/truetype/dejavu/$f').readAsBytesSync();
    mono.addFont(Future.value(ByteData.view(b.buffer)));
  }
  await mono.load();
}

Future<NoxController> _app(WidgetTester t, {required bool on}) async {
  t.view.physicalSize = const Size(412 * 2, 915 * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final api = MockApi();
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  for (final b in api.subs) {
    b['expire'] = now + 6 * 86400;
    b['total'] = 100 * 1024 * 1024 * 1024;
    b['upload'] = 8 * 1024 * 1024 * 1024;
    b['download'] = 70 * 1024 * 1024 * 1024;
    b['announce'] =
        '**Новые серверы qWDTT** через Лондон уже в подписке.\n• Обновите подписку, чтобы получить их\n• В выходные возможны короткие перерывы\nПодробнее: https://iji.by/vps/';
  }
  final c = NoxController(api);
  await c.refresh();
  await c.saveSettings({'theme': 'black'});
  c.setPrefLive('vol3d', on ? '1' : '0');
  await t.pumpWidget(NoxApp(c: c));
  await t.pump(const Duration(milliseconds: 300));
  return c;
}

void main() {
  setUpAll(_loadFonts);
  final shots = Platform.environment['NOX_SHOTS'] == '1';

  testWidgets('3D default on; toggle off makes surfaces flat, AMOLED black', (
    t,
  ) async {
    final api = MockApi();
    final c = NoxController(api);
    await c.refresh();
    expect(vol3dFromUi(c.ui), isTrue); // default ON
    await c.setPref('vol3d', '0');
    expect(c.ui['vol3d'], '0'); // persisted in settings.ui
    expect(vol3dFromUi(c.ui), isFalse);
    vol3d = false;
    expect(raisedShadow(Pal.black), isEmpty);
    final g = raisedGradient(Pal.black, Pal.black.card) as LinearGradient;
    expect(g.colors.toSet().length, 1);
    expect(Pal.black.bg, const Color(0xFF000000));
    vol3d = true;
    expect(raisedShadow(Pal.dark), isNotEmpty);
  });

  for (final on in [true, false]) {
    testWidgets('home amoled 3d=$on renders subscription + announcement', (
      t,
    ) async {
      await _app(t, on: on);
      expect(find.text('Осталось дней'), findsNothing);
      expect(find.text('6 дней'), findsWidgets);
      expect(find.text('Объявление'), findsWidgets);
      expect(vol3d, on);
      if (shots) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../preview/home-1018-3d-${on ? 'on' : 'off'}.png',
          ),
        );
      }
    });
  }

  testWidgets('settings has 3D switch next to theme', (t) async {
    final c = await _app(t, on: true);
    final ctx = t.element(find.byType(Scaffold).first);
    settingsSheet(ctx, c, Pal.black);
    for (var i = 0; i < 10; i++)
      await t.pump(const Duration(milliseconds: 100));
    final theme = t.getTopLeft(find.text('Тема').last).dy;
    final s3d = t.getTopLeft(find.text('Объёмный 3D-дизайн')).dy;
    expect(s3d > theme && s3d - theme < 90, isTrue);
    if (shots) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../preview/settings-1018-3d.png'),
      );
    }
    await t.tap(find.text('Объёмный 3D-дизайн'));
    for (var i = 0; i < 10; i++)
      await t.pump(const Duration(milliseconds: 100));
    expect(c.ui['vol3d'], '0');
  });

  testWidgets('menus 3D: subscription ⋮ sheet and add sheet', (t) async {
    final c = await _app(t, on: true);
    await t.tap(find.byTooltip('Действия с подпиской').first);
    for (var i = 0; i < 10; i++)
      await t.pump(const Duration(milliseconds: 100));
    if (shots) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../preview/menu-sub-1018-3d.png'),
      );
    }
    Navigator.of(t.element(find.byType(Scaffold).first)).pop();
    for (var i = 0; i < 10; i++)
      await t.pump(const Duration(milliseconds: 100));
    addSheet(t.element(find.byType(Scaffold).first), c, Pal.black);
    for (var i = 0; i < 10; i++)
      await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Цепочка'), findsWidgets);
    if (shots) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../preview/menu-add-1018-3d.png'),
      );
    }
  });

  testWidgets('manual add sheet', (t) async {
    final c = await _app(t, on: true);
    manualSheet(t.element(find.byType(Scaffold).first), c, Pal.black);
    for (var i = 0; i < 10; i++)
      await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Juicity'), findsWidgets);
    if (shots) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../preview/manual-add-1018.png'),
      );
    }
  });

  for (final st in ['', 'smooth', 'matrix']) {
    testWidgets('graph style "$st"', (t) async {
      t.view.physicalSize = const Size(412 * 2, 240 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      graphStyle = st;
      final r = math.Random(7);
      final s = SpeedSeries();
      s.feed({
        'Seq': 60,
        'Hist': [
          for (var i = 0; i < 60; i++)
            [
              (20000 + r.nextInt(120000)) * (i % 9 == 0 ? 3 : 1),
              (300000 + r.nextInt(1500000)) * (i % 7 == 0 ? 2 : 1),
            ],
        ],
      });
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Roboto'),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: 200,
                child: LiveGraph(
                  series: s,
                  p: Pal.black,
                  active: true,
                  labels: true,
                  span: 60,
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 8; i++)
        await t.pump(const Duration(milliseconds: 200));
      if (shots) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../preview/graph-${st.isEmpty ? 'classic' : st}.png',
          ),
        );
      }
      graphStyle = '';
      await t.pumpWidget(const SizedBox());
    });
  }
}
