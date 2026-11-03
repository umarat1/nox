import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'controller.dart';
import 'theme.dart';

/// 2.3.1 liquid glass: frosted backdrop behind a card. With «Размытие» off (or on
/// devices where blur is too slow) the card keeps only its translucent tint.
Widget glassBlurred({required double r, required Widget child}) {
  if (!glassBlur || glassOpacity >= .999) return child;
  return ClipRRect(
    borderRadius: BorderRadius.circular(r),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: child,
    ),
  );
}

/// Soft red ambient light behind the screen so the glass has something to refract.
class GlassAmbient extends StatelessWidget {
  final Pal p;
  const GlassAmbient({super.key, required this.p});
  @override
  Widget build(BuildContext context) {
    final k = (1 - glassOpacity).clamp(0.0, 1.0);
    if (k < .02) return const SizedBox.shrink();
    final a = (p.light ? .18 : .34) * k;
    return IgnorePointer(
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-.9, -.75),
              radius: 1.1,
              colors: [
                p.acc.withValues(alpha: a),
                p.acc.withValues(alpha: 0),
              ],
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(1, .55),
                radius: .9,
                colors: [
                  p.acc2.withValues(alpha: a * .8),
                  p.acc2.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Settings rows: «Прозрачность стекла» slider (live) and «Размытие» switch.
class GlassControls extends StatelessWidget {
  final NoxController c;
  final Pal p;
  const GlassControls({super.key, required this.c, required this.p});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final v = (int.tryParse(c.pref('glassA', '70')) ?? 70).clamp(0, 100);
        final blur = c.pref('glassBlur', '1') == '1';
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
          decoration: BoxDecoration(
            color: p.card.withValues(alpha: glassAlpha()),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Прозрачность стекла',
                      style: TextStyle(
                        color: p.txt,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '$v %',
                    style: TextStyle(
                      color: p.acc2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Slider(
                value: v.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                activeColor: p.acc,
                inactiveColor: p.line,
                label: '$v %',
                // live: the whole app redraws while dragging, saved in the background
                onChanged: (x) => c.setPrefLive('glassA', '${x.round()}'),
              ),
              Text(
                '0 % — прозрачное стекло, 100 % — сплошные карточки',
                style: TextStyle(color: p.sub, fontSize: 12),
              ),
              // own Material: the glass card behind would hide the ink (debug assert)
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: blur,
                  activeThumbColor: Colors.white,
                  activeTrackColor: p.acc,
                  title: Text('Размытие', style: TextStyle(color: p.txt)),
                  subtitle: Text(
                    'Матовое стекло. На слабых телефонах можно выключить',
                    style: TextStyle(color: p.sub, fontSize: 12),
                  ),
                  onChanged: (x) => c.setPrefLive('glassBlur', x ? '1' : '0'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
