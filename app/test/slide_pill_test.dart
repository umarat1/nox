// 2.1.6: «Таймер» card slide pill — swipe right connects, swipe left disconnects,
// a tap on the knob or anywhere on the pill toggles; works inside the scrolling home list.
// Every action must hit the same engine calls as the round power knob (Connect/Disconnect).
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

/// The pill inside a long vertical ListView (home list / small-screen scroll layouts).
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
                child: SlidePill(c: c, p: p),
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

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

Finder get _pill => find.byKey(TourKeys.power);

Offset _knob(WidgetTester t, {required bool right}) {
  final r = t.getRect(_pill);
  return Offset(right ? r.right - 5 - 21 : r.left + 5 + 21, r.center.dy);
}

/// A slow, deliberate slide that stops before the finger lifts (velocity ≈ 0) —
/// what a real thumb does and what 2.1.5 ignored.
Future<void> _slowSlide(WidgetTester t, Offset from, Offset by) async {
  final g = await t.startGesture(from, kind: PointerDeviceKind.touch);
  for (var i = 0; i < 12; i++) {
    await g.moveBy(by / 12);
    await t.pump(const Duration(milliseconds: 40));
  }
  await t.pump(const Duration(milliseconds: 300)); // hold still
  await g.up();
  await _settle(t);
}

double _scroll(WidgetTester t) {
  final s = find.ancestor(of: _pill, matching: find.byType(Scrollable));
  return t.state<ScrollableState>(s.first).position.pixels;
}

