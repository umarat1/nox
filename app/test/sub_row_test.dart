import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/mock.dart';

/// Compact subscription row: the expiry label must never be ellipsized
/// (360dp phone, font 85–130%, UI scale 80–130%), and font scale must apply.
import 'dart:io';
import 'package:flutter/services.dart';

Future<void> _loadFonts() async {
  final root =
      Platform.environment['FLUTTER_ROOT'] ?? '/workspace/tools/flutter';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in ['Regular', 'Medium', 'Bold']) {
    final b = File('$dir/Roboto-$f.ttf').readAsBytesSync();
    roboto.addFont(Future.value(ByteData.view(b.buffer)));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.view(
          File('$dir/MaterialIcons-Regular.otf').readAsBytesSync().buffer,
        ),
      ),
    );
  await icons.load();
}

void main() {
  setUpAll(_loadFonts);
  for (final w in [360.0, 411.0]) {
    for (final fs in ['0.85', '1.00', '1.30']) {
      for (final us in ['0.80', '1.00', '1.30']) {
        testWidgets('sub row w=$w font=$fs ui=$us', (t) async {
          t.view.physicalSize = Size(w * 3, 2400);
          t.view.devicePixelRatio = 3;
          addTearDown(t.view.reset);
          final api = MockApi();
          for (final b in api.subs) b['expire'] = 0; // «Бессрочно»
          final c = NoxController(api);
          await c.refresh();
          c.setPrefLive('fontScale', fs);
          c.setPrefLive('uiScale', us);
          await t.pumpWidget(NoxApp(c: c));
          await t.pump();
          final f = find.text('Бессрочно');
          expect(f, findsWidgets);
          final ro = t.renderObject<RenderParagraph>(f.first);
          expect(ro.didExceedMaxLines, isFalse);
          final size = ro.size.width;
          final need = ro.getMaxIntrinsicWidth(double.infinity);
          expect(size + 0.5 >= need, isTrue, reason: 'truncated $size < $need');
          expect(
            MediaQuery.textScalerOf(t.element(f.first)).scale(10),
            closeTo(10 * double.parse(fs), 0.01),
          );
          final e = t.takeException();
          if (e != null) _dumpOverflow(t);
          expect(e, isNull);
        });
      }
    }
  }

  testWidgets('font scale applies when changed live', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final api = MockApi();
    for (final b in api.subs) b['expire'] = 0;
    final c = NoxController(api);
    await c.refresh();
    await t.pumpWidget(NoxApp(c: c));
    await t.pump();
    final h0 = t.getSize(find.text('Бессрочно').first).height;
    c.setPrefLive('fontScale', '1.30');
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final h1 = t.getSize(find.text('Бессрочно').first).height;
    expect(h1, greaterThan(h0 * 1.2), reason: 'h0=$h0 h1=$h1');
    await c.refresh(); // engine round-trip keeps it
    await t.pump();
    expect(t.getSize(find.text('Бессрочно').first).height, closeTo(h1, .5));
  });
}

void _dumpOverflow(WidgetTester t) {
  void visit(RenderObject o) {
    if (o is RenderFlex && o.hasSize) {
      var sum = 0.0;
      o.visitChildren((ch) {
        final b = ch as RenderBox;
        sum += o.direction == Axis.horizontal ? b.size.width : b.size.height;
      });
      final main = o.direction == Axis.horizontal
          ? o.size.width
          : o.size.height;
      if (sum > main + .5) {
        debugPrint('OVERFLOW ${sum - main}: ${o.debugCreator}');
      }
    }
    o.visitChildren(visit);
  }

  visit(t.binding.rootElement!.renderObject!);
}
