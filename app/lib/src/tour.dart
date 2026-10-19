import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Bump when the layout changes enough that everyone (upgraders too) should see the tour again.
const tourVersion = '109';

/// Spotlight targets. Each key sits on exactly one widget (first sub / first server only).
class TourKeys {
  static final add = GlobalKey(debugLabel: 'tour-add');
  static final theme = GlobalKey(debugLabel: 'tour-theme');
  static final mail = GlobalKey(debugLabel: 'tour-mail');
  static final settings = GlobalKey(debugLabel: 'tour-settings');
  static final power = GlobalKey(debugLabel: 'tour-power');
  static final sub = GlobalKey(debugLabel: 'tour-sub');
  static final tabs = GlobalKey(debugLabel: 'tour-tabs');
  static final ping = GlobalKey(debugLabel: 'tour-ping');
  static final refresh = GlobalKey(debugLabel: 'tour-refresh');
  static final more = GlobalKey(debugLabel: 'tour-more');
  static final server = GlobalKey(debugLabel: 'tour-server');
}

class TourStep {
  final GlobalKey key;
  final String title, text;
  final bool circle;
  const TourStep(this.key, this.title, this.text, {this.circle = false});
}

List<TourStep> tourSteps() => [
  TourStep(
    TourKeys.add,
    'Добавить подписку',
    'Вставьте ссылку на подписку или сервер.',
    circle: true,
  ),
  TourStep(TourKeys.theme, 'Тема', 'Тёмная, чёрная или светлая.', circle: true),
  TourStep(
    TourKeys.mail,
    'Обновления и сообщения',
    'Точка на конверте — вышла новая версия.',
    circle: true,
  ),
  TourStep(
    TourKeys.settings,
    'Настройки',
    'Режим, DNS, размер шрифта, масштаб и 60 fps.',
    circle: true,
  ),
  TourStep(
    TourKeys.power,
    'Подключение',
    'Нажмите, чтобы включить или выключить VPN.',
    circle: true,
  ),
  TourStep(
    TourKeys.sub,
    'Подписка',
    'Срок и трафик. ↻ — обновить, ⋮ — действия с подпиской.',
  ),
  TourStep(TourKeys.tabs, 'Фильтры', 'Страны и типы серверов — листайте вбок.'),
  TourStep(
    TourKeys.ping,
    'Пинг',
    'Проверить все серверы списка.',
    circle: true,
  ),
  TourStep(
    TourKeys.refresh,
    'Обновить',
    'Загрузить свежие серверы из подписок.',
    circle: true,
  ),
  TourStep(
    TourKeys.more,
    'Меню списка',
    'Сортировка, вид и счётчик серверов.',
    circle: true,
  ),
  TourStep(
    TourKeys.server,
    'Сервер',
    'Нажмите — выбрать. ⋮ — пинг, конфиг, удалить.',
    circle: true,
  ),
];

/// Dim overlay with a spotlight on the current target and a small tooltip card.
/// Tap / OK / Enter / → = next, ← = back, Back / Esc = skip. Steps whose target is not
/// on screen (no subscription yet, empty list…) are skipped.
class TourOverlay extends StatefulWidget {
  final Pal p;
  final List<TourStep> steps;
  final VoidCallback onDone;
  const TourOverlay({
    super.key,
    required this.p,
    required this.steps,
    required this.onDone,
  });
  @override
  State<TourOverlay> createState() => TourOverlayState();
}

