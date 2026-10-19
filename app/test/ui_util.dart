import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Prints every RenderFlex whose children exceed its main axis (for overflow failures).
void dumpOverflow(WidgetTester t) {
  void visit(RenderObject o) {
    if (o is RenderFlex && o.hasSize) {
      var sum = 0.0;
      o.visitChildren((ch) {
        final b = ch as RenderBox;
        if (b.hasSize)
          sum += o.direction == Axis.horizontal ? b.size.width : b.size.height;
      });
      final m = o.direction == Axis.horizontal ? o.size.width : o.size.height;
      if (sum > m + .5)
        debugPrint(
          'OVERFLOW ${(sum - m).toStringAsFixed(1)}: ${o.debugCreator}',
        );
    }
    o.visitChildren(visit);
  }

  visit(t.binding.rootElement!.renderObject!);
}
