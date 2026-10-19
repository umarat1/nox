import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/mock.dart';
import 'package:nox/src/pair.dart';

import 'ui_util.dart';

Future<NoxController> _app(
  WidgetTester t,
  Size s, {
  MockApi? api,
  bool tv = false,
  String fs = '1.00',
}) async {
  t.view.physicalSize = s * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  api ??= MockApi();
  final c = NoxController(api);
  c.isTv = tv;
  await c.refresh();
  c.setPrefLive('fontScale', fs);
  await t.pumpWidget(NoxApp(c: c));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  return c;
}

Future<void> _push(WidgetTester t, Widget page) async {
  final nav = t.state<NavigatorState>(find.byType(Navigator).first);
  nav.push(MaterialPageRoute(builder: (_) => page));
  await _frames(t);
}

Future<void> _frames(WidgetTester t, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

const _sizes = [
  ('phone360', Size(360, 780)),
  ('wide', Size(1280, 720)),
  ('tv', Size(1920, 1080)),
];

void main() {
  setUpAll(loadFonts);
  setUp(() => PairGlue.suggested = false);

  for (final (name, size) in _sizes) {
    for (final fs in ['1.00', '1.30']) {
      testWidgets('receive screen $name font $fs: QR, address, code; result', (
        t,
      ) async {
        final api = MockApi();
        final c = await _app(t, size, api: api, tv: name == 'tv', fs: fs);
        await _push(t, PairReceivePage(c: c));
        dumpOverflow(t);
        expect(t.takeException(), isNull);
        expect(find.byType(QrView), findsOneWidget);
        expect(find.text('192.168.1.23:41234'), findsOneWidget);
        expect(find.text('482 913'), findsOneWidget);
        expect(find.textContaining('Ожидание телефона'), findsOneWidget);
        // a phone delivers
        api.pair = {
          ...api.pair,
          'active': false,
          'result': {'subs': 2, 'servers': 4, 'dups': 1},
        };
        await t.pump(const Duration(milliseconds: 1100));
        await t.pump(const Duration(milliseconds: 100));
        expect(find.text('Получено: 2 подписки, 4 сервера'), findsOneWidget);
        expect(find.textContaining('уже были: 1'), findsOneWidget);
        expect(t.takeException(), isNull);
        // D-pad: OK on the autofocused «Готово» closes
        await t.pump(const Duration(milliseconds: 100));
        await t.sendKeyEvent(LogicalKeyboardKey.select);
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 200));
        }
        expect(find.byType(PairReceivePage), findsNothing);
      });
    }
  }

  testWidgets('TV without profiles opens «Принять с телефона» once', (t) async {
    final api = MockApi()
      ..subs.clear()
      ..servers.clear();
    await _app(t, const Size(1920, 1080), api: api, tv: true);
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(PairReceivePage), findsOneWidget);
    // Back closes it and stops the receiver; not suggested again this launch
    await t.binding.handlePopRoute();
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(PairReceivePage), findsNothing);
    expect(api.pair['active'], isFalse);
    await t.pump(const Duration(seconds: 2));
    expect(find.byType(PairReceivePage), findsNothing);
  });

  testWidgets('TV with profiles and phones never auto-open it', (t) async {
    await _app(t, const Size(1920, 1080), tv: true);
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(PairReceivePage), findsNothing);
    PairGlue.suggested = false;
    final api = MockApi()
      ..subs.clear()
      ..servers.clear();
    await _app(t, const Size(411, 860), api: api);
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(PairReceivePage), findsNothing);
  });

  testWidgets('«+» offers both directions', (t) async {
    await _app(t, const Size(411, 860));
    await t.tap(find.byTooltip('Добавить подписку'));
    await _frames(t);
    expect(find.text('Передать на ТВ'), findsOneWidget);
    expect(find.text('Принять с телефона'), findsOneWidget);
    await t.tap(find.text('Передать на ТВ'));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(PairSendPage), findsOneWidget);
  });

  for (final (name, size) in [
    ('phone360', const Size(360, 780)),
    ('phone411', const Size(411, 860)),
  ]) {
    testWidgets('send manual $name: validation, payload, success', (t) async {
      final api = MockApi();
      final c = await _app(t, size, api: api, fs: '1.30');
      await _push(t, PairSendPage(c: c, camera: () async => true));
      dumpOverflow(t);
      expect(t.takeException(), isNull);
      expect(find.text('Сканировать QR-код'), findsOneWidget);
      final send = find.widgetWithText(PairBtn, 'Отправить');
      expect(t.widget<PairBtn>(send).onTap, isNull); // nothing entered yet
      await t.enterText(find.byType(TextField).at(0), '192.168.1.23:41234');
      await t.enterText(find.byType(TextField).at(1), '482913');
      await t.pump();
      expect(t.widget<PairBtn>(send).onTap, isNotNull);
      await t.ensureVisible(send);
      await t.tap(send);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(api.pairSent![0], '192.168.1.23:41234');
      expect(api.pairSent![1], '482913');
      final o = api.pairSent![2] as Map;
      expect(o['subIds'], isNull); // all subscriptions by default
      expect(o['selected'], isTrue);
      expect(o['settings'], isFalse);
      expect(find.text('Отправлено на ТВ'), findsOneWidget);
      expect(find.text('Получено: 2 подписки, 9 серверов'), findsOneWidget);
    });
  }

  testWidgets('send: scanned QR, unreachable TV shows Wi‑Fi hint', (t) async {
    final api = MockApi();
    final c = await _app(t, const Size(411, 860), api: api);
    await _push(
      t,
      PairSendPage(
        c: c,
        camera: () async => true,
        scan: () async =>
            'nox://pair?h=10.9.9.9:41234&t=AAAAAAAAAAAAAAAAAAAAAA',
      ),
    );
    await t.tap(find.text('Сканировать QR-код'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('ТВ: 10.9.9.9:41234'), findsOneWidget);
    expect(find.byType(TextField), findsNothing); // no manual fields with a QR
    final send = find.widgetWithText(PairBtn, 'Отправить');
    await t.ensureVisible(send);
    await t.tap(send);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('ТВ не отвечает'), findsOneWidget);
    expect(api.pairSent![1], '');
  });

  testWidgets('send: camera denied → manual hint; non-Nox QR rejected', (
    t,
  ) async {
    final c = await _app(t, const Size(411, 860));
    var r = 'error:denied';
    await _push(
      t,
      PairSendPage(c: c, camera: () async => true, scan: () async => r),
    );
    await t.tap(find.text('Сканировать QR-код'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Нет доступа к камере'), findsOneWidget);
    r = 'https://example.com';
    await t.tap(find.text('Сканировать QR-код'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Это не QR-код Nox'), findsOneWidget);
  });

  testWidgets('send: unticking a subscription sends only the rest', (t) async {
    final api = MockApi();
    final c = await _app(t, const Size(411, 860), api: api);
    await _push(t, PairSendPage(c: c, uri: 'nox://pair?h=192.168.1.5:1&t=x'));
    final first = '${c.subs.first['name']}';
    await t.tap(find.text(first).last);
    await t.pump();
    final send = find.widgetWithText(PairBtn, 'Отправить');
    // nothing left to send → disabled; settings alone are enough
    final m =
        t.widget<PairBtn>(send).onTap == null ||
        c.servers.any((s) => (s['subId'] ?? '') == '');
    expect(m, isTrue);
    await t.tap(find.text('Настройки'));
    await t.pump();
    await t.ensureVisible(send);
    await t.tap(send);
    await t.pump(const Duration(milliseconds: 300));
    final ids = (api.pairSent![2] as Map)['subIds'] as List?;
    expect(ids, isNotNull);
    expect(ids!.contains(c.subs.first['id']), isFalse);
  });
}
