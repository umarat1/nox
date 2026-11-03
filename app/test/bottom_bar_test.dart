// 2.1.8: bottom bar, left to right: «＋», «Добавить из буфера» (only while nothing is added),
// then the connect pill filling the rest; the pill is no longer in the «Таймер» card.
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

const _size = Size(411, 860);

Future<NoxController> _app(
  WidgetTester t,
  String status, {
  bool empty = false,
  String sel = 'm3',
}) async {
  t.view.physicalSize = _size * 2.625;
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  NoxController.forceAccordion = true;
  heroStyle = 'timer';
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
    api.selected = sel;
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
  setUpAll(() async {
    await loadFonts();
    // Screenshots: a Cyrillic face under the app's family when the box has one.
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

  testWidgets(
    'pill is in the bottom bar to the right of «＋», not in the card',
    (t) async {
      await _app(t, 'connecting');
      expect(find.byType(TapPill), findsOneWidget);
      final bar = find.byKey(const Key('bottom-bar'));
      expect(
        find.descendant(of: bar, matching: find.byType(TapPill)),
        findsOneWidget,
      );
      final add = t.getRect(find.byKey(TourKeys.add));
      final pill = t.getRect(find.byKey(TourKeys.power));
      expect(add.left, lessThan(40));
      expect(pill.left, greaterThan(add.right));
      expect(pill.right, greaterThan(_size.width - 40));
      expect((pill.center.dy - add.center.dy).abs(), lessThan(2));
      expect(pill.bottom, greaterThan(_size.height - 40));
      expect(find.byKey(const Key('clip-add')), findsNothing);
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(NoxApp),
        matchesGoldenFile('shots/218-bottom-bar-connecting.png'),
      );
    },
  );

  testWidgets('the last server scrolls clear of the bar', (t) async {
    await _app(t, 'disconnected', sel: '');
    for (var i = 0; i < 4; i++) {
      await t.dragFrom(const Offset(200, 600), const Offset(0, -1500));
      await t.pump(const Duration(milliseconds: 400));
    }
    final barTop = t.getRect(find.byKey(TourKeys.power)).top;
    final last = find.textContaining('Швейцария');
    expect(last, findsWidgets);
    expect(t.getRect(last.last).bottom, lessThan(barTop));
    await expectLater(
      find.byType(NoxApp),
      matchesGoldenFile('shots/218-bottom-bar-scrolled.png'),
    );
  });

  testWidgets('empty: «＋», «Добавить из буфера», pill — in that order', (
    t,
  ) async {
    await _app(t, 'disconnected', empty: true);
    final add = t.getRect(find.byKey(TourKeys.add));
    final clip = t.getRect(find.byKey(const Key('clip-add')));
    final pill = t.getRect(find.byKey(TourKeys.power));
    expect(add.right, lessThanOrEqualTo(clip.left));
    expect(clip.right, lessThanOrEqualTo(pill.left));
    expect((clip.center.dy - pill.center.dy).abs(), lessThan(2));
    expect(find.byKey(const Key('clip-add')), findsOneWidget);
    final e = t.takeException();
    if (e != null) dumpOverflow(t);
    expect(e, isNull);
    await expectLater(
      find.byType(NoxApp),
      matchesGoldenFile('shots/218-bottom-bar-empty.png'),
    );
  });

  testWidgets(
    '2.2.0: in the bar the knob drags (shot mid-drag), past 60% connects',
    (t) async {
      TapPill.debounce = Duration.zero;
      addTearDown(() => TapPill.debounce = const Duration(milliseconds: 700));
      noTopBar = true;
      addTearDown(() => noTopBar = false);
      final c = await _app(t, 'disconnected', sel: '');
      final r = t.getRect(find.byKey(TourKeys.power));
      final g = await t.startGesture(Offset(r.left + 26, r.center.dy));
      for (var i = 0; i < 8; i++) {
        await g.moveBy(Offset(r.width * .45 / 8, 0));
        await t.pump(const Duration(milliseconds: 30));
      }
      expect(c.connected, isFalse);
      await expectLater(
        find.byType(NoxApp),
        matchesGoldenFile('shots/220-bottom-bar-drag.png'),
      );
      for (var i = 0; i < 6; i++) {
        await g.moveBy(Offset(r.width * .3 / 6, 0));
        await t.pump(const Duration(milliseconds: 30));
      }
      await g.up();
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 60));
      }
      expect(c.connected, isTrue);
    },
  );
}