class TourOverlayState extends State<TourOverlay> {
  int i = -1;
  Rect? hole;
  bool _done = false;
  final _next = FocusNode(debugLabel: 'tour-next');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _go(0, 1));
  }

  @override
  void dispose() {
    _next.dispose();
    super.dispose();
  }

  /// Index of the visible step (for tests / counter).
  int get step => i;

  Rect? _rectOf(GlobalKey k) {
    final ctx = k.currentContext, me = context.findRenderObject();
    final ro = ctx?.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize || me is! RenderBox) {
      return null;
    }
    final a = me.globalToLocal(ro.localToGlobal(Offset.zero));
    final b = me.globalToLocal(
      ro.localToGlobal(ro.size.bottomRight(Offset.zero)),
    );
    return Rect.fromPoints(a, b);
  }

  Future<void> _go(int from, int dir) async {
    if (!mounted || _done) return;
    for (var j = from; j >= 0 && j < widget.steps.length; j += dir) {
      final k = widget.steps[j].key;
      final ctx = k.currentContext;
      if (ctx == null || !mounted) continue;
      var r = _rectOf(k);
      final me = context.findRenderObject() as RenderBox?;
      final size = me?.size ?? Size.zero;
      final view = Offset.zero & size;
      if (r != null && !view.contains(r.center)) {
        // scrolled away: bring it into view first
        await Scrollable.ensureVisible(
          ctx,
          alignment: .4,
          duration: const Duration(milliseconds: 250),
        );
        if (!mounted) return;
        await WidgetsBinding.instance.endOfFrame;
        r = _rectOf(k);
      }
      if (r == null || !view.contains(r.center)) continue;
      setState(() {
        i = j;
        hole = r;
      });
      _next.requestFocus();
      return;
    }
    if (dir > 0) finish(); // ran past the last step
  }

  void next() => _go(i + 1, 1);
  void back() {
    if (i > 0) _go(i - 1, -1);
  }

  void finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  KeyEventResult _key(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent)
      return KeyEventResult.handled; // swallow repeats/ups too
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.browserBack) {
      finish();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      back();
    } else if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.gameButtonA) {
      next();
    } else if (k == LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored; // let Tab move between Пропустить / Далее
    }
    return KeyEventResult.handled; // never leak arrows to the screen underneath
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final h = hole;
    final st = i >= 0 ? widget.steps[i] : null;
    final last =
        i >= 0 &&
        !widget.steps.skip(i + 1).any((s) => s.key.currentContext != null);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) => finish(),
      child: FocusScope(
        autofocus: true,
        onKeyEvent: _key,
        child: LayoutBuilder(
          builder: (_, box) {
            final w = box.maxWidth, H = box.maxHeight;
            final cardW = math.min(320.0, w - 24);
            Widget? card;
            if (h != null && st != null) {
              final below = h.center.dy < H / 2;
              final left = (h.center.dx - cardW / 2).clamp(
                12.0,
                math.max(12.0, w - cardW - 12),
              );
              card = Positioned(
                left: left.toDouble(),
                width: cardW,
                top: below ? h.bottom + 14 : null,
                bottom: below ? null : H - h.top + 14,
                child: _Card(
                  p: p,
                  step: st,
                  n: i + 1,
                  total: widget.steps.length,
                  last: last,
                  nextNode: _next,
                  onNext: next,
                  onSkip: finish,
                ),
              );
            }
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: next,
                    child: h == null
                        ? CustomPaint(painter: _Spot(null, false, p.acc2))
                        : TweenAnimationBuilder<Rect?>(
                            tween: RectTween(begin: h, end: h),
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            builder: (_, r, _) => CustomPaint(
                              painter: _Spot(r, st?.circle ?? false, p.acc2),
                            ),
                          ),
                  ),
                ),
                ?card,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Spot extends CustomPainter {
  final Rect? r;
  final bool circle;
  final Color ring;
  _Spot(this.r, this.circle, this.ring);
  @override
  void paint(Canvas c, Size s) {
    final dim = Paint()..color = const Color(0xC8000000);
    final all = Path()..addRect(Offset.zero & s);
    if (r == null) {
      c.drawPath(all, dim);
      return;
    }
    final Path hole;
    final RRect rr;
    if (circle) {
      final rad = math.max(r!.width, r!.height) / 2 + 8;
      rr = RRect.fromRectAndRadius(
        Rect.fromCircle(center: r!.center, radius: rad),
        Radius.circular(rad),
      );
    } else {
      rr = RRect.fromRectAndRadius(r!.inflate(6), const Radius.circular(16));
    }
    hole = Path()..addRRect(rr);
    c.drawPath(Path.combine(PathOperation.difference, all, hole), dim);
    c.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(_Spot o) =>
      o.r != r || o.circle != circle || o.ring != ring;
}

final _btn = TextButton.styleFrom(
  minimumSize: const Size(0, 40),
  padding: const EdgeInsets.symmetric(horizontal: 12),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

class _Card extends StatelessWidget {
  final Pal p;
  final TourStep step;
  final int n, total;
  final bool last;
  final FocusNode nextNode;
  final VoidCallback onNext, onSkip;
  const _Card({
    required this.p,
    required this.step,
    required this.n,
    required this.total,
    required this.last,
    required this.nextNode,
    required this.onNext,
    required this.onSkip,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: p.hero,
    elevation: 8,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step.title,
            style: TextStyle(
              color: p.txt,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(step.text, style: TextStyle(color: p.sub, fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            children: [
              Flexible(
                child: Text(
                  '$n / $total',
                  maxLines: 1,
                  style: TextStyle(color: p.ter, fontSize: 12),
                ),
              ),
              const Spacer(),
              TextButton(
                style: _btn,
                onPressed: onSkip,
                child: Text('Пропустить', style: TextStyle(color: p.sub)),
              ),
              TextButton(
                style: _btn,
                focusNode: nextNode,
                onPressed: onNext,
                child: Text(
                  last ? 'Готово' : 'Далее',
                  style: TextStyle(color: p.acc2, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
