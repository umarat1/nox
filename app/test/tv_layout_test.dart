import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/home.dart';
import 'package:nox/src/theme.dart';
import 'package:nox/src/mock.dart';
import 'package:nox/src/pair.dart';

import 'ui_util.dart';

bool _wide(WidgetTester t) {
  Finder f(String type) =>
      find.byWidgetPredicate((w) => w.runtimeType.toString() == type).first;
  // one column: on a short landscape phone the filter bar can sit below the fold (not built)
  if (find
      .byWidgetPredicate((w) => w.runtimeType.toString() == '_FilterBar')
      .evaluate()
      .isEmpty) {
    return false;
  }
  // two panes: the filter bar / server list is to the right of the connect card
  return t.getRect(f('_FilterBar')).left >= t.getRect(f('_Hero')).right;
}

Future<NoxController> _app(
  WidgetTester t,
  Size s, {
  bool tv = false,
  String? us,
}) async {
  t.view.physicalSize = s * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final c = NoxController(MockApi());
  c.isTv = tv;
  await c.refresh();
  if (us != null) c.setPrefLive('uiScale', us);
  PairGlue.suggested = true; // no auto-suggest sheet over the home
  await t.pumpWidget(NoxApp(c: c));
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  return c;
}

void main() {
  setUpAll(loadFonts);
  // A real 1080p Android TV is xhdpi: 960×540 dp.
  for (final us in [null, '1.30', '0.80']) {
    testWidgets('1080p TV (960 dp) uiScale ${us ?? "default"} is two-pane', (
      t,
    ) async {
      await _app(t, const Size(960, 540), tv: true, us: us);
      dumpOverflow(t);
      expect(t.takeException(), isNull);
      expect(_wide(t), isTrue);
    });
  }
  testWidgets('phone landscape 780 dp stays one column', (t) async {
    await _app(t, const Size(780, 360));
    expect(_wide(t), isFalse);
  });
  testWidgets('settings sheet: D-pad focus is visible on TV', (t) async {
    final c = await _app(t, const Size(960, 540), tv: true);
    final ctx = t.element(find.byType(Scaffold).first);
    settingsSheet(ctx, c, Pal.of(c.settings['theme']));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    // a row of the sheet (below the «Режим» item) draws a full accent ring when focused
    bool ring() => find
        .descendant(
          of: find.ancestor(
            of: find.text('Режим'),
            matching: find.byType(SingleChildScrollView),
          ),
          matching: find.byWidgetPredicate((w) {
            final d = w is Container ? w.decoration : null;
            return d is BoxDecoration &&
                d.border is Border &&
                (d.border as Border).isUniform &&
                (d.border as Border).top.width == 2;
          }),
        )
        .evaluate()
        .isNotEmpty;
    for (var i = 0; i < 3 && !ring(); i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(ring(), isTrue);
    expect(t.takeException(), isNull);
  });
}
