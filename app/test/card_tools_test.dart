// 2.2.1: Android has no top bar; МТС, mail and settings sit in the connection card's
// top-right corner (theme button removed). The list menu has no header, sort or view.
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
  String? name,
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
    if (name != null)
      api.servers.firstWhere((e) => e['id'] == 'm3')['name'] = name;
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

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  void corner(WidgetTester t) {
    final k = find.byKey(const Key('hero-corner'));
    expect(k, findsOneWidget);
    for (final x in [TourKeys.mail, TourKeys.settings]) {
      expect(find.descendant(of: k, matching: find.byKey(x)), findsOneWidget);
    }
    expect(find.descendant(of: k, matching: find.text('МТС')), findsOneWidget);
    // top-right: right edge near the card edge, above the middle of the hero
    final r = t.getRect(k);
    expect(r.right, greaterThan(_size.width - 40));
    expect(r.top, lessThan(60));
    expect(find.byKey(TourKeys.theme), findsNothing);
    expect(find.byKey(const Key('card-tools')), findsNothing);
  }

  for (final st in ['connected', 'disconnected']) {
    testWidgets('corner buttons, no theme, collapse kept — $st', (t) async {
      await _app(t, status: st);
      expect(find.text('nox'), findsNothing);
      corner(t);
      expect(find.byTooltip('Свернуть подписку'), findsOneWidget);
      final e = t.takeException();
      if (e != null) dumpOverflow(t);
      expect(e, isNull);
      await expectLater(
        find.byType(NoxApp),
        matchesGoldenFile('shots/221-main-$st.png'),
      );
    });
  }

  testWidgets('settings and mail open from the corner', (t) async {
    await _app(t);
    await t.tap(find.byKey(TourKeys.settings));
    await settle(t);
    expect(find.byType(BottomSheet), findsWidgets);
    expect(find.text('Тема'), findsWidgets);
    Navigator.of(t.element(find.byType(BottomSheet).first)).pop();
    await settle(t);
    await t.tap(find.byKey(TourKeys.mail));
    await settle(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('subscription collapse still works', (t) async {
    await _app(t);
    await t.tap(find.byTooltip('Свернуть подписку'));
    await settle(t);
    expect(find.byTooltip('Развернуть подписку'), findsOneWidget);
    corner(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('no subscription: corner still there, no tools card', (t) async {
    await _app(t, status: 'disconnected', empty: true);
    corner(t);
    expect(t.takeException(), isNull);
  });

  const long = '🇨🇭 Швейцария очень длинное имя сервера qwdtt через прокси';
  for (final s in ['timer', 'ring', 'compact', 'classic']) {
    testWidgets('style $s: long name is cut, never under the buttons', (
      t,
    ) async {
      await _app(t, style: s, name: long);
      corner(t);
      final e = t.takeException();
      if (e != null) dumpOverflow(t);
      expect(e, isNull);
      final k = t.getRect(find.byKey(const Key('hero-corner')));
      final txt = find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').contains('очень длинное'),
      );
      expect(txt, findsWidgets);
      for (final el in txt.evaluate()) {
        final r = t.getRect(find.byWidget(el.widget));
        expect(r.overlaps(k), isFalse, reason: 'name under the corner in $s');
      }
      await expectLater(
        find.byType(NoxApp),
        matchesGoldenFile('shots/221-main-$s.png'),
      );
    });
  }

  testWidgets('list menu: no header, sort or view; the rest stays', (t) async {
    final c = await _app(t);
    await t.tap(find.byKey(TourKeys.more).first);
    await settle(t);
    expect(find.text('Список'), findsNothing);
    expect(find.textContaining('Сортировка'), findsNothing);
    expect(find.textContaining(RegExp(r'^Вид')), findsNothing);
    expect(find.textContaining('пинг:'), findsNothing);
    for (final x in [
      'Скрыть нерабочие',
      'Скрывать дубликаты',
      'Выбрать самый быстрый',
      'Удалить нерабочие',
      'Тип пинга',
      'Журнал',
    ]) {
      expect(find.textContaining(x), findsWidgets, reason: x);
    }
    expect(c.pref('view', 'list'), 'list');
    await expectLater(
      find.byType(NoxApp),
      matchesGoldenFile('shots/221-list-menu.png'),
    );
    // a toggle still works
    final before = c.flag('dedup', true);
    await t.tap(find.textContaining('Скрывать дубликаты').last);
    await settle(t);
    expect(c.flag('dedup', true), isNot(before));
  });
}
