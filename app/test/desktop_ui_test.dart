// 2.2.2: Windows/macOS use the mobile UI. Narrow window = the phone column; from 860 dp
// (maximized / fullscreen) two panes: connection card + subscriptions | server accordion.
// No protocol labels on desktop; server names exactly as the subscription gives them.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/home.dart';
import 'package:nox/src/mock.dart';
import 'package:nox/src/pair.dart';
import 'package:nox/src/platform.dart';
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
    return r.passed || r.diffPercent < 0.01;
  }
}

Future<NoxController> _app(
  WidgetTester t,
  Size size, {
  String status = 'connected',
  bool fs = false,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  desktopUi = true;
  noTopBar = true;
  showProto = false;
  rawNames = true;
  debugTitleBar = true;
  NoxController.forceAccordion = false;
  addTearDown(() {
    desktopUi = false;
    noTopBar = false;
    showProto = true;
    rawNames = false;
    debugTitleBar = false;
  });
  fullScreen.value = fs;
  addTearDown(() => fullScreen.value = false);
  final api = MockApi();
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
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
  return c;
}

void main() {
  goldenFileComparator = _Tolerant(
    (goldenFileComparator as LocalFileComparator).basedir.resolve(
      'desktop_ui_test.dart',
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

  void noProto(WidgetTester t) {
    for (final w in ['VLESS', 'Hysteria2', 'Reality', 'Trojan', 'XHTTP']) {
      final hits = find.byWidgetPredicate((x) {
        if (x is! Text) return false;
        final d = x.data ?? x.textSpan?.toPlainText() ?? '';
        // a protocol word inside a server name is the name itself, not a label
        return d.contains(w) &&
            !realServers().any((s) => '${s['name']}'.contains(d));
      });
      expect(hits, findsNothing, reason: '$w label shown');
    }
  }

  for (final (name, size, fs) in [
    ('normal', const Size(460, 860), false),
    ('wide', const Size(1280, 800), false),
    ('fullscreen', const Size(1920, 1080), true),
  ]) {
    for (final st in ['connected', 'disconnected']) {
      testWidgets('desktop $name — $st', (t) async {
        final c = await _app(t, size, status: st, fs: fs);
        expect(c.accordion, isTrue);
        expect(find.text('nox'), findsNothing); // no top bar
        expect(find.byKey(const Key('hero-corner')), findsOneWidget);
        expect(find.byKey(const Key('corner-fullscreen')), findsOneWidget);
        expect(find.byKey(TourKeys.settings), findsOneWidget);
        expect(find.byKey(TourKeys.mail), findsOneWidget);
        expect(find.text('МТС'), findsNothing);
        expect(find.byKey(TourKeys.theme), findsNothing);
        expect(
          find.byKey(const Key('win-title-bar')),
          fs ? findsNothing : findsOneWidget,
        );
        expect(find.byTooltip('Свернуть подписку'), findsOneWidget);
        noProto(t);
        final e = t.takeException();
        if (e != null) dumpOverflow(t);
        expect(e, isNull);
        await expectLater(
          find.byType(NoxApp),
          matchesGoldenFile('shots/222-desktop-$name-$st.png'),
        );
      });
    }
  }

  testWidgets('wide: two panes, bottom bar under the left one', (t) async {
    await _app(t, const Size(1280, 800));
    final hero = t.getRect(find.byKey(const Key('hero-corner')));
    final bar = t.getRect(find.byKey(const Key('bottom-bar')));
    expect(hero.right, lessThan(600));
    expect(bar.right, lessThan(620));
    expect(
      find.byTooltip('Меню списка').evaluate().isNotEmpty ||
          find.byTooltip('Сервер и список').evaluate().isNotEmpty,
      isTrue,
    );
    // a country card on the right pane
    final cc = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('cc-'),
    );
    expect(cc, findsWidgets);
    expect(t.getRect(cc.first).left, greaterThan(500));
  });

  testWidgets('server names are shown exactly as given', (t) async {
    await _app(t, const Size(1280, 800));
    final raw = realServers().map((s) => '${s['name']}').toSet();
    final shown = find.byWidgetPredicate(
      (w) => w is Text && raw.contains(w.data),
    );
    expect(shown, findsWidgets);
  });

  testWidgets('fullscreen: no title bar, exit button in the corner', (t) async {
    await _app(t, const Size(1920, 1080), fs: true);
    expect(find.byKey(const Key('win-title-bar')), findsNothing);
    expect(
      find.byTooltip('Выйти из полноэкранного режима (F11 / Esc)'),
      findsOneWidget,
    );
  });
}
