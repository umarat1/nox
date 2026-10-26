import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/fmt.dart';
import 'package:nox/src/mock.dart';
import 'package:nox/src/regions.dart';

void main() {
  test('ping is text only', () {
    expect(pingText(-1), 'таймаут');
    expect(pingText(62), '62 мс');
    expect(pingText(0), '—');
    expect(plural(23, 'день', 'дня', 'дней'), 'дня');
    expect(plural(11, 'день', 'дня', 'дней'), 'дней');
    expect(region('🇬🇧 Лондон 1'), 'GB');
  });

  testWidgets('home renders with mock core', (t) async {
    t.view.physicalSize = const Size(920, 4000);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final c = NoxController(MockApi());
    await c.refresh();
    await t.pumpWidget(NoxApp(c: c));
    await t.pump();
    expect(find.text('ПОДКЛЮЧЕНО'), findsOneWidget);
    expect(find.text('62 мс'), findsWidgets);
    // Phone list is grouped by country (Happ-style sections).
    expect(find.text('Британия · 2'), findsOneWidget);
    expect(find.text('Антиблок · 1'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    // dead server hidden by default; dedup/hideDead logic
    expect(c.visible().any((s) => s['ping'] == -1), isFalse);
  });
}
