// 2.1.7: «Таймер» card pill is a tap toggle (the 2.1.x swipe slider was too sensitive):
// tap = connect, tap again = disconnect, tap while «Подключение…» cancels;
// 2.2.0: the knob can also be dragged (fires past 60%, snaps back otherwise);
// fast double taps are debounced. Every action hits the same engine calls as the power knob.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Rect knob(WidgetTester t) => t.getRect(
    find
        .descendant(
          of: find.byKey(const Key('pill-knob')),
          matching: find.byType(Container),
        )
        .first,
  );

  testWidgets('drag the knob past 60% → connects, with haptic feedback', (
    t,
  ) async {
    final haptics = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (m) async {
        if (m.method == 'HapticFeedback.vibrate') haptics.add('${m.arguments}');
        return null;
      },
    );
    final (c, api) = await _inList(t, 'disconnected');
    final r = t.getRect(_pill);
    final k0 = knob(t);
    // mid-drag the knob follows the finger
    final g = await t.startGesture(
      Offset(r.left + 26, r.center.dy),
      kind: PointerDeviceKind.touch,
    );
    for (var i = 0; i < 6; i++) {
      await g.moveBy(Offset(r.width * .35 / 6, 0));
      await t.pump(const Duration(milliseconds: 30));
    }
    expect(knob(t).left, greaterThan(k0.left + r.width * .25));
    expect(api.calls, isEmpty);
    for (var i = 0; i < 6; i++) {
      await g.moveBy(Offset(r.width * .35 / 6, 0));
      await t.pump(const Duration(milliseconds: 30));
    }
    await g.up();
    await _settle(t);
    expect(api.calls, ['Connect']);
    expect(c.connected, isTrue);
    expect(haptics, contains('HapticFeedbackType.mediumImpact'));
  });

  testWidgets('drag under 60% snaps back, nothing fires', (t) async {
    final (c, api) = await _inList(t, 'disconnected');
    final r = t.getRect(_pill);
    final k0 = knob(t);
    await _slide(t, Offset(r.left + 26, r.center.dy), Offset(r.width * .4, 0));
    expect(api.calls, isEmpty);
    expect(c.connected, isFalse);
    expect(knob(t).left, closeTo(k0.left, .5));
  });

  testWidgets('short drags (30 px) start a drag but never fire', (t) async {
    final (c, api) = await _inList(t, 'disconnected');
    final r = t.getRect(_pill);
    final k0 = knob(t);
    await _slide(t, Offset(r.left + 26, r.center.dy), const Offset(30, 0));
    await _slide(t, Offset(r.left + 26, r.center.dy), const Offset(30, 4));
    expect(api.calls, isEmpty);
    expect(c.connected, isFalse);
    expect(knob(t).left, closeTo(k0.left, .5));
  });

  testWidgets(
    'connected: drag the knob left past 60% → disconnects; 30% does not',
    (t) async {
      final (c, api) = await _inList(t, 'connected');
      final r = t.getRect(_pill);
      await _slide(
        t,
        Offset(r.right - 26, r.center.dy),
        Offset(-r.width * .3, 0),
      );
      expect(api.calls, isEmpty);
      expect(c.connected, isTrue);
      await _slide(
        t,
        Offset(r.right - 26, r.center.dy),
        Offset(-r.width * .7, 0),
      );
      expect(api.calls, ['Disconnect']);
      expect(c.connected, isFalse);
    },
  );

  testWidgets('connecting: drag back cancels', (t) async {
    final (_, api) = await _inList(t, 'connecting');
    final r = t.getRect(_pill);
    await _slide(
      t,
      Offset(r.right - 26, r.center.dy),
      Offset(-r.width * .7, 0),
    );
    expect(api.calls, ['Disconnect']);
  });

  testWidgets('disconnecting: drags are ignored', (t) async {
    final (_, api) = await _inList(t, 'disconnecting');
    final r = t.getRect(_pill);
    await _slide(
      t,
      Offset(r.right - 26, r.center.dy),
      Offset(-r.width * .7, 0),
    );
    await _slide(t, Offset(r.left + 26, r.center.dy), Offset(r.width * .7, 0));
    expect(api.calls, isEmpty);
  });

  testWidgets('a diagonal, mostly vertical drag scrolls and never connects', (
    t,
  ) async {
    final (_, api) = await _inList(t, 'disconnected');
    final r = t.getRect(_pill);
    await _slide(t, Offset(r.left + 26, r.center.dy), const Offset(60, -320));
    expect(api.calls, isEmpty);
    final s = t.state<ScrollableState>(find.byType(Scrollable).first);
    expect(s.position.pixels, greaterThan(100));
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
