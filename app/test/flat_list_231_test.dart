// 2.3.1: flat server list (no collapsing), country chips on top, «Текущий» on the
// selected row, no link buttons on the subscription card (they live in «⋯» and Настройки).
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
    return r.passed || r.diffPercent < 0.5;
  }
}

const _size = Size(411, 860);

Future<NoxController> _app(WidgetTester t, String theme, String tpl) async {
  t.view.physicalSize = _size * 2.625;
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  noTopBar = true;
  addTearDown(() => noTopBar = false);
  NoxController.forceAccordion = true;
  phoneTab.value = 0;
  srvQuery.value = '';
  final api = MockApi();
  api.settings['theme'] = theme;
  api.status = 'connected';
  api.servers
    ..clear()
    ..addAll(realServers());
  api.selected = 'm3';
  final c = NoxController(api);
  await c.refresh();
  c.setPrefLive('homeTpl', tpl);
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
      'flat_list_231_test.dart',
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
  for (final theme in ['dark', 'light']) {
    for (final tpl in ['button', 'slider']) {
      testWidgets('flat list, chips, no card links — $theme $tpl', (t) async {
        final c = await _app(t, theme, tpl);
        final n = c.visible().length;
        expect(find.text('Все · $n'), findsOneWidget);
        for (final l in ['etv24.ru', 'iji.by', 'Поддержка', 'Донат']) {
          expect(
            find.text(l),
            findsNothing,
            reason: '$l must not be on the card',
          );
        }
        expect(find.byTooltip('Развернуть'), findsNothing);
        // 2.3.1 phone shell: bottom navigation instead of the hero icons and the FAB
        expect(find.byKey(const Key('phone-nav')), findsOneWidget);
        expect(find.byKey(const Key('hero-corner')), findsNothing);
        expect(find.byKey(const Key('bottom-bar')), findsNothing);
        expect(find.byKey(const Key('current-server')), findsOneWidget);
        expect(
          find.byKey(const Key('slider-dock')),
          tpl == 'slider' ? findsOneWidget : findsNothing,
        );
        expect(t.takeException(), isNull);
        await expectLater(
          find.byType(NoxApp),
          matchesGoldenFile('shots/231-main-$theme-$tpl.png'),
        );
        await t.drag(find.byType(Scrollable).first, const Offset(0, -500));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 60));
        }
        await expectLater(
          find.byType(NoxApp),
          matchesGoldenFile('shots/231-list-$theme-$tpl.png'),
        );
        // chip filters to one country, label stays non-tappable text
        await t.drag(find.byType(Scrollable).first, const Offset(0, 500));
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(find.text('Турция · 13'));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 60));
        }
        expect(find.textContaining('ТУРЦИЯ · 13'), findsOneWidget);
        expect(find.textContaining('ЧЕХИЯ ·'), findsNothing);
        expect(find.text('Текущий'), findsOneWidget);
        await expectLater(
          find.byType(NoxApp),
          matchesGoldenFile('shots/231-chip-$theme-$tpl.png'),
        );
        expect(t.takeException(), isNull);
      });
    }
  }
  testWidgets('links live in Настройки (2.3.2: row at the top)', (t) async {
    await _app(t, 'dark', 'button');
    await t.tap(find.byKey(TourKeys.settings));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
    for (final l in [
      'Поддержка',
      'sessia.top',
      'etv24.ru',
      'iji.by',
      'Донат',
    ]) {
      expect(find.text(l), findsWidgets, reason: l);
    }
    t.takeException();
  });
  for (final theme in ['dark', 'light']) {
    for (final tpl in ['button', 'slider']) {
      testWidgets('tabs Серверы / Подписки / Настройки — $theme $tpl', (
        t,
      ) async {
        await _app(t, theme, tpl);
        for (final (i, name) in [
          (1, 'servers'),
          (2, 'subs'),
          (3, 'settings'),
        ]) {
          await t.tap(
            find.descendant(
              of: find.byKey(const Key('phone-nav')),
              matching: find.text(
                const ['Главная', 'Серверы', 'Подписки', 'Настройки'][i],
              ),
            ),
          );
          for (var k = 0; k < 8; k++) {
            await t.pump(const Duration(milliseconds: 60));
          }
          expect(phoneTab.value, i);
          expect(t.takeException(), isNull, reason: name);
          if (i == 1) {
            expect(find.text('Проверить пинг'), findsOneWidget);
            expect(find.byKey(const Key('page-add-Серверы')), findsOneWidget);
          }
          if (i == 3) {
            expect(find.text('МТС прокси'), findsOneWidget);
            expect(find.text('Обновления и сообщения'), findsOneWidget);
            expect(find.byKey(const Key('settings-links')), findsOneWidget);
          }
          await expectLater(
            find.byType(NoxApp),
            matchesGoldenFile('shots/231-$name-$theme-$tpl.png'),
          );
        }
        // the current-server row opens Серверы
        await t.tap(
          find.descendant(
            of: find.byKey(const Key('phone-nav')),
            matching: find.text('Главная'),
          ),
        );
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(find.byKey(const Key('current-server')));
        await t.pump(const Duration(milliseconds: 300));
        expect(phoneTab.value, 1);
        expect(t.takeException(), isNull);
      });
    }
  }
}
