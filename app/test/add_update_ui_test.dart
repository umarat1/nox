// 2.1.7: «+» lives at the bottom (round button), an empty list offers «Добавить из буфера»
// (gone once something is added), and a newer build is offered in a dialog with the
// changelog — mandatory below latest.json `minSupported` (no «Позже»).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/mock.dart';
import 'package:nox/src/pair.dart';
import 'package:nox/src/tour.dart';
import 'package:nox/src/update_ui.dart';

class _Api extends MockApi {
  Map<String, dynamic>? update;
  final imported = <String>[];
  final hidden = <String>[];
  @override
  Future<dynamic> call(String m, [List<dynamic> a = const []]) async {
    switch (m) {
      case 'GetState':
        final s = Map<String, dynamic>.from(await super.call(m, a) as Map);
        s['update'] = update;
        return s;
      case 'Import':
        imported.add('${a[0]}');
        servers.add({
          ...Map<String, dynamic>.from(MockApi().servers.first),
          'id': 'imp1',
        });
        return {
          'ok': true,
          'added': 1,
          'errors': [],
          'msg': 'Добавлено серверов: 1',
        };
      case 'HideUpdate':
        hidden.add('${a[0]}');
        update = null;
        return null;
    }
    return super.call(m, a);
  }
}

Future<NoxController> _app(WidgetTester t, _Api api) async {
  t.view.physicalSize = const Size(411, 860) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  PairGlue.suggested = true;
  final c = NoxController(api);
  await c.refresh();
  await t.pumpWidget(NoxApp(c: c));
  await _frames(t);
  return c;
}

Future<void> _frames(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _clipboard(WidgetTester t, String? text) {
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => call.method == 'Clipboard.getData'
        ? (text == null ? null : {'text': text})
        : null,
  );
  addTearDown(
    () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

Finder _inDialog(Finder f) =>
    find.descendant(of: find.byType(UpdateOfferDialog), matching: f);

void main() {
  setUp(resetUpdateOffers);

  testWidgets('«+» is the round button at the bottom and opens the add sheet', (
    t,
  ) async {
    await _app(t, _Api());
    final r = t.getRect(find.byKey(TourKeys.add));
    expect(r.center.dy, greaterThan(860 * .8));
    expect(r.center.dx, greaterThan(411 / 2));
    expect(find.byKey(const Key('clip-add')), findsNothing);
    await t.tap(find.byTooltip('Добавить подписку'));
    await _frames(t);
    expect(find.text('Передать на другое устройство'), findsOneWidget);
  });

  testWidgets('empty list: «Добавить из буфера» imports and disappears', (
    t,
  ) async {
    final api = _Api()
      ..subs.clear()
      ..servers.clear();
    _clipboard(t, '  vless://u@1.2.3.4:443#Test  ');
    await _app(t, api);
    expect(find.text('Добавить из буфера'), findsOneWidget);
    await t.tap(find.byKey(const Key('clip-add')));
    await _frames(t);
    expect(api.imported, ['vless://u@1.2.3.4:443#Test']);
    expect(find.byKey(const Key('clip-add')), findsNothing);
    expect(find.text('Добавлено серверов: 1'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('empty clipboard: a hint, nothing imported, button stays', (
    t,
  ) async {
    final api = _Api()
      ..subs.clear()
      ..servers.clear();
    _clipboard(t, null);
    await _app(t, api);
    await t.tap(find.byKey(const Key('clip-add')));
    await _frames(t);
    expect(api.imported, isEmpty);
    expect(find.textContaining('Буфер обмена пуст'), findsOneWidget);
    expect(find.byKey(const Key('clip-add')), findsOneWidget);
  });

  testWidgets(
    'a newer version is offered once with the changelog; «Позже» hides it',
    (t) async {
      final api = _Api()
        ..update = {
          'versionName': '2.1.7',
          'versionCode': 2170,
          'notes': '• Кнопка «+» внизу\n• Переключатель нажатием',
        };
      await _app(t, api);
      expect(find.byType(UpdateOfferDialog), findsOneWidget);
      expect(_inDialog(find.text('Доступна версия 2.1.7')), findsOneWidget);
      expect(
        _inDialog(find.textContaining('Переключатель нажатием')),
        findsOneWidget,
      );
      await t.tap(_inDialog(find.text('Позже')));
      await _frames(t);
      expect(find.byType(UpdateOfferDialog), findsNothing);
      expect(api.hidden, ['2.1.7']);
    },
  );

  testWidgets('mandatory update: no «Позже», back does not close it', (
    t,
  ) async {
    final api = _Api()
      ..update = {
        'versionName': '2.2.0',
        'versionCode': 2200,
        'notes': 'Важное обновление',
        'mandatory': true,
      };
    await _app(t, api);
    expect(find.byType(UpdateOfferDialog), findsOneWidget);
    expect(_inDialog(find.text('Позже')), findsNothing);
    expect(find.text('Позже'), findsNothing); // banner hides it too
    expect(find.textContaining('больше не поддерживается'), findsOneWidget);
    await t.binding.handlePopRoute();
    await _frames(t);
    await t.tapAt(const Offset(5, 5));
    await _frames(t);
    expect(find.byType(UpdateOfferDialog), findsOneWidget);
    expect(_inDialog(find.text('Обновить')), findsOneWidget);
  });
}
