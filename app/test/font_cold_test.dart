import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/main.dart';
import 'package:nox/src/controller.dart';
import 'package:nox/src/mock.dart';

void main() {
  testWidgets('saved font scale applies on cold start', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final api = MockApi();
    (api.settings['ui'] as Map)['fontScale'] = '1.30';
    final c = NoxController(api);
    await t.pumpWidget(NoxApp(c: c)); // like main(): runApp before state loads
    await c.refresh();
    await t.pump();
    final el = t.element(find.text('Все', skipOffstage: false).first);
    expect(MediaQuery.textScalerOf(el).scale(10), closeTo(13, .01));
  });
}
