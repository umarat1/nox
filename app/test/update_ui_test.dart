import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/mock.dart';
import 'package:nox/src/pair.dart';
import 'package:nox/src/theme.dart';
import 'package:nox/src/update_ui.dart';

import 'ui_util.dart';

Future<(NoxController, MockApi)> _app(
  WidgetTester t,
  Size s, {
  String fs = '1.00',
  bool tv = false,
}) async {
  t.view.physicalSize = s * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final api = MockApi();
  final c = NoxController(api);
  c.isTv = tv;
  await c.refresh();
  c.setPrefLive('fontScale', fs);
  PairGlue.suggested = true;
  await t.pumpWidget(NoxApp(c: c));
  await t.pump(const Duration(milliseconds: 300));
  return (c, api);
}

Future<void> _frames(WidgetTester t, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _open(WidgetTester t, NoxController c) async {
  final ctx = t.element(find.byType(Scaffold).first);
  openUpdate(ctx, c, Pal.of(c.settings['theme']));
  await _frames(t);
}

void main() {
  setUpAll(loadFonts);
  for (final (name, size, tv) in [
    ('phone360', const Size(360, 740), false),
    ('tv', const Size(960, 540), true),
  ]) {
    for (final fs in ['1.00', '1.30']) {
      testWidgets('progress $name font $fs: %, MB, speed, cancel, retry', (
        t,
      ) async {
        final (c, api) = await _app(t, size, fs: fs, tv: tv);
        await _open(t, c);
        expect(api.updStarts, 1);
        expect(find.text('Загрузка'), findsWidgets);
        api.upd = {
          ...api.upd,
          'done': 70508176,
          'total': 141016353,
          'speed': 2.5 * 1048576,
        };
        await _frames(t, 5);
        dumpOverflow(t);
        expect(t.takeException(), isNull);
        expect(find.text('49%'), findsOneWidget);
        expect(find.text('67.2 из 134 МБ'), findsOneWidget);
        expect(find.textContaining('2.5 МБ/с'), findsOneWidget);
        final bar = t.widget<LinearProgressIndicator>(
          find.descendant(
            of: find.byType(UpdateDialog),
            matching: find.byType(LinearProgressIndicator),
          ),
        );
        expect(bar.value, closeTo(0.5, 0.01));
        await t.tap(find.text('Отмена'));
        await _frames(t, 5);
        expect(api.updCancels, 1);
        expect(find.text('Загрузка остановлена'), findsOneWidget);
        expect(find.textContaining('продолжит'), findsOneWidget);
        await t.tap(find.text('Повторить'));
        await _frames(t, 5);
        expect(api.updStarts, 2);
        // verify → error
        api.upd = {...api.upd, 'stage': 'verify', 'done': 141016353};
        await _frames(t, 4);
        expect(find.text('Проверка…'), findsOneWidget);
        api.upd = {
          ...api.upd,
          'active': false,
          'stage': 'error',
          'error': 'контрольная сумма не совпала',
        };
        await _frames(t, 4);
        expect(find.text('Не удалось обновить'), findsOneWidget);
        expect(find.text('контрольная сумма не совпала'), findsOneWidget);
        expect(find.text('Повторить'), findsOneWidget);
        dumpOverflow(t);
        expect(t.takeException(), isNull);
        await t.tap(find.text('Закрыть'));
        await _frames(t, 4);
        expect(find.byType(UpdateDialog), findsNothing);
      });
    }
  }
  testWidgets('install stage asks to confirm; D-pad focus starts on Отмена', (
    t,
  ) async {
    final (c, api) = await _app(t, const Size(960, 540), tv: true);
    await _open(t, c);
    final f = FocusManager.instance.primaryFocus;
    expect(
      f?.context?.findAncestorWidgetOfExactType<OutlinedButton>(),
      isNotNull,
    );
    api.upd = {
      ...api.upd,
      'active': false,
      'stage': 'done',
      'done': 1,
      'total': 1,
    };
    await _frames(t, 4);
    expect(find.text('Подтвердите установку'), findsOneWidget);
  });
  test('formatters', () {
    expect(mb(141016353), '134');
    expect(mb(5 * 1048576 + 300000), '5.3');
    expect(speedText(800 * 1024), '800 КБ/с');
    expect(etaText(10 * 1048576, 1048576), 'ещё 10 с');
    expect(etaText(300 * 1048576, 1048576), 'ещё 5 мин');
  });
}
