// 2.2.0: Android has no top bar; МТС, theme, mail and settings sit in the subscription
// card (or a small glass card when there is no subscription). Shots of the new screen.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/home.dart';
import 'package:nox/src/mock.dart';
import 'package:nox/src/pair.dart';
import 'package:nox/src/tour.dart';

import 'real_servers.dart';
import 'ui_util.dart';

class _Tolerant extends LocalFileComparator {
  _Tolerant(super.testFile);
  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final r = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    // the connected timer ticks with the wall clock
    return r.passed || r.diffPercent < 0.01;
  }
}

const _size = Size(411, 860);

Future<NoxController> _app(
  WidgetTester t, {
  String status = 'connected',
  bool empty = false,
  String style = 'timer',
}) async {
  t.view.physicalSize = _size * 2.625;
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  noTopBar = true;
  addTearDown(() => noTopBar = false);
  NoxController.forceAccordion = true;
  heroStyle = style;
  addTearDown(() => heroStyle = 'timer');
  final api = MockApi();
  api.settings['theme'] = 'dark';
  api.status = status;
  if (empty) {
    api.subs.clear();
    api.servers.clear();
  } else {
    api.servers
      ..clear()
      ..addAll(realServers());
    api.selected = 'm3';
  }
  final c = NoxController(api);
  await c.refresh();
  PairGlue.suggested = true;
  await t.pumpWidget(NoxApp(c: c));
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
  return c;
}

void main() {
  goldenFileComparator = _Tolerant(
    (goldenFileComparator as LocalFileComparator).basedir.resolve(
      'card_tools_test.dart',
    ),
  );
  setUpAll(() async {
    await loadFonts();
    const cyr =
        '/usr/share/fonts/truetype/sand-box/google/Roboto/Roboto-VariableFont_wdth,wght.ttf';
    if (File(cyr).existsSync()) {
      for (final fam in ['Segoe UI', 'Roboto']) {
        await (FontLoader(fam)..addFont(
              Future.value(ByteData.view(File(cyr).readAsBytesSync().buffer)),
            ))
            .load();
      }
    }
  });

  testWidgets('no top bar: no wordmark, buttons in the subscription card', (
    t,
  ) async {
    final c = await _app(t);
    expect(find.text('nox'), findsNothing);
    expect(find.byTooltip('Свернуть шапку'), findsNothing);
    final tools = find.byKey(const Key('card-tools'));
    expect(tools, findsOneWidget);
    expect(
      find.descendant(of: find.byKey(TourKeys.sub), matching: tools),
      findsOneWidget,
    );
    for (final k in [TourKeys.theme, TourKeys.mail, TourKeys.settings]) {
      expect(
        find.descendant(of: tools, matching: find.byKey(k)),
        findsOneWidget,
      );
    }
    // the connection card is now first, right under the safe area
    final hero = t.getRect(find.text('ПОДКЛЮЧЕНО').first);
    expect(hero.top, lessThan(80));
    final e = t.takeException();
    if (e != null) dumpOverflow(t);
    expect(e, isNull);
    await expectLater(
      find.byType(NoxApp),
      matchesGoldenFile('shots/220-main.png'),
    );
    // theme still cycles
    final before = c.settings['theme'];
    await t.tap(find.byKey(TourKeys.theme));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
    expect(c.settings['theme'], isNot(before));
  });

  testWidgets('settings opens from the card', (t) async {
    await _app(t);
    await t.tap(find.byKey(TourKeys.settings));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
    expect(find.byType(BottomSheet), findsWidgets);
  });

  testWidgets('collapsed subscription keeps the buttons', (t) async {
    await _app(t);
    await t.tap(find.byTooltip('Свернуть подписку'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
    expect(find.byTooltip('Развернуть подписку'), findsOneWidget);
    expect(find.byKey(const Key('card-tools')), findsOneWidget);
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(NoxApp),
      matchesGoldenFile('shots/220-main-collapsed.png'),
    );
  });

  testWidgets('no subscription: buttons in their own glass card', (t) async {
    await _app(t, status: 'disconnected', empty: true);
    expect(find.byKey(const Key('card-tools')), findsOneWidget);
    expect(find.byKey(TourKeys.settings), findsOneWidget);
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(NoxApp),
      matchesGoldenFile('shots/220-main-empty.png'),
    );
  });

  for (final s in ['ring', 'compact', 'classic']) {
    testWidgets('hero style $s: buttons in the card, no overflow', (t) async {
      await _app(t, style: s);
      expect(find.byKey(const Key('card-tools')), findsOneWidget);
      final e = t.takeException();
      if (e != null) dumpOverflow(t);
      expect(e, isNull);
      await expectLater(
        find.byType(NoxApp),
        matchesGoldenFile('shots/220-main-$s.png'),
      );
    });
  }
}
