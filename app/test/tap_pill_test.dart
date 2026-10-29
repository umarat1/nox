// 2.1.7: «Таймер» card pill is a tap toggle (the 2.1.x swipe slider was too sensitive):
// tap = connect, tap again = disconnect, tap while «Подключение…» cancels; swipes do nothing;
// fast double taps are debounced. Every action hits the same engine calls as the power knob.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/home.dart';
import 'package:nox/src/mock.dart';
import 'package:nox/src/pair.dart';
import 'package:nox/src/theme.dart';
import 'package:nox/src/tour.dart';

import 'real_servers.dart';

class _Api extends MockApi {
  final calls = <String>[];
  @override
  Future<dynamic> call(String m, [List<dynamic> a = const []]) {
    if (m == 'Connect' || m == 'Disconnect') calls.add(m);
    return super.call(m, a);
  }
}

Future<(NoxController, _Api)> _app(WidgetTester t, String status) async {
  t.view.physicalSize = const Size(411, 860) * 2.625;
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  NoxController.forceAccordion = true;
  heroStyle = 'timer';
  final api = _Api();
  api.settings['theme'] = 'dark';
  api.status = status;
  api.servers
    ..clear()
    ..addAll(realServers());
  api.selected = 'm3';
  final c = NoxController(api);
  await c.refresh();
  PairGlue.suggested = true;
  await t.pumpWidget(NoxApp(c: c));
  await _settle(t);
  return (c, api);
}

Future<(NoxController, _Api)> _inList(WidgetTester t, String status) async {
  t.view.physicalSize = const Size(411, 860) * 2.625;
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  final api = _Api()..status = status;
  final c = NoxController(api);
  await c.refresh();
  final p = Pal.of('dark');
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: c,
          builder: (_, _) => ListView(
            children: [
              const SizedBox(height: 260),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TapPill(c: c, p: p),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    ),
  );
  await _settle(t);
  return (c, api);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

Finder get _pill => find.byKey(TourKeys.power);
String _label(WidgetTester t) =>
    t.widget<Text>(find.byKey(const Key('pill-label'))).textSpan!.toPlainText();

Future<void> _slide(WidgetTester t, Offset from, Offset by) async {
  final g = await t.startGesture(from, kind: PointerDeviceKind.touch);
  for (var i = 0; i < 12; i++) {
    await g.moveBy(by / 12);
    await t.pump(const Duration(milliseconds: 40));
  }
  await g.up();
  await _settle(t);
}

void main() {
  setUp(() => TapPill.debounce = Duration.zero);
  tearDown(() {
    NoxController.forceAccordion = false;
    heroStyle = 'timer';
    TapPill.debounce = const Duration(milliseconds: 700);
  });

  testWidgets('home: the «Таймер» card shows the tap pill, no swipe hints', (
    t,
  ) async {
    await _app(t, 'disconnected');
    expect(find.byType(TapPill), findsOneWidget);
    expect(_label(t), 'Отключено\nнажмите, чтобы подключить');
    expect(find.textContaining('Свайп'), findsNothing);
  });

  testWidgets('tap connects, tap again disconnects', (t) async {
    final (c, api) = await _app(t, 'disconnected');
    await t.tap(_pill);
    await _settle(t);
    expect(api.calls, ['Connect']);
    expect(c.connected, isTrue);
    expect(_label(t), 'Подключено\nнажмите, чтобы отключить');
    await t.tap(_pill);
    await _settle(t);
    expect(api.calls, ['Connect', 'Disconnect']);
    expect(c.connected, isFalse);
  });

  testWidgets('connecting: tap cancels; label says Подключение…', (t) async {
    final (_, api) = await _app(t, 'connecting');
    expect(_label(t), 'Подключение…\nнажмите — отмена');
    await t.tap(_pill);
    await _settle(t);
    expect(api.calls, ['Disconnect']);
  });

  testWidgets('disconnecting: taps are ignored', (t) async {
    final (_, api) = await _app(t, 'disconnecting');
    expect(_label(t), 'Отключение…');
    await t.tap(_pill);
    await _settle(t);
    expect(api.calls, isEmpty);
  });

  testWidgets('swipes do nothing (no accidental connect/disconnect)', (
    t,
  ) async {
    final (c, api) = await _inList(t, 'disconnected');
    final w = t.getSize(_pill).width;
    final r = t.getRect(_pill);
    await _slide(t, Offset(r.left + 26, r.center.dy), Offset(w * .7, 0));
    await _slide(t, Offset(r.right - 26, r.center.dy), Offset(-w * .7, 0));
    expect(api.calls, isEmpty);
    expect(c.connected, isFalse);
  });

  testWidgets('the list scrolls when dragged over the pill vertically', (
    t,
  ) async {
    final (_, api) = await _inList(t, 'disconnected');
    await t.drag(_pill, const Offset(0, -300));
    await _settle(t);
    final s = t.state<ScrollableState>(find.byType(Scrollable).first);
    expect(s.position.pixels, greaterThan(100));
    expect(api.calls, isEmpty);
  });

  testWidgets('double tap is debounced', (t) async {
    TapPill.debounce = const Duration(seconds: 2);
    final (_, api) = await _inList(t, 'disconnected');
    await t.tap(_pill);
    await t.pump(const Duration(milliseconds: 80));
    await t.tap(_pill);
    await _settle(t);
    expect(api.calls, ['Connect']);
  });
}
