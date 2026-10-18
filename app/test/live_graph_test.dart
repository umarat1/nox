import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox/src/live_graph.dart';
import 'package:nox/src/theme.dart';

void main() {
  test('series appends only new samples by Seq', () {
    final s = SpeedSeries();
    s.feed({
      'Seq': 3,
      'Hist': [
        [1, 10],
        [2, 20],
        [3, 30],
      ],
    });
    expect(s.down, [10, 20, 30]);
    s.feed({
      'Seq': 3,
      'Hist': [
        [1, 10],
        [2, 20],
        [3, 30],
      ],
    });
    expect(s.down.length, 3);
    s.feed({
      'Seq': 5,
      'Hist': [
        [2, 20],
        [3, 30],
        [4, 40],
        [5, 50],
      ],
    });
    expect(s.down, [10, 20, 30, 40, 50]);
    expect(s.at(s.down, 3.5), 45);
    s.feed({
      'Seq': 1,
      'Hist': [
        [9, 90],
      ],
    }); // new session
    expect(s.down, [90]);
  });

  testWidgets('graph renders and keeps animating', (t) async {
    final s = SpeedSeries();
    s.feed({
      'Seq': 30,
      'Hist': [
        for (var i = 0; i < 30; i++) [i * 100, i * 1000],
      ],
    });
    await t.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 200,
          child: LiveGraph(series: s, p: Pal.dark, active: true, labels: true),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(t.binding.hasScheduledFrame, isTrue); // ticker still running
    await t.pumpWidget(const SizedBox());
  });
}
