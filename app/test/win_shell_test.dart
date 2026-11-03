// 2.4.0 Windows «design A»: left navigation pane, timer card + graph, current server,
// subscription card with a ping check, quick settings, ad-block card and page.
// Screenshots go to test/shots/240-win-*.png (the real 69 servers of the user).
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
    return r.passed || r.diffPercent < 0.01;
  }
}

Future<(NoxController, MockApi)> _app(
  WidgetTester t,
  Size size, {
  String status = 'connected',
  bool packaged = false,
  int tab = 0,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  desktopUi = true;
  noTopBar = true;
  showProto = false;
  rawNames = true;
  debugTitleBar = true;
  winShellForce = true;
  NoxController.mtsAnyOs = true;
  NoxController.forceAccordion = false;
  winTab.value = tab;
  winNavOpen.value = true;
  addTearDown(() {
    desktopUi = false;
    noTopBar = false;
    showProto = true;
    rawNames = false;
    debugTitleBar = false;
    winShellForce = false;
    NoxController.mtsAnyOs = false;
    winTab.value = 0;
  });
  final api = MockApi();
  api.settings['theme'] = 'dark';
  api.settings['blockAds'] = true;
  for (final k in [
    'adsYandex',
    'adsRutube',
    'adsMailVk',
    'adsGoogle',
    'adsOther',
  ]) {
    api.settings[k] = true;
  }
  api.settings['adsAllow'] = ['ads.example.org'];
  api.status = status;
  api.packaged = packaged;
  api.ads = {
    'session': 1284,
    'total': 20417,
    'bySrc': {
      'yandex': 612,
      'rutube': 147,
      'mailvk': 203,
      'google': 288,
      'other': 34,
    },
  };
  api.update = {'versionName': '2.4.1', 'notes': ''};
  api.version = '2.4.0';
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
  // the launch offer dialog (non-MSIX) — dismiss, the nav banner stays
  if (find.text('Позже').evaluate().isNotEmpty) {
    await t.tap(find.text('Позже'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }
  return (c, api);
}

void main() {
  goldenFileComparator = _Tolerant(
    (goldenFileComparator as LocalFileComparator).basedir.resolve(
      'win_shell_test.dart',
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

  void noErr(WidgetTester t) {
    final e = t.takeException();
    if (e != null) dumpOverflow(t);
    expect(e, isNull);
  }

  void noFakeProto() {
    for (final w in ['Reality', 'Shadowsocks']) {
      expect(find.textContaining(w), findsNothing, reason: '$w shown');
    }
  }

  for (final (name, size) in [
    ('home', const Size(1280, 800)),
    ('home-narrow', const Size(820, 760)),
  ]) {
    testWidgets('win $name', (t) async {
      final (c, _) = await _app(t, size);
      expect(find.byKey(const Key('mica')), findsOneWidget);
      expect(find.text('2.4.0'), findsOneWidget);
      expect(find.byKey(const Key('win-update')), findsOneWidget);
      expect(find.text('Доступно обновление 2.4.1'), findsOneWidget);
      expect(find.text('Главная'), findsWidgets);
      expect(find.byKey(const Key('win-connect')), findsOneWidget);
      expect(find.text('Время подключения'), findsOneWidget);
      expect(find.byKey(TourKeys.power), findsOneWidget);
      expect(find.byKey(const Key('win-graph')), findsOneWidget);
      expect(find.byKey(const Key('win-current')), findsOneWidget);
      expect(find.byKey(TourKeys.sub), findsOneWidget);
      await t.scrollUntilVisible(
        find.byKey(const Key('win-ads')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.byKey(const Key('win-mts')), findsOneWidget);
      expect(find.byKey(const Key('win-anti')), findsOneWidget);
      expect(find.textContaining('1\u202F284'), findsOneWidget);
      for (final v in ['Яндекс', 'Rutube', 'Mail.ru / VK', 'Google']) {
        expect(find.text(v), findsOneWidget);
      }
      // the current server shows its real protocol
      final cur = c.current!;
      expect(find.textContaining(NoxController.proto(cur)), findsWidgets);
      noFakeProto();
      noErr(t);
      await t.drag(find.byType(Scrollable).last, const Offset(0, 3000));
      await t.pump(const Duration(milliseconds: 60));
      await expectLater(
        find.byType(NoxApp),
        matchesGoldenFile('shots/240-win-$name.png'),
      );
    });
  }

  testWidgets('win ads page: counter, sources, allow-list', (t) async {
    final (_, api) = await _app(t, const Size(1280, 800), tab: 3);
    expect(find.text('Белый список'), findsOneWidget);
    expect(find.text('ads.example.org'), findsOneWidget);
    noErr(t);
    await expectLater(
      find.byType(NoxApp),
      matchesGoldenFile('shots/240-win-ads.png'),
    );
    // vendor switch saves the setting
    await t.tap(find.byKey(const Key('win-adp-adsRutube')));
    await t.pump(const Duration(milliseconds: 100));
    expect(api.settings['adsRutube'], isFalse);
    // allow-list: normalized, invalid rejected
    await t.scrollUntilVisible(
      find.byKey(const Key('allow-add')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.drag(find.byType(Scrollable).last, const Offset(0, -300));
    await t.pump();
    await t.enterText(
      find.byKey(const Key('allow-input')),
      'https://*.Mc.Yandex.ru/watch',
    );
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump(const Duration(milliseconds: 100));
    expect(api.settings['adsAllow'], ['ads.example.org', 'mc.yandex.ru']);
    await t.enterText(find.byKey(const Key('allow-input')), 'not a domain');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Введите домен'), findsOneWidget);
    // reset counter
    await t.scrollUntilVisible(
      find.byKey(const Key('win-ads-reset')),
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.byKey(const Key('win-ads-reset')));
    await t.pump(const Duration(milliseconds: 100));
    expect(api.adResets, 1);
    noErr(t);
  });

  testWidgets('win servers page + search', (t) async {
    await _app(t, const Size(1280, 800), tab: 1);
    expect(find.byKey(const Key('win-title-Серверы')), findsOneWidget);
    noFakeProto();
    noErr(t);
    await expectLater(
      find.byType(NoxApp),
      matchesGoldenFile('shots/240-win-servers.png'),
    );
    await t.enterText(find.byKey(const Key('win-search')), 'zzzz-none');
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Поиск «zzzz-none»: 0'), findsOneWidget);
    await t.enterText(find.byKey(const Key('win-search')), '');
    await t.pump(const Duration(milliseconds: 100));
    noErr(t);
  });

  testWidgets('win subs + settings pages, back to the old layout and again', (
    t,
  ) async {
    final (c, _) = await _app(t, const Size(1280, 800), tab: 2);
    expect(find.byKey(const Key('win-title-Подписки')), findsOneWidget);
    noErr(t);
    winTab.value = 4;
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('win-title-Настройки')), findsOneWidget);
    noErr(t);
    await t.scrollUntilVisible(
      find.text('Новый интерфейс Windows'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text('Новый интерфейс Windows'));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
    expect(c.flag('winUi', true), isFalse);
    expect(find.byKey(const Key('mica')), findsNothing);
    noErr(t);
  });

  testWidgets('win narrow window folds the nav; hamburger toggles it', (
    t,
  ) async {
    await _app(t, const Size(1000, 760));
    expect(find.byKey(const Key('win-search')), findsOneWidget);
    await t.tap(find.byKey(const Key('win-hamburger')));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('win-search')), findsNothing);
    expect(find.byKey(const Key('win-nav-search')), findsOneWidget);
    noErr(t);
  });

  testWidgets('MSIX: update banner says App Installer, tap shows the dialog', (
    t,
  ) async {
    await _app(t, const Size(1280, 800), packaged: true);
    expect(find.textContaining('App Installer'), findsWidgets);
    await t.tap(find.byKey(const Key('win-update')));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('msix-update')), findsOneWidget);
    noErr(t);
  });

  testWidgets('quick ad vendor switch on the home card', (t) async {
    final (_, api) = await _app(t, const Size(1280, 800));
    await t.tap(find.byKey(const Key('win-ad-adsGoogle')));
    await t.pump(const Duration(milliseconds: 100));
    expect(api.settings['adsGoogle'], isFalse);
    noErr(t);
  });
}
