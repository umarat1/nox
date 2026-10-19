import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/mock.dart';
import 'package:nox/src/theme.dart';
import 'package:nox/src/tour.dart';

import 'ui_util.dart';

Future<void> _fonts() async {
  final root =
      Platform.environment['FLUTTER_ROOT'] ?? '/workspace/tools/flutter';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  final r = FontLoader('Roboto');
  for (final f in ['Regular', 'Medium', 'Bold']) {
    r.addFont(
      Future.value(
        ByteData.view(File('$dir/Roboto-$f.ttf').readAsBytesSync().buffer),
      ),
    );
  }
  await r.load();
  await (FontLoader('MaterialIcons')..addFont(
        Future.value(
          ByteData.view(
            File('$dir/MaterialIcons-Regular.otf').readAsBytesSync().buffer,
          ),
        ),
      ))
      .load();
}

Future<NoxController> _app(
  WidgetTester t,
  Size s, {
  String fs = '1.00',
  String? tourV, // null = key absent (upgrader from ≤1.0.8)
  bool seen = true,
  MockApi? api,
}) async {
  t.view.physicalSize = s * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  api ??= MockApi();
  final ui = api.settings['ui'] as Map;
  if (!seen) {
    if (tourV == null) {
      ui.remove('tourV');
    } else {
      ui['tourV'] = tourV;
    }
  }
  final c = NoxController(api);
  await c.refresh();
  c.setPrefLive('fontScale', fs);
  await t.pumpWidget(NoxApp(c: c));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  return c;
}

const _sizes = [
  ('phone360', Size(360, 780)),
  ('phone411', Size(411, 860)),
  ('wide', Size(1280, 720)),
  ('tv', Size(1920, 1080)),
];

String? _tourTitle(WidgetTester t) {
  final st = t.state<TourOverlayState>(find.byType(TourOverlay));
  return st.step < 0 ? null : tourSteps()[st.step].title;
}

void main() {
  setUpAll(_fonts);

  for (final (name, size) in _sizes) {
    for (final fs in ['1.00', '1.30']) {
      testWidgets('header: + theme | logo centred | mail settings — $name $fs', (
        t,
      ) async {
        await _app(t, size, fs: fs);
        final logo = find.text('nox');
        final lx = t.getCenter(logo).dx;
        final bar = t.getRect(find.byKey(TourKeys.add)).center.dy;
        // logo centred in the header row (header spans the phone column / whole window)
        final header = t.getRect(
          find.ancestor(of: logo, matching: find.byType(Row)).first,
        );
        expect(lx, closeTo(header.center.dx, 1.0));
        final add = t.getCenter(find.byKey(TourKeys.add)).dx;
        final theme = t.getCenter(find.byKey(TourKeys.theme)).dx;
        final mail = t.getCenter(find.byKey(TourKeys.mail)).dx;
        final set = t.getCenter(find.byKey(TourKeys.settings)).dx;
        expect(add < theme && theme < lx && lx < mail && mail < set, isTrue);
        expect(
          (t.getCenter(find.byKey(TourKeys.mail)).dy - bar).abs(),
          lessThan(2),
        );
        final e = t.takeException();
        if (e != null) dumpOverflow(t);
        expect(e, isNull);
      });
    }
  }

  testWidgets('header ghost buttons show a focus ring', (t) async {
    final c = await _app(t, const Size(1920, 1080));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump(const Duration(milliseconds: 300));
    final p = Pal.of(c.settings['theme'] as String?);
    final ring = find.descendant(
      of: find.byKey(TourKeys.add),
      matching: find.byWidgetPredicate(
        (w) =>
            w is AnimatedContainer &&
            w.decoration is BoxDecoration &&
            ((w.decoration as BoxDecoration).border as Border?)?.top.color ==
                p.acc2,
      ),
    );
    expect(ring, findsOneWidget);
  });

  for (final (name, size) in [_sizes[0], _sizes[2], _sizes[3]]) {
    testWidgets('tour walks every step with OK on $name, then never again', (
      t,
    ) async {
      final api = MockApi();
      final c = await _app(t, size, seen: false, tourV: '', api: api);
      expect(find.byType(TourOverlay), findsOneWidget);
      final seenTitles = <String>[];
      for (
        var i = 0;
        i < 20 && find.byType(TourOverlay).evaluate().isNotEmpty;
        i++
      ) {
        final tt = _tourTitle(t);
        if (tt != null && !seenTitles.contains(tt)) seenTitles.add(tt);
        await t.sendKeyEvent(LogicalKeyboardKey.select);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        final ex = t.takeException();
        if (ex != null) {
          debugPrint('AT STEP $tt');
          dumpOverflow(t);
          fail('$ex');
        }
      }
      expect(find.byType(TourOverlay), findsNothing);
      expect(seenTitles, tourSteps().map((s) => s.title).toList());
      expect(c.pref('tourV', ''), tourVersion);
      // next launch: no tour
      final c2 = NoxController(api);
      await c2.refresh();
      expect(c2.tourOn, isFalse);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('upgrader without the flag sees the tour; Back skips it', (
    t,
  ) async {
    final c = await _app(t, const Size(411, 860), seen: false);
    expect(find.byType(TourOverlay), findsOneWidget);
    expect(_tourTitle(t), 'Добавить подписку');
    await t.tap(find.text('Далее'));
    await t.pump(const Duration(milliseconds: 400));
    expect(_tourTitle(t), 'Тема');
    await t.binding.handlePopRoute(); // Android / TV Back
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(TourOverlay), findsNothing);
    expect(c.pref('tourV', ''), tourVersion);
  });

  testWidgets('Пропустить and Esc close; replay from settings', (t) async {
    final c = await _app(t, const Size(411, 860), seen: false, tourV: '108');
    await t.tap(find.text('Пропустить'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(TourOverlay), findsNothing);
    await t.tap(find.byKey(TourKeys.settings));
    await t.pump(const Duration(milliseconds: 500));
    final item = find.text('Показать подсказки снова');
    final sheetScroll = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Scrollable),
    );
    await t.scrollUntilVisible(item, 150, scrollable: sheetScroll.first);
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(item);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(TourOverlay), findsOneWidget);
    expect(_tourTitle(t), 'Добавить подписку');
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(TourOverlay), findsNothing);
    expect(c.tourOn, isFalse);
  });

  testWidgets('no subscription: steps without a target are skipped', (t) async {
    final api = MockApi()..subs.clear();
    await _app(t, const Size(411, 860), seen: false, tourV: '', api: api);
    final titles = <String>[];
    for (
      var i = 0;
      i < 20 && find.byType(TourOverlay).evaluate().isNotEmpty;
      i++
    ) {
      final tt = _tourTitle(t);
      if (tt != null && !titles.contains(tt)) titles.add(tt);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump(const Duration(milliseconds: 400));
    }
    expect(titles.contains('Подписка'), isFalse);
    expect(titles.first, 'Добавить подписку');
  });
}
