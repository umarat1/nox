import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'controller.dart';
import 'fmt.dart';
import 'regions.dart';
import 'theme.dart';

class Home extends StatelessWidget {
  final NoxController c;
  const Home({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final p = Pal.of(c.settings['theme'] as String?);
        return Theme(
          data: materialTheme(p),
          child: Scaffold(
            backgroundColor: p.bg,
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: _Body(c: c, p: p),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

void toast(BuildContext ctx, String t) {
  ScaffoldMessenger.of(ctx)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(t),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xDD000000),
      ),
    );
}

class _Body extends StatelessWidget {
  final NoxController c;
  final Pal p;
  const _Body({required this.c, required this.p});

  @override
  Widget build(BuildContext context) {
    if (c.fatal != null && c.state == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'nox',
              style: TextStyle(
                color: p.txt,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              c.fatal!,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.sub),
            ),
            const SizedBox(height: 16),
            _Btn(p: p, label: 'Повторить', onTap: c.refresh),
          ],
        ),
      );
    }
    if (c.state == null)
      return const Center(child: CircularProgressIndicator());
    final view = c.pref('view', 'list');
    final list = c.visible();
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          sliver: SliverList.list(
            children: [
              _TopBar(c: c, p: p),
              _Hero(c: c, p: p),
              if ((c.s['error'] ?? '') != '')
                _Banner(
                  p: p,
                  text: c.s['error'],
                  color: p.red,
                  onTap: () => c.call('ClearError'),
                ),
              if ((c.s['notice'] ?? '') != '')
                _Banner(
                  p: p,
                  text: c.s['notice'],
                  color: p.acc,
                  onTap: () => c.call('ClearError'),
                ),
              if (c.s['update'] != null) _UpdateBanner(c: c, p: p),
              for (final b in c.subs) _SubBlock(c: c, p: p, b: b),
              _Chips(c: c, p: p),
              _Toolbar(c: c, p: p, shown: list.length),
            ],
          ),
        ),
        if (list.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Text(
                'Нет серверов. Нажмите «＋», чтобы добавить подписку или ссылку (vless, trojan, ss, hy2, tuic, qwdtt, sstp).',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.sub),
              ),
            ),
          )
        else if (view == 'grid')
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisSpacing: 7,
                crossAxisSpacing: 7,
                mainAxisExtent: 128,
              ),
              itemCount: list.length,
              itemBuilder: (_, i) => _ServerCard(c: c, p: p, s: list[i]),
            ),
          )
        else if (view == 'slider')
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 40),
            sliver: SliverList.list(children: _sliders(list)),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
            sliver: SliverList.builder(
              itemCount: list.length,
              itemBuilder: (_, i) => _ServerRow(c: c, p: p, s: list[i]),
            ),
          ),
      ],
    );
  }

  /// «Слайдеры»: one horizontal carousel per country (Автовыбор / qWDTT / other first).
  List<Widget> _sliders(List<J> list) {
    final groups = <String, List<J>>{};
    for (final s in list) {
      final k = NoxController.isBal(s)
          ? '⚡ Автовыбор'
          : NoxController.isQw(s)
          ? 'qWDTT'
          : (regionName[region(s['name'] ?? '') ?? ''] ?? 'Другие');
      groups.putIfAbsent(k, () => []).add(s);
    }
    return [
      for (final e in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Text(
            '${e.key} · ${e.value.length}',
            style: TextStyle(
              color: p.sub,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(
          height: 128,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: e.value.length,
            separatorBuilder: (_, _) => const SizedBox(width: 7),
            itemBuilder: (_, i) => SizedBox(
              width: 190,
              child: _ServerCard(c: c, p: p, s: e.value[i]),
            ),
          ),
        ),
      ],
    ];
  }
}

// ------------------------------------------------------------------ small widgets

class _IconBtn extends StatelessWidget {
  final Pal p;
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  const _IconBtn({
    required this.p,
    required this.icon,
    required this.tip,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: Material(
      color: p.chip,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Center(child: Icon(icon, color: p.txt, size: 19)),
        ),
      ),
    ),
  );
}