void main() {
  setUp(() => slideHints = true); // phone hints (tests run on a desktop host)
  tearDown(() {
    NoxController.forceAccordion = false;
    heroStyle = 'timer';
  });

  testWidgets('home: the «Таймер» card shows the pill', (t) async {
    await _app(t, 'disconnected');
    expect(_pill, findsOneWidget);
    expect(find.byType(SlidePill), findsOneWidget);
  });

  testWidgets('disconnected: slow swipe right connects', (t) async {
    final (c, api) = await _app(t, 'disconnected');
    expect(find.text('Свайп вправо — подключить'), findsOneWidget);
    final w = t.getSize(_pill).width;
    await _slowSlide(t, _knob(t, right: false), Offset(w * .6, 0));
    expect(api.calls, ['Connect']);
    expect(c.connected, isTrue);
    expect(find.text('Свайп влево — отключить'), findsOneWidget);
  });

  testWidgets(
    'disconnected: diagonal swipe right in the list connects, list does not scroll',
    (t) async {
      final (c, api) = await _inList(t, 'disconnected');
      final y0 = _scroll(t);
      final w = t.getSize(_pill).width;
      await _slowSlide(t, _knob(t, right: false), Offset(w * .6, -70));
      expect(api.calls, ['Connect']);
      expect(c.connected, isTrue);
      expect(_scroll(t), y0);
    },
  );

  testWidgets('disconnected: quick flick right connects', (t) async {
    final (_, api) = await _app(t, 'disconnected');
    await t.flingFrom(_knob(t, right: false), const Offset(90, 0), 900);
    await _settle(t);
    expect(api.calls, ['Connect']);
  });

  testWidgets('disconnected: swipe left does nothing', (t) async {
    final (c, api) = await _app(t, 'disconnected');
    await _slowSlide(t, t.getCenter(_pill), const Offset(-150, 0));
    expect(api.calls, isEmpty);
    expect(c.connected, isFalse);
  });

  testWidgets('disconnected: tap on knob connects', (t) async {
    final (c, api) = await _app(t, 'disconnected');
    await t.tapAt(_knob(t, right: false));
    await _settle(t);
    expect(api.calls, ['Connect']);
    expect(c.connected, isTrue);
  });

  testWidgets('disconnected: tap on the pill text connects', (t) async {
    final (_, api) = await _app(t, 'disconnected');
    await t.tap(find.text('Свайп вправо — подключить'));
    await _settle(t);
    expect(api.calls, ['Connect']);
  });

  testWidgets('connected: slow swipe left disconnects', (t) async {
    final (c, api) = await _app(t, 'connected');
    expect(find.text('Свайп влево — отключить'), findsOneWidget);
    final w = t.getSize(_pill).width;
    await _slowSlide(t, _knob(t, right: true), Offset(-w * .6, 0));
    expect(api.calls, ['Disconnect']);
    expect(c.connected, isFalse);
    expect(find.text('Свайп вправо — подключить'), findsOneWidget);
  });

  testWidgets('connected: diagonal swipe left in the list disconnects', (
    t,
  ) async {
    final (_, api) = await _inList(t, 'connected');
    final y0 = _scroll(t);
    final w = t.getSize(_pill).width;
    await _slowSlide(t, _knob(t, right: true), Offset(-w * .6, 60));
    expect(api.calls, ['Disconnect']);
    expect(_scroll(t), y0);
  });

  testWidgets('connected: swipe right does nothing', (t) async {
    final (c, api) = await _app(t, 'connected');
    await _slowSlide(t, t.getCenter(_pill), const Offset(150, 0));
    expect(api.calls, isEmpty);
    expect(c.connected, isTrue);
  });

  testWidgets('connected: tap on knob / pill disconnects', (t) async {
    final (c, api) = await _app(t, 'connected');
    await t.tapAt(_knob(t, right: true));
    await _settle(t);
    expect(api.calls, ['Disconnect']);
    expect(c.connected, isFalse);
    await t.tap(_pill);
    await _settle(t);
    expect(api.calls, ['Disconnect', 'Connect']);
  });

  testWidgets('connecting: hint, swipe right ignored, swipe left cancels', (
    t,
  ) async {
    final (_, api) = await _app(t, 'connecting');
    expect(find.text('Подключение… влево — отмена'), findsOneWidget);
    await _slowSlide(t, t.getCenter(_pill), const Offset(150, 0));
    expect(api.calls, isEmpty);
    final w = t.getSize(_pill).width;
    await _slowSlide(t, _knob(t, right: true), Offset(-w * .6, 0));
    expect(api.calls, ['Disconnect']);
  });

  testWidgets('a short slide that does not pass the threshold snaps back', (
    t,
  ) async {
    final (c, api) = await _app(t, 'disconnected');
    await _slowSlide(t, _knob(t, right: false), const Offset(40, 0));
    expect(api.calls, isEmpty);
    expect(c.connected, isFalse);
  });

  testWidgets('home: diagonal slow swipe right connects', (t) async {
    final (_, api) = await _app(t, 'disconnected');
    final w = t.getSize(_pill).width;
    await _slowSlide(t, _knob(t, right: false), Offset(w * .6, 50));
    expect(api.calls, ['Connect']);
  });

  testWidgets('list: tap on knob connects, tap on pill disconnects', (t) async {
    final (c, api) = await _inList(t, 'disconnected');
    final y0 = _scroll(t);
    await t.tapAt(_knob(t, right: false));
    await _settle(t);
    expect(api.calls, ['Connect']);
    expect(c.connected, isTrue);
    expect(find.text('Свайп влево — отключить'), findsOneWidget);
    await t.tap(_pill);
    await _settle(t);
    expect(api.calls, ['Connect', 'Disconnect']);
    expect(_scroll(t), y0);
  });

  testWidgets('list: the list still scrolls when dragged outside the pill', (
    t,
  ) async {
    final (_, api) = await _inList(t, 'disconnected');
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await _settle(t);
    expect(_scroll(t), greaterThan(100));
    expect(api.calls, isEmpty);
  });

  testWidgets('desktop hints: tap toggles', (t) async {
    slideHints = false;
    final (_, api) = await _app(t, 'disconnected');
    expect(find.text('Нажмите — подключить'), findsOneWidget);
    await t.tap(find.text('Нажмите — подключить'));
    await _settle(t);
    expect(api.calls, ['Connect']);
  });
}
