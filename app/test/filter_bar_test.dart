import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/mock.dart';

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

Future<NoxController> _app(WidgetTester t, Size s, {String fs = '1.00'}) async {
  t.view.physicalSize = s * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final c = NoxController(MockApi());
  await c.refresh();
  c.setPrefLive('fontScale', fs);
  await t.pumpWidget(NoxApp(c: c));
  await t.pump();
  return c;
}

void main() {
  setUpAll(_fonts);

  for (final (name, size) in [
    ('phone360', const Size(360, 780)),
    ('wide', const Size(1280, 720)),
    ('tv', const Size(1920, 1080)),
  ]) {
    for (final fs in ['1.00', '1.30']) {
      testWidgets('filter bar one row $name font=$fs', (t) async {
        await _app(t, size, fs: fs);
        // 2.1.4: two glass subscription cards can push the bar below the fold on 360dp@1.3
        expect(find.text('Все', skipOffstage: false), findsOneWidget);
        expect(find.byTooltip('Пинг', skipOffstage: false), findsOneWidget);
        expect(find.byTooltip('Обновить', skipOffstage: false), findsOneWidget);
        expect(find.byTooltip('Обновить подписки'), findsNothing);
        // «N из M · пинг» moved off the main screen
        expect(find.textContaining(RegExp(r'\d+ из \d+')), findsNothing);
        // tabs and the three buttons share one row
        final tabY = t.getCenter(find.text('Все', skipOffstage: false)).dy;
        final btnY = t.getCenter(find.byTooltip('Пинг', skipOffstage: false)).dy;
        expect((tabY - btnY).abs(), lessThan(8));
        final e = t.takeException();
        if (e != null) dumpOverflow(t);
        expect(e, isNull);
      });
    }
  }

  testWidgets('⋮ sheet shows list caption', (t) async {
    await _app(t, const Size(411, 860));
    final barY = t.getCenter(find.byTooltip('Пинг')).dy;
    final more = find
        .byTooltip('Ещё')
        .evaluate()
        .firstWhere(
          (e) => (t.getCenter(find.byWidget(e.widget)).dy - barY).abs() < 10,
        );
    await t.tap(find.byWidget(more.widget));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.textContaining(RegExp(r'\d+ из \d+ · пинг')), findsOneWidget);
  });

  testWidgets('D-pad reaches tabs and selects with Enter', (t) async {
    final c = await _app(t, const Size(1920, 1080));
    final tabs = c.chips();
    expect(tabs.length, greaterThan(1));
    final second = tabs[1];
    bool focusedOn(String label) {
      final f = FocusManager.instance.primaryFocus?.context;
      return f != null &&
          find
              .descendant(
                of: find.byWidget(f.widget),
                matching: find.text(label),
              )
              .evaluate()
              .isNotEmpty;
    }

    // Remote: Down until we land on the filter-bar row (⋮ / ↻ / ⚡), then Left along the tabs.
    final barY = t.getCenter(find.byTooltip('Пинг')).dy;
    // first key focuses «+» (header left); walk Right across the header to ⚙
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    for (var i = 0; i < 8; i++) {
      final f = FocusManager.instance.primaryFocus?.context;
      if (f != null &&
          t.getCenter(find.byWidget(f.widget).first).dx > 1920 * .8)
        break;
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
    }
    var onBar = false;
    for (var i = 0; i < 12 && !onBar; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      final f = FocusManager.instance.primaryFocus?.context;
      onBar =
          f != null &&
          (t.getCenter(find.byWidget(f.widget).first).dy - barY).abs() < 10;
    }
    expect(onBar, isTrue, reason: 'Down never reached the filter bar');
    var hit = false;
    for (var j = 0; j < 20 && !hit; j++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump(const Duration(milliseconds: 50));
      hit = focusedOn(second.$2);
    }
    expect(hit, isTrue, reason: 'tab «${second.$2}» never got D-pad focus');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump(const Duration(milliseconds: 600));
    expect(c.category, second.$1);
  });

  testWidgets('sections collapse shrinks window height with no top/bottom space', (t) async {
    await _app(t, const Size(411, 860));
    expect(t.getSize(find.byType(MaterialApp)).height, 860);

    // Header collapse toggle works independently and reduces height
    expect(find.byTooltip('Свернуть шапку'), findsOneWidget);
    await t.tap(find.byTooltip('Свернуть шапку'));
    await t.pump();
    await t.pump();
    expect(find.byTooltip('Развернуть шапку'), findsOneWidget);
    expect(t.getSize(find.byType(MaterialApp)).height, lessThan(860));
    await t.tap(find.byTooltip('Развернуть шапку'));
    await t.pump();
    await t.pump();
    expect(find.byTooltip('Свернуть шапку'), findsOneWidget);
    expect(t.getSize(find.byType(MaterialApp)).height, 860);

    // Subscription collapse still shrinks the window. The server list on a phone
    // has no chevron and stays expanded.
    await t.tap(find.byTooltip('Свернуть подписку'));
    await t.pump();
    await t.pump();
    expect(find.byTooltip('Развернуть подписку'), findsOneWidget);
    expect(t.getSize(find.byType(MaterialApp)).height, lessThan(750));
    expect(find.byTooltip('Свернуть серверы'), findsNothing);
    expect(find.byTooltip('Развернуть серверы'), findsNothing);
    expect(find.text('Лондон 1'), findsWidgets);
    final row = find.ancestor(
      of: find.text('Лондон 1').last,
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: row.first, matching: find.text('VLESS')),
      findsNothing,
    );
  });

  testWidgets('desktop keeps server collapse and the protocol line', (t) async {
    await _app(t, const Size(1280, 800));
    expect(find.byTooltip('Свернуть серверы'), findsOneWidget);
    expect(find.text('Hysteria2'), findsWidgets);
    await t.tap(find.byTooltip('Свернуть серверы'));
    await t.pump();
    await t.pump();
    expect(find.byTooltip('Развернуть серверы'), findsOneWidget);
  });
}
