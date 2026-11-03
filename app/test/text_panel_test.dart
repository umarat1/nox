import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/home.dart';
import 'package:nox/src/live_graph.dart';
import 'package:nox/src/mock.dart';
import 'package:nox/src/theme.dart';

void main() {
  testWidgets('text template is plain status, no speed graph', (t) async {
    t.view.physicalSize = const Size(412 * 2, 1400 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final c = NoxController(MockApi());
    await c.refresh();
    await t.pumpWidget(NoxApp(c: c));
    await t.pump();
    expect(c.pref('panel', ''), '');
    expect(find.byType(LiveGraph), findsOneWidget);
    expect(find.text('Подключено'), findsNothing);

    c.setPrefLive('panel', 'text');
    await t.pump();
    expect(find.byType(LiveGraph), findsNothing);
    expect(find.text('Подключено'), findsOneWidget);
    expect(find.text('Сервер: Лондон 1'), findsOneWidget);
    expect(find.text('Страна: Британия'), findsOneWidget);
    expect(find.text('Пинг: 62 мс'), findsOneWidget);
    expect(find.text('Протокол: VLESS Reality'), findsOneWidget);
    expect(find.textContaining('Скорость:'), findsOneWidget);
    expect(find.textContaining('Трафик:'), findsOneWidget);
    expect(find.text('Отключить'), findsOneWidget);
    expect(
      find.textContaining('Лондон 1 · Британия · VLESS Reality'),
      findsOneWidget,
    );
    expect(find.text('62 мс'), findsWidgets);

    final ctx = t.element(find.byType(Scaffold).first);
    settingsSheet(ctx, c, Pal.black);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Внешний вид'), findsOneWidget);
    expect(find.text('Шаблон'), findsOneWidget);
    expect(find.text('Текстовый'), findsWidgets);

    c.setPrefLive('panel', '');
    Navigator.of(ctx).pop();
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(LiveGraph), findsOneWidget);
    expect(c.pref('panel', ''), '');
  });
}