class _Btn extends StatelessWidget {
  final Pal p;
  final String label;
  final VoidCallback onTap;
  final bool secondary;
  const _Btn({
    required this.p,
    required this.label,
    required this.onTap,
    this.secondary = false,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Material(
      color: secondary ? p.chip : p.acc,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: secondary ? p.txt : Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    ),
  );
}

BoxDecoration _box(Pal p, {Color? color, double r = 18, Color? border}) =>
    BoxDecoration(
      color: color ?? p.card,
      borderRadius: BorderRadius.circular(r),
      border: Border.all(color: border ?? p.line),
    );

class _TopBar extends StatelessWidget {
  final NoxController c;
  final Pal p;
  const _TopBar({required this.c, required this.p});
  @override
  Widget build(BuildContext context) {
    final th = (c.settings['theme'] ?? 'dark') as String;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'n',
                    style: TextStyle(color: p.txt),
                  ),
                  TextSpan(
                    text: 'o',
                    style: TextStyle(color: p.acc2),
                  ),
                  TextSpan(
                    text: 'x',
                    style: TextStyle(color: p.txt),
                  ),
                ],
              ),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: .5,
              ),
            ),
          ),
          _IconBtn(
            p: p,
            icon: th == 'light'
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
            tip: 'Тема',
            onTap: () {
              final i = themeNames.indexWhere((e) => e.$1 == th);
              final n = themeNames[(i + 1) % 3].$1;
              c.saveSettings({'theme': n});
              toast(context, 'Тема: ${themeName(n)}');
            },
          ),
          const SizedBox(width: 8),
          _IconBtn(
            p: p,
            icon: Icons.add,
            tip: 'Добавить подписку',
            onTap: () => addSheet(context, c, p),
          ),
          const SizedBox(width: 8),
          _IconBtn(
            p: p,
            icon: Icons.settings_outlined,
            tip: 'Настройки',
            onTap: () => settingsSheet(context, c, p),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final NoxController c;
  final Pal p;
  const _Hero({required this.c, required this.p});
  @override
  Widget build(BuildContext context) {
    final on = c.connected, wait = c.busy, st = c.status, cur = c.current;
    final since = (c.s['since'] ?? 0) as int;
    final t = c.traffic;
    final label = on
        ? 'ПОДКЛЮЧЕНО'
        : st == 'connecting'
        ? 'ПОДКЛЮЧЕНИЕ…'
        : st == 'disconnecting'
        ? 'ОТКЛЮЧЕНИЕ…'
        : 'ОТКЛЮЧЕНО';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(p, color: p.hero, r: 22),
      child: Row(
        children: [
          Focus(
            child: Builder(
              builder: (ctx) {
                final f = Focus.of(ctx).hasFocus;
                return GestureDetector(
                  onTap: c.toggle,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: on
                          ? p.acc
                          : wait
                          ? p.amb
                          : p.chip,
                      border: f ? Border.all(color: p.acc2, width: 3) : null,
                      boxShadow: [
                        BoxShadow(
                          color: p.acc.withValues(alpha: on ? .25 : .08),
                          spreadRadius: on ? 8 : 6,
                        ),
                        if (on)
                          BoxShadow(
                            color: p.acc.withValues(alpha: .5),
                            blurRadius: 30,
                          ),
                      ],
                    ),
                    child: Icon(
                      Icons.power_settings_new,
                      size: 34,
                      color: on
                          ? Colors.white
                          : wait
                          ? const Color(0xFF111111)
                          : p.sub,
                    ),
                  ),
                );
              },
            ),
            onKeyEvent: (n, e) {
              if (e is KeyDownEvent &&
                  (e.logicalKey == LogicalKeyboardKey.select ||
                      e.logicalKey == LogicalKeyboardKey.enter)) {
                c.toggle();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: on
                        ? p.grn
                        : wait
                        ? p.amb
                        : p.sub,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  cur == null
                      ? 'Сервер не выбран'
                      : dispName(cur['name'] ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.txt,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  cur == null
                      ? ''
                      : '${NoxController.proto(cur).isEmpty ? 'Автовыбор' : NoxController.proto(cur)}'
                            '${on && since > 0 ? ' · ${fmtDur(DateTime.now().millisecondsSinceEpoch ~/ 1000 - since)}' : ''}',
                  style: TextStyle(color: p.sub, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Pill(p: p, text: '↓ ${fmtBytes(t?['Down'] ?? 0)}/с'),
                    const SizedBox(width: 10),
                    _Pill(p: p, text: '↑ ${fmtBytes(t?['Up'] ?? 0)}/с'),
                  ],
                ),
                if (t != null)
                  SizedBox(
                    height: 34,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _Graph((t['Hist'] as List?) ?? const [], p.acc),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final Pal p;
  final String text;
  const _Pill({required this.p, required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: p.chip,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(text, style: TextStyle(color: p.txt, fontSize: 12)),
  );
}

class _Graph extends CustomPainter {
  final List h;
  final Color col;
  _Graph(this.h, this.col);
  @override
  void paint(Canvas canvas, Size size) {
    if (h.isEmpty) return;
    final v = h.map((e) => ((e as List)[1] as num).toDouble()).toList();
    final mx = math.max(1.0, v.reduce(math.max));
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = i / 119 * size.width,
          y = size.height - 2 - v[i] / mx * (size.height - 4);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(_Graph o) => o.h != h;
}

class _Banner extends StatelessWidget {
  final Pal p;
  final String text;
  final Color color;
  final VoidCallback onTap;
  const _Banner({
    required this.p,
    required this.text,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Material(
      color: color.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            text,
            style: TextStyle(
              color: color == p.red ? p.red : p.txt,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    ),
  );
}

class _UpdateBanner extends StatelessWidget {
  final NoxController c;
  final Pal p;
  const _UpdateBanner({required this.c, required this.p});
  @override
  Widget build(BuildContext context) {
    final u = (c.s['update'] as Map).cast<String, dynamic>();
    final v = '${u['versionName']}';
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _box(p, r: 16, border: p.acc),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Доступна версия '),
                      TextSpan(
                        text: v,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  style: TextStyle(color: p.txt, fontSize: 13),
                ),
                if ((u['notes'] ?? '') != '')
                  Text(
                    '${u['notes']}',
                    style: TextStyle(color: p.sub, fontSize: 12),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              final r = await c.call('DoUpdate');
              if (context.mounted && r is String && r.isNotEmpty)
                toast(context, r);
            },
            child: Text(
              'Обновить',
              style: TextStyle(color: p.acc2, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: () async {
              await c.call('HideUpdate', [v]);
              c.refresh();
            },
            child: Text('Позже', style: TextStyle(color: p.sub)),
          ),
        ],
      ),
    );
  }
}

class _SubBlock extends StatelessWidget {
  final NoxController c;
  final Pal p;
  final J b;
  const _SubBlock({required this.c, required this.p, required this.b});
  @override
  Widget build(BuildContext context) {
    final n = c.servers.where((s) => s['subId'] == b['id']).length;
    final used = ((b['upload'] ?? 0) as num) + ((b['download'] ?? 0) as num);
    final total = (b['total'] ?? 0) as num;
    final expire = (b['expire'] ?? 0) as int;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final left = expire > 0 ? (expire - now) / 86400 : null;
    final days = left == null ? null : math.max(0, left.ceil());
    final m = TextStyle(color: p.sub, fontSize: 12);
    final ann = (b['announce'] ?? '') as String;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: _box(p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${b['name'] ?? 'Подписка'}',
                  style: TextStyle(
                    color: p.txt,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              _IconBtn(
                p: p,
                icon: Icons.refresh,
                tip: 'Обновить',
                onTap: () async {
                  final r = await c.call('RefreshSub', [b['id']]);
                  await c.refresh();
                  if (context.mounted)
                    toast(
                      context,
                      (r is String && r.isNotEmpty) ? r : 'Обновлено',
                    );
                },
              ),
              const SizedBox(width: 6),
              _IconBtn(
                p: p,
                icon: Icons.more_vert,
                tip: 'Ещё',
                onTap: () => subSheet(context, c, p, b),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Серверов: $n'),
                if (left != null)
                  left <= 0
                      ? TextSpan(
                          text: ' · истекла',
                          style: TextStyle(color: p.red),
                        )
                      : TextSpan(
                          text:
                              ' · осталось $days ${plural(days!, 'день', 'дня', 'дней')}',
                          style: left <= 3 ? TextStyle(color: p.amb) : null,
                        ),
              ],
            ),
            style: m,
          ),
          Text(
            '${expire > 0 ? 'Действует до: ${fmtDate(expire)} · ' : ''}'
            '${used > 0 || total > 0 ? 'Трафик: ${fmtBytes(used)}${total > 0 ? ' из ${fmtBytes(total)}' : ''}' : 'Трафик: без лимита'}',
            style: m,
          ),
          if (total > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: math.min(1.0, used / total),
                  minHeight: 4,
                  backgroundColor: p.chip,
                  color: p.acc,
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Обновлено: ${ago((b['updated'] ?? 0) as int)}',
            style: m.copyWith(color: p.ter),
          ),
          if (ann.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: p.acc.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(ann, style: TextStyle(color: p.txt, fontSize: 12.5)),
            ),
          if ((b['webPage'] ?? '') != '' || (b['support'] ?? '') != '')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  if ((b['webPage'] ?? '') != '')
                    _Link(p: p, text: 'Подробнее', url: b['webPage']),
                  if ((b['support'] ?? '') != '')
                    _Link(p: p, text: 'Поддержка', url: b['support']),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Link extends StatelessWidget {
  final Pal p;
  final String text, url;
  const _Link({required this.p, required this.text, required this.url});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: url));
        toast(context, 'Ссылка скопирована: $url');
      },
      child: Text(
        text,
        style: TextStyle(
          color: p.acc2,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _Chips extends StatelessWidget {
  final NoxController c;
  final Pal p;
  const _Chips({required this.c, required this.p});
  @override
  Widget build(BuildContext context) {
    final cs = c.chips(), cat = c.category;
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        itemCount: cs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final (k, t, iso) = cs[i];
          final on = k == cat;
          return Material(
            color: on ? p.acc : p.chip,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => c.setPref('cat', k),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (iso != null && hasFlag(iso)) ...[
                      ClipOval(
                        child: SvgPicture.asset(
                          'assets/flags/${iso.toLowerCase()}.svg',
                          width: 16,
                          height: 16,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      t,
                      style: TextStyle(
                        color: on ? Colors.white : p.txt,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final NoxController c;
  final Pal p;
  final int shown;
  const _Toolbar({required this.c, required this.p, required this.shown});
  @override
  Widget build(BuildContext context) {
    final s = c.s;
    final txt = s['pinging'] == true
        ? 'Пинг ${s['pingDone']}/${s['pingAll']}…'
        : '$shown из ${c.servers.length} · пинг: ${c.settings['pingMode'] == 'tcp' ? 'TCP' : 'через прокси'}';
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(txt, style: TextStyle(color: p.sub, fontSize: 12)),
          ),
          _IconBtn(
            p: p,
            icon: Icons.bolt,
            tip: 'Пинг',
            onTap: () {
              c.ping(c.visible().map((e) => e['id'] as String).toList());
              toast(context, 'Проверяю пинг…');
            },
          ),
          const SizedBox(width: 6),
          _IconBtn(
            p: p,
            icon: Icons.refresh,
            tip: 'Обновить подписки',
            onTap: () async {
              toast(context, 'Обновляю подписки…');
              final r = await c.call('RefreshSubs');
              await c.refresh();
              if (context.mounted) toast(context, (r ?? 'Готово').toString());
            },
          ),
          const SizedBox(width: 6),
          _IconBtn(
            p: p,
            icon: Icons.more_vert,
            tip: 'Ещё',
            onTap: () => listSheet(context, c, p),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ servers

Widget _flag(Pal p, J s, {double size = 36}) {
  Widget inner;
  if (NoxController.isBal(s)) {
    inner = const Text('⚡', style: TextStyle(fontSize: 15));
  } else if (NoxController.isQw(s)) {
    inner = Text(
      'qW',
      style: TextStyle(
        color: p.acc2,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    );
  } else {
    final r = region(s['name'] ?? '');
    if (r != null && hasFlag(r)) {
      return ClipOval(
        child: SvgPicture.asset(
          'assets/flags/${r.toLowerCase()}.svg',
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    final t = r ?? NoxController.proto(s);
    inner = Text(
      t.length > 2 ? t.substring(0, 2).toUpperCase() : t.toUpperCase(),
      style: TextStyle(color: p.sub, fontWeight: FontWeight.w700, fontSize: 12),
    );
  }
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: p.chip, shape: BoxShape.circle),
    child: inner,
  );
}

/// White (light theme: ink) ping chip — no green/yellow/red; «таймаут» marks dead servers.
class PingChip extends StatelessWidget {
  final Pal p;
  final String text;
  const PingChip({super.key, required this.p, required this.text});
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 54),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: p.pingBg,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: p.pingFg,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

String _pingOf(NoxController c, J s) {
  final ping = (s['ping'] ?? 0) as int;
  if (c.s['pinging'] == true && c.pingWait.contains(s['id']) && ping == 0)
    return '…';
  return pingText(ping);
}

String _sub(J s) {
  final pr = NoxController.proto(s);
  final m = (s['members'] as List?)?.length;
  final d = (s['desc'] ?? '') as String;
  return '${pr.isNotEmpty ? pr : (m != null ? '$m серв.' : '')}${d.isNotEmpty ? ' · $d' : ''}';
}

class _Tap extends StatelessWidget {
  final Pal p;
  final bool sel;
  final Widget child;
  final VoidCallback onTap, onLong;
  final EdgeInsets padding;
  const _Tap({
    required this.p,
    required this.sel,
    required this.child,
    required this.onTap,
    required this.onLong,
    required this.padding,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: sel ? p.sel : p.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: sel ? p.acc : p.line),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      focusColor: p.acc.withValues(alpha: .25),
      onTap: onTap,
      onLongPress: onLong,
      onSecondaryTap: onLong,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class _ServerRow extends StatelessWidget {
  final NoxController c;
  final Pal p;
  final J s;
  const _ServerRow({required this.c, required this.p, required this.s});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: _Tap(
      p: p,
      sel: s['id'] == c.selected,
      onTap: () => c.select(s['id']),
      onLong: () => serverSheet(context, c, p, s),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Row(
        children: [
          _flag(p, s),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dispName(s['name'] ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.txt, fontWeight: FontWeight.w600),
                ),
                if (_sub(s).isNotEmpty)
                  Text(
                    _sub(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.sub, fontSize: 12),
                  ),
              ],
            ),
          ),
          PingChip(p: p, text: _pingOf(c, s)),
          IconButton(
            onPressed: () => serverSheet(context, c, p, s),
            icon: Icon(Icons.more_vert, color: p.sub, size: 20),
            tooltip: 'Ещё',
          ),
        ],
      ),
    ),
  );
}

class _ServerCard extends StatelessWidget {
  final NoxController c;
  final Pal p;
  final J s;
  const _ServerCard({required this.c, required this.p, required this.s});
  @override
  Widget build(BuildContext context) => _Tap(
    p: p,
    sel: s['id'] == c.selected,
    onTap: () => c.select(s['id']),
    onLong: () => serverSheet(context, c, p, s),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _flag(p, s),
            const Spacer(),
            InkWell(
              onTap: () => serverSheet(context, c, p, s),
              child: Icon(Icons.more_vert, color: p.sub, size: 18),
            ),
          ],
        ),
        const Spacer(),
        Text(
          dispName(s['name'] ?? ''),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: p.txt, fontWeight: FontWeight.w600),
        ),
        Text(
          _sub(s),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: p.sub, fontSize: 12),
        ),
        const SizedBox(height: 6),
        PingChip(p: p, text: _pingOf(c, s)),
      ],
    ),
  );
}

// ------------------------------------------------------------------ sheets

Future<void> sheet(
  BuildContext context,
  Pal p,
  String title,
  List<Widget> Function(BuildContext) items,
) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: p.hero,
  constraints: const BoxConstraints(maxWidth: 560),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
  ),
  builder: (ctx) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(ctx).size.height * .88,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: p.txt,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...items(ctx),
          ],
        ),
      ),
    ),
  ),
);

Widget item(
  Pal p,
  String label, {
  String? desc,
  VoidCallback? onTap,
  bool checked = false,
  Widget? trailing,
  Color? color,
  bool arrow = false,
}) {
  return InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      if (checked)
                        TextSpan(
                          text: '✓ ',
                          style: TextStyle(color: p.acc2),
                        ),
                      TextSpan(text: label),
                    ],
                  ),
                  style: TextStyle(color: color ?? p.txt, fontSize: 14),
                ),
                if (desc != null && desc.isNotEmpty)
                  Text(desc, style: TextStyle(color: p.sub, fontSize: 12)),
              ],
            ),
          ),
          if (trailing != null) trailing,
          if (arrow) Text('›', style: TextStyle(color: p.sub, fontSize: 18)),
        ],
      ),
    ),
  );
}

