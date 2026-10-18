import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'fmt.dart';
import 'platform.dart';
import 'theme.dart';

const _upColor = Color(0xFF3FC6E8);

/// Per-second speed samples from the engine, kept across rebuilds (lives in the controller).
/// Samples are addressed by their absolute index in the session (`Seq` from GetTraffic),
/// so the graph knows exactly how many new ones arrived and can scroll by that much.
class SpeedSeries {
  static const keep = 200;
  final up = <double>[], down = <double>[];
  int base = 0; // absolute index of up[0]
  int get seq => base + up.length; // absolute index of the next sample
  int arrivedUs = 0; // monotonic µs when the newest sample arrived
  double intervalMs = 1000; // smoothed gap between samples
  final _clock = Stopwatch()..start();
  int get nowUs => _clock.elapsedMicroseconds;

  void reset() {
    up.clear();
    down.clear();
    base = 0;
    arrivedUs = 0;
  }

  void feed(Map<String, dynamic>? t) {
    if (t == null) return reset();
    final hist = (t['Hist'] as List?) ?? const [];
    final s = (t['Seq'] as num?)?.toInt() ?? hist.length;
    if (s < seq || (up.isEmpty && s > 0)) {
      // new session (or first look): take the whole window as-is
      reset();
      base = s - hist.length;
      for (final e in hist) {
        up.add(((e as List)[0] as num).toDouble());
        down.add((e[1] as num).toDouble());
      }
      arrivedUs = nowUs;
      return;
    }
    final n = math.min(s - seq, hist.length);
    if (n <= 0) return;
    for (final e in hist.sublist(hist.length - n)) {
      up.add(((e as List)[0] as num).toDouble());
      down.add((e[1] as num).toDouble());
    }
    base = s - up.length;
    final now = nowUs;
    if (arrivedUs > 0) {
      final gap = ((now - arrivedUs) / 1000 / n).clamp(250.0, 3000.0);
      intervalMs += (gap - intervalMs) * .3;
    }
    arrivedUs = now;
    if (up.length > keep) {
      final cut = up.length - keep;
      up.removeRange(0, cut);
      down.removeRange(0, cut);
      base += cut;
    }
  }

  /// Linear value at a fractional absolute index (clamped to the known range).
  double at(List<double> v, double i) {
    if (v.isEmpty) return 0;
    final r = (i - base).clamp(0.0, v.length - 1.0);
    final a = r.floor(), b = math.min(a + 1, v.length - 1);
    return v[a] + (v[b] - v[a]) * (r - a);
  }
}

/// Smoothly scrolling speed graph: a Ticker drives a fractional "head" position that glides
/// between engine samples, the curve is a Catmull-Rom spline and the scale eases in/out.
/// Only this widget's layer repaints (RepaintBoundary + CustomPaint(repaint:)); the ticker
/// stops when the window is hidden, minimized or in the tray, and when nothing is connected.
class LiveGraph extends StatefulWidget {
  final SpeedSeries series;
  final Pal p;
  final bool active;
  final int span; // samples across the width
  final bool labels;
  const LiveGraph({
    super.key,
    required this.series,
    required this.p,
    required this.active,
    this.span = 60,
    this.labels = false,
  });
  @override
  State<LiveGraph> createState() => _LiveGraphState();
}

class _LiveGraphState extends State<LiveGraph>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _frame = ValueNotifier<int>(0);
  Duration _last = Duration.zero;
  double pos = -1, mx = 0, curUp = 0, curDown = 0;

  @override
  void initState() {
    super.initState();
    windowShown.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(LiveGraph o) {
    super.didUpdateWidget(o);
    _sync();
  }

  void _sync() {
    final run = widget.active && windowShown.value;
    if (run && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
      return;
    }
    if (!run) {
      if (_ticker.isActive) _ticker.stop();
      // Freeze on the newest sample so a static curve stays visible when
      // «Плавные анимации» is off (or the window is hidden briefly).
      final s = widget.series;
      if (s.up.isNotEmpty) {
        pos = s.seq - 1.0;
        var top = 0.0;
        for (var i = 0; i < s.up.length; i++) {
          top = math.max(top, math.max(s.down[i], s.up[i]));
        }
        mx = math.max(32 * 1024.0, top * 1.18);
        curDown = s.down.last;
        curUp = s.up.last;
      } else {
        pos = -1;
      }
      _frame.value++;
    }
  }

  void _tick(Duration t) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : ((t - _last).inMicroseconds / 1e6).clamp(0.0, .25);
    _last = t;
    final s = widget.series;
    if (s.up.isEmpty) return;
    final newest = s.seq - 1.0;
    final phase = ((s.nowUs - s.arrivedUs) / 1000 / s.intervalMs).clamp(
      0.0,
      1.0,
    );
    // head runs one sample behind the newest one so it always has a target to glide to
    final want = math.max(s.base.toDouble(), newest - 1 + phase);
    if (pos < 0 || (want - pos).abs() > 4) {
      pos = want;
    } else {
      pos += (want - pos) * (1 - math.exp(-dt * 12));
    }
    var top = 0.0;
    final from = (pos - widget.span).floor();
    for (var i = math.max(from, s.base); i <= s.seq - 1; i++) {
      top = math.max(top, math.max(s.at(s.down, i * 1.0), s.at(s.up, i * 1.0)));
    }
    final target = math.max(32 * 1024.0, top * 1.18);
    mx = mx == 0 ? target : mx + (target - mx) * (1 - math.exp(-dt * 3));
    curDown = s.at(s.down, pos);
    curUp = s.at(s.up, pos);
    _frame.value++;
  }

  @override
  void dispose() {
    windowShown.removeListener(_sync);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _LivePainter(this, widget.p, _frame),
      size: Size.infinite,
    ),
  );
}

