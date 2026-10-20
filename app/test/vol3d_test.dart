import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/home.dart';
import 'package:nox/src/mock.dart';
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
        'Новые серверы qWDTT через Лондон уже в подписке. Обновите подписку, чтобы получить их. В выходные возможны короткие перерывы на обслуживание.';
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
      expect(find.text('Осталось дней'), findsWidgets);
      expect(find.text('Осталось трафика'), findsWidgets);
      expect(find.text('Объявление'), findsWidgets);
      expect(vol3d, on);
      if (shots) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../preview/home-amoled-3d-${on ? 'on' : 'off'}.png',
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
        matchesGoldenFile('../../../preview/settings-3d.png'),
      );
    }
    await t.tap(find.text('Объёмный 3D-дизайн'));
    for (var i = 0; i < 10; i++)
      await t.pump(const Duration(milliseconds: 100));
    expect(c.ui['vol3d'], '0');
  });
}