Widget sw(Pal p, bool on) => Container(
  width: 40,
  height: 22,
  decoration: BoxDecoration(
    color: on ? p.acc : p.line,
    borderRadius: BorderRadius.circular(12),
  ),
  child: AnimatedAlign(
    duration: const Duration(milliseconds: 150),
    alignment: on ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.all(3),
      width: 16,
      height: 16,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    ),
  ),
);

const _sorts = [
  ('', 'По умолчанию'),
  ('ping', 'По пингу'),
  ('name', 'По имени'),
];
const _views = [
  ('list', 'Список'),
  ('grid', 'Карточки'),
  ('slider', 'Слайдеры'),
];
const _dns = [
  ('cloudflare', 'Cloudflare (1.1.1.1)'),
  ('google', 'Google (8.8.8.8)'),
  ('yandex', 'Яндекс (77.88.8.8)'),
  ('adguard', 'AdGuard (без рекламы)'),
];

void settingsSheet(BuildContext context, NoxController c, Pal p) {
  sheet(context, p, 'Настройки', (ctx) {
    final s = c.settings;
    Widget swItem(String k, String t, [String? d]) => item(
      p,
      t,
      desc: d,
      trailing: sw(p, s[k] == true),
      onTap: () {
        c.saveSettings({k: !(s[k] == true)});
        Navigator.pop(ctx);
      },
    );
    return [
      item(
        p,
        'Режим',
        desc: s['mode'] == 'proxy' ? 'Системный прокси' : 'TUN (весь трафик)',
        arrow: true,
        onTap: () {
          c.saveSettings({'mode': s['mode'] == 'proxy' ? 'tun' : 'proxy'});
          Navigator.pop(ctx);
        },
      ),
      item(
        p,
        'Тема',
        desc: themeName(s['theme']),
        arrow: true,
        onTap: () {
          Navigator.pop(ctx);
          sheet(
            context,
            p,
            'Тема',
            (c2) => [
              for (final (k, n) in themeNames)
                item(
                  p,
                  n,
                  checked: (s['theme'] ?? 'dark') == k,
                  onTap: () {
                    c.saveSettings({'theme': k});
                    Navigator.pop(c2);
                  },
                ),
            ],
          );
        },
      ),
      item(
        p,
        'DNS',
        desc: _dns
            .firstWhere(
              (e) => e.$1 == (s['dns'] ?? 'cloudflare'),
              orElse: () => _dns[0],
            )
            .$2,
        arrow: true,
        onTap: () {
          Navigator.pop(ctx);
          sheet(
            context,
            p,
            'DNS',
            (c2) => [
              for (final (k, n) in _dns)
                item(
                  p,
                  n,
                  checked: (s['dns'] ?? 'cloudflare') == k,
                  onTap: () {
                    c.saveSettings({'dns': k});
                    Navigator.pop(c2);
                  },
                ),
            ],
          );
        },
      ),
      swItem('directRu', 'Российские сайты мимо VPN'),
      swItem(
        'autoSwitch',
        'Автопереключение при блокировке',
        'Каждые 20 с проверка через туннель; после 3 неудач — переход на рабочий сервер (сначала та же страна, другой протокол)',
      ),
      swItem('blockAds', 'Блокировка рекламы'),
      swItem('autoConnect', 'Автоподключение при запуске'),
      swItem('autostart', 'Запуск вместе с системой'),
      swItem('ipv6', 'IPv6'),
      item(
        p,
        'Тип пинга',
        arrow: true,
        onTap: () {
          Navigator.pop(ctx);
          pingSheet(context, c, p);
        },
      ),
      item(
        p,
        'Проверить обновления',
        onTap: () async {
          final r = await c.call('CheckUpdateMsg');
          if (ctx.mounted) toast(ctx, '$r');
        },
      ),
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          'nox ${c.s['version']} · ${c.s['core']} · ${c.api.transport}',
          style: TextStyle(color: p.sub, fontSize: 12),
        ),
      ),
    ];
  });
}