class _LivePainter extends CustomPainter {
  final _LiveGraphState g;
  final Pal p;
  _LivePainter(this.g, this.p, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final s = g.widget.series;
    final labels = g.widget.labels;
    final w = size.width, h = size.height;
    final top = labels ? 26.0 : 2.0, bottom = h - (labels ? 4 : 2);
    if (labels) {
      final grid = Paint()
        ..color = p.line.withValues(alpha: .6)
        ..strokeWidth = 1;
      for (var k = 0; k <= 3; k++) {
        final y = top + (bottom - top) * k / 3;
        canvas.drawLine(Offset(0, y), Offset(w, y), grid);
      }
    }
    if (g.pos < 0 || s.up.isEmpty || g.mx <= 0) {
      // Idle baseline — keeps the connection-card slot visible before samples arrive.
      final y = bottom - 1;
      canvas.drawLine(
        Offset(0, y),
        Offset(w, y),
        Paint()
          ..color = p.acc.withValues(alpha: .35)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      );
      // Soft accent glow so it reads as a graph, not an empty gap.
      canvas.drawLine(
        Offset(0, y - 3),
        Offset(w * .55, y - 8),
        Paint()
          ..color = p.acc2.withValues(alpha: .45)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
      if (labels) {
        _text(canvas, 'Нет подключения', Offset(0, 0), p.sub, 12.5);
      }
      return;
    }
    final span = g.widget.span;
    final step = w / (span - 1);
    double y(double v) => bottom - (v / g.mx).clamp(0.0, 1.0) * (bottom - top);
    List<Offset> pts(List<double> v) {
      final out = <Offset>[];
      final first = math.max(s.base, (g.pos - span).floor() - 1);
      for (var i = first; i <= s.seq - 1; i++) {
        out.add(Offset(w - (g.pos - i) * step, y(v[i - s.base])));
      }
      return out;
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, w, h));
    final dn = pts(s.down), upP = pts(s.up);
    final dPath = _spline(dn, top, bottom);
    if (dn.length > 1) {
      final fill = Path.from(dPath)
        ..lineTo(dn.last.dx, bottom)
        ..lineTo(dn.first.dx, bottom)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              p.acc.withValues(alpha: labels ? .38 : .30),
              p.acc.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromLTRB(0, top, w, bottom)),
      );
    }
    canvas.drawPath(
      _spline(upP, top, bottom),
      Paint()
        ..color = _upColor.withValues(alpha: .85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = labels ? 1.6 : 1.2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      dPath,
      Paint()
        ..color = p.acc2
        ..style = PaintingStyle.stroke
        ..strokeWidth = labels ? 2.4 : 1.8
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    // live dot at the head
    final hy = y(g.curDown);
    canvas.drawCircle(
      Offset(w - 1.5, hy),
      labels ? 6 : 4,
      Paint()..color = p.acc2.withValues(alpha: .25),
    );
    canvas.drawCircle(
      Offset(w - 1.5, hy),
      labels ? 3 : 2.2,
      Paint()..color = p.acc2,
    );
    canvas.restore();
    if (labels) {
      _text(
        canvas,
        '↓ ${fmtBytes(g.curDown)}/с',
        const Offset(0, 0),
        p.txt,
        13.5,
        bold: true,
      );
      _text(
        canvas,
        '↑ ${fmtBytes(g.curUp)}/с',
        const Offset(120, 0),
        _upColor,
        13.5,
        bold: true,
      );
      _text(
        canvas,
        '${fmtBytes(g.mx)}/с',
        Offset(w, 0),
        p.sub,
        11.5,
        right: true,
      );
    }
  }

  /// Catmull-Rom through the points, as cubic Béziers (control points kept inside the band).
  Path _spline(List<Offset> q, double top, double bottom) {
    final path = Path();
    if (q.isEmpty) return path;
    path.moveTo(q[0].dx, q[0].dy);
    for (var i = 0; i < q.length - 1; i++) {
      final p0 = q[math.max(i - 1, 0)], p1 = q[i], p2 = q[i + 1];
      final p3 = q[math.min(i + 2, q.length - 1)];
      final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(
        c1.dx,
        c1.dy.clamp(top, bottom),
        c2.dx,
        c2.dy.clamp(top, bottom),
        p2.dx,
        p2.dy,
      );
    }
    return path;
  }

  void _text(
    Canvas c,
    String t,
    Offset o,
    Color col,
    double size, {
    bool bold = false,
    bool right = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(
          color: col,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, right ? o.translate(-tp.width, 0) : o);
  }

  @override
  bool shouldRepaint(_LivePainter o) => o.p != p || o.g != g;
}