void pingSheet(BuildContext context, NoxController c, Pal p) {
  const pu = [
    ('', 'Google (gstatic)'),
    ('https://cp.cloudflare.com/generate_204', 'Cloudflare'),
    ('https://ya.ru/', 'Яндекс'),
  ];
  sheet(context, p, 'Тип пинга', (ctx) {
    final s = c.settings, m = s['pingMode'] ?? 'url';
    return [
      item(
        p,
        'Через прокси',
        desc: 'Реальная проверка URL через сервер (по умолчанию)',
        checked: m != 'tcp',
        onTap: () {
          c.saveSettings({'pingMode': 'url'});
          Navigator.pop(ctx);
        },
      ),
      item(
        p,
        'TCP',
        desc:
            'Время TCP-подключения к серверу напрямую, мимо VPN (и когда VPN включён). Быстрый TCP ≠ рабочий туннель.',
        checked: m == 'tcp',
        onTap: () {
          c.saveSettings({'pingMode': 'tcp'});
          Navigator.pop(ctx);
        },
      ),
      if (m != 'tcp') ...[
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Text(
            'Точка проверки',
            style: TextStyle(color: p.txt, fontWeight: FontWeight.w700),
          ),
        ),
        for (final (k, n) in pu)
          item(
            p,
            n,
            checked: (s['pingUrl'] ?? '') == k,
            onTap: () {
              c.saveSettings({'pingUrl': k});
              Navigator.pop(ctx);
            },
          ),
      ],
    ];
  });
}

void listSheet(BuildContext context, NoxController c, Pal p) {
  sheet(context, p, 'Список', (ctx) {
    final h = c.flag('hideDead', true),
        d = c.flag('dedup', true),
        v = c.pref('view', 'list');
    final undo = (c.s['canUndo'] ?? 0) as int;
    return [
      item(
        p,
        'Сортировка',
        desc: _sorts
            .firstWhere(
              (e) => e.$1 == (c.s['sort'] ?? ''),
              orElse: () => _sorts[0],
            )
            .$2,
        arrow: true,
        onTap: () {
          Navigator.pop(ctx);
          sheet(
            context,
            p,
            'Сортировка',
            (c2) => [
              for (final (k, n) in _sorts)
                item(
                  p,
                  n,
                  checked: (c.s['sort'] ?? '') == k,
                  onTap: () async {
                    await c.call('SetSort', [k]);
                    await c.refresh();
                    if (c2.mounted) Navigator.pop(c2);
                  },
                ),
            ],
          );
        },
      ),
      item(
        p,
        'Вид',
        desc: _views.firstWhere((e) => e.$1 == v).$2,
        arrow: true,
        onTap: () {
          Navigator.pop(ctx);
          sheet(
            context,
            p,
            'Вид',
            (c2) => [
              for (final (k, n) in _views)
                item(
                  p,
                  n,
                  checked: v == k,
                  onTap: () {
                    c.setPref('view', k);
                    Navigator.pop(c2);
                  },
                ),
            ],
          );
        },
      ),
      item(
        p,
        'Скрыть нерабочие',
        checked: h,
        onTap: () {
          c.setPref('hideDead', h ? '0' : '1');
          Navigator.pop(ctx);
        },
      ),
      item(
        p,
        'Скрывать дубликаты',
        checked: d,
        onTap: () {
          c.setPref('dedup', d ? '0' : '1');
          Navigator.pop(ctx);
        },
      ),
      item(
        p,
        'Выбрать самый быстрый',
        desc: 'Автовыбор по последнему пингу',
        onTap: () async {
          Navigator.pop(ctx);
          final id = await c.call('BestServer', [30]);
          if (id is String && id.isNotEmpty) {
            await c.select(id);
          } else if (context.mounted) {
            toast(context, 'Сначала проверьте пинг');
          }
        },
      ),
      item(
        p,
        'Удалить нерабочие',
        onTap: () async {
          Navigator.pop(ctx);
          final n = await c.call('DeleteDead', [<String>[]]);
          await c.refresh();
          if (context.mounted) toast(context, 'Удалено: $n');
        },
      ),
      if (undo > 0)
        item(
          p,
          'Вернуть удалённые ($undo)',
          onTap: () async {
            Navigator.pop(ctx);
            final n = await c.call('UndoDelete');
            await c.refresh();
            if (context.mounted) toast(context, 'Возвращено: $n');
          },
        ),
      if (c.subs.length > 1)
        item(
          p,
          'Порядок подписок',
          arrow: true,
          onTap: () {
            Navigator.pop(ctx);
            orderSheet(context, c, p);
          },
        ),
      item(
        p,
        'Тип пинга',
        desc: c.settings['pingMode'] == 'tcp' ? 'TCP' : 'Через прокси',
        onTap: () {
          Navigator.pop(ctx);
          pingSheet(context, c, p);
        },
      ),
      item(
        p,
        'Журнал',
        onTap: () async {
          Navigator.pop(ctx);
          final log = await c.call('GetLog');
          if (!context.mounted) return;
          sheet(
            context,
            p,
            'Журнал',
            (_) => [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: p.chip,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  '$log',
                  style: TextStyle(
                    color: p.txt,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ];
  });
}

void orderSheet(BuildContext context, NoxController c, Pal p) {
  showModalBottomSheet(
    context: context,
    backgroundColor: p.hero,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final l = c.subs;
        Future<void> mv(int i, int d) async {
          final ids = l.map((e) => e['id']).toList();
          final t = ids[i];
          ids[i] = ids[i + d];
          ids[i + d] = t;
          await c.call('ReorderSubs', [ids]);
          await c.refresh();
          set(() {});
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Порядок подписок',
                style: TextStyle(
                  color: p.txt,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              for (var i = 0; i < l.length; i++)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${l[i]['name'] ?? 'Подписка'}',
                        style: TextStyle(color: p.txt),
                      ),
                    ),
                    IconButton(
                      onPressed: i > 0 ? () => mv(i, -1) : null,
                      icon: Icon(Icons.arrow_upward, color: p.txt),
                    ),
                    IconButton(
                      onPressed: i < l.length - 1 ? () => mv(i, 1) : null,
                      icon: Icon(Icons.arrow_downward, color: p.txt),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              _Btn(p: p, label: 'Готово', onTap: () => Navigator.pop(ctx)),
            ],
          ),
        );
      },
    ),
  );
}

void subSheet(BuildContext context, NoxController c, Pal p, J b) {
  sheet(
    context,
    p,
    'Подписка',
    (ctx) => [
      item(
        p,
        'Обновить',
        onTap: () async {
          Navigator.pop(ctx);
          final r = await c.call('RefreshSub', [b['id']]);
          await c.refresh();
          if (context.mounted)
            toast(context, (r is String && r.isNotEmpty) ? r : 'Обновлено');
        },
      ),
      item(
        p,
        'Копировать ссылку',
        onTap: () async {
          Navigator.pop(ctx);
          final t = await c.call('SubLink', [b['id']]);
          await Clipboard.setData(ClipboardData(text: '$t'));
          if (context.mounted) toast(context, 'Ссылка скопирована');
        },
      ),
      item(
        p,
        'Удалить',
        color: p.red,
        onTap: () async {
          Navigator.pop(ctx);
          final ok = await showDialog<bool>(
            context: context,
            builder: (d) => AlertDialog(
              title: const Text('Удалить подписку?'),
              content: const Text('Подписка и её серверы будут удалены.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(d, false),
                  child: const Text('Отмена'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(d, true),
                  child: const Text('Удалить'),
                ),
              ],
            ),
          );
          if (ok == true) {
            await c.call('DeleteSub', [b['id']]);
            await c.refresh();
          }
        },
      ),
    ],
  );
}

void serverSheet(BuildContext context, NoxController c, Pal p, J s) {
  sheet(
    context,
    p,
    dispName(s['name'] ?? ''),
    (ctx) => [
      Text(
        '${s['type']} · ${s['host'] ?? ''}${(s['port'] ?? 0) != 0 ? ':${s['port']}' : ''}',
        style: TextStyle(color: p.sub, fontSize: 12),
      ),
      item(
        p,
        'Подключиться',
        onTap: () async {
          Navigator.pop(ctx);
          await c.call('Select', [s['id']]);
          if (c.status == 'disconnected') await c.call('Connect');
          c.refresh();
        },
      ),
      item(
        p,
        'Проверить пинг',
        onTap: () {
          Navigator.pop(ctx);
          c.ping([s['id']]);
        },
      ),
      item(
        p,
        'Скопировать конфиг',
        onTap: () async {
          Navigator.pop(ctx);
          final t = await c.call('ServerLink', [s['id']]);
          await Clipboard.setData(ClipboardData(text: '$t'));
          if (context.mounted) toast(context, 'Скопировано');
        },
      ),
      item(
        p,
        'Удалить',
        color: p.red,
        onTap: () async {
          Navigator.pop(ctx);
          await c.call('DeleteServer', [s['id']]);
          c.refresh();
        },
      ),
    ],
  );
}

void addSheet(BuildContext context, NoxController c, Pal p) {
  final tc = TextEditingController();
  sheet(
    context,
    p,
    'Добавить',
    (ctx) => [
      TextField(
        controller: tc,
        maxLines: 5,
        style: TextStyle(color: p.txt),
        decoration: InputDecoration(
          hintText:
              'Ссылка на подписку, vless://, trojan://, ss://, hy2://, tuic://, qwdtt://, sstp://user:pass@host:443#Имя',
          hintStyle: TextStyle(color: p.ter, fontSize: 13),
          filled: true,
          fillColor: p.chip,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: p.line),
          ),
        ),
      ),
      const SizedBox(height: 10),
      _Btn(
        p: p,
        secondary: true,
        label: 'Вставить из буфера',
        onTap: () async {
          final d = await Clipboard.getData('text/plain');
          tc.text = d?.text ?? '';
        },
      ),
      const SizedBox(height: 10),
      _Btn(
        p: p,
        label: 'Добавить',
        onTap: () async {
          final r = await c.call('Import', [tc.text]);
          if (ctx.mounted) Navigator.pop(ctx);
          await c.refresh();
          if (r is Map && context.mounted) {
            final errs = (r['errors'] as List?)?.length ?? 0;
            toast(context, '${r['msg']}${errs > 0 ? ' · ошибок: $errs' : ''}');
          }
        },
      ),
    ],
  );
}
