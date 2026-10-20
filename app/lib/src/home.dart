import 'split_apps.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'controller.dart';
import 'fmt.dart';
import 'live_graph.dart';
import 'platform.dart';
import 'regions.dart';
import 'theme.dart';
import 'pair.dart';
import 'update_ui.dart';
import 'tour.dart';
import 'qr_import.dart';

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
            body: PairGlue(
              c: c,
              child: Stack(
                children: [
                  SafeArea(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        // TV / wide window: two panes (controls left, servers right)
                        // (fills the whole window; narrow keeps the phone column)
                        // A 1080p TV is ~960 dp; with TV UI scale (≤1.3) it is ≥738,
                        // so TVs keep the two panes from 640 dp.
                        final wide = box.maxWidth >= (c.isTv ? 640 : 840);
                        return Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: wide ? double.infinity : 560,
                            ),
                            child: _Body(
                              c: c,
                              p: p,
                              wide: wide,
                              w: box.maxWidth,
                              h: box.maxHeight,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (c.tourOn)
                    Positioned.fill(
                      child: TourOverlay(
                        key: ValueKey('tour${c.tourRun}'),
                        p: p,
                        steps: tourSteps(tv: c.isTv),
                        onDone: c.endTour,
                      ),
                    ),
                ],
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
  final bool wide;
  final double w, h;
  const _Body({
    required this.c,
    required this.p,
    this.wide = false,
    this.w = 0,
    this.h = 0,
  });

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
    final head = <Widget>[
      if (!wide) _TopBar(c: c, p: p),
      _Hero(c: c, p: p, wide: wide),
      if (wide) const _GraphSlot(),
      if (c.vpnDenied)
        _Banner(
          p: p,
          text: 'Нужно разрешение на VPN: нажмите кнопку питания и подтвердите системный запрос.',
          color: p.red,
          onTap: () {
            c.vpnDenied = false;
            c.refresh();
          },
        ),
      if (c.captcha != null && canCaptcha && !c.captchaOpen)
        _Banner(
          p: p,
          text: 'qWDTT: VK просит пройти проверку «я не робот». Нажмите, чтобы открыть.',
          color: p.amb,
          onTap: c.openCaptcha,
        ),
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
      for (final (i, b) in c.subs.indexed)
        _SubBlock(key: i == 0 ? TourKeys.sub : null, c: c, p: p, b: b),
    ];
    final listHead = <Widget>[_FilterBar(c: c, p: p, shown: list.length)];
    final servers = _serverSlivers(list, view);
    if (wide) {
      // Two columns sharing top and bottom edges, equal outer padding (pad) on every side:
      // left = connect card, live graph (flexes to fill), subscriptions; right = one panel
      // with filters on top and the server list scrolling inside it.
      const pad = 20.0, gap = 16.0;
      final leftW = (w * .34).clamp(390.0, 540.0);
      final graph = _GraphCard(c: c, p: p);
      final banners = head.length - 2 - c.subs.length; // between hero and graph
      final need = 140 + 230 + 60.0 * banners + 150.0 * c.subs.length;
      final avail = h - pad * 2 - 56;
      Widget left;
      if (avail >= need) {
        left = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final wdg in head)
              if (wdg is _GraphSlot) Expanded(child: graph) else wdg,
          ],
        );
      } else {
        // short window: scroll the column, graph gets a fixed height
        left = ListView(
          padding: EdgeInsets.zero,
          children: [
            for (final wdg in head)
              if (wdg is _GraphSlot)
                SizedBox(height: 230, child: graph)
              else
                wdg,
          ],
        );
      }
      return Padding(
        padding: const EdgeInsets.all(pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopBar(c: c, p: p),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: leftW,
                    child: FocusTraversalGroup(child: left),
                  ),
                  const SizedBox(width: gap),
                  Expanded(
                    child: FocusTraversalGroup(
                      child: Container(
                        decoration: _box(p, r: 22),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: listHead,
                              ),
                            ),
                            Expanded(child: CustomScrollView(slivers: servers)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    // Phone: pin logo/actions + connection card; banners, subs, chips and list scroll under them.
    final pinned = <Widget>[
      for (final wdg in head)
        if (wdg is _TopBar || wdg is _Hero) wdg,
    ];
    final scrollHead = <Widget>[
      for (final wdg in head)
        if (wdg is! _TopBar && wdg is! _Hero) wdg,
      ...listHead,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: pinned,
          ),
        ),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                sliver: SliverList.list(children: scrollHead),
              ),
              ...servers,
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _serverSlivers(List<J> list, String view) {
    final h = wide
        ? const EdgeInsets.fromLTRB(14, 0, 14, 14)
        : const EdgeInsets.fromLTRB(12, 0, 12, 40);
    if (list.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Text(
              'Нет серверов. Нажмите «＋», чтобы добавить подписку или ссылку (vless, trojan, ss, hy2, tuic, qwdtt, sstp).',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.sub),
            ),
          ),
        ),
      ];
    }
    if (view == 'grid') {
      return [
        SliverPadding(
          padding: h,
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 260,
              mainAxisSpacing: 7,
              crossAxisSpacing: 7,
              mainAxisExtent: 128,
            ),
            itemCount: list.length,
            itemBuilder: (_, i) =>
                _ServerCard(c: c, p: p, s: list[i], first: i == 0),
          ),
        ),
      ];
    }
    if (view == 'slider') {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 40),
          sliver: SliverList.list(children: _sliders(list)),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: h,
        sliver: SliverList.builder(
          itemCount: list.length,
          itemBuilder: (_, i) =>
              _ServerRow(c: c, p: p, s: list[i], first: i == 0),
        ),
      ),
    ];
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
  final bool small; // flat 34×34 (filter bar) instead of a 38×38 chip
  const _IconBtn({
    super.key,
    required this.p,
    required this.icon,
    required this.tip,
    required this.onTap,
    this.small = false,
  });
  @override
  Widget build(BuildContext context) {
    final d = small ? 34.0 : 38.0;
    return Tooltip(
      message: tip,
      child: Material(
        color: small ? Colors.transparent : p.chip,
        borderRadius: BorderRadius.circular(small ? 10 : 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(small ? 10 : 12),
          focusColor: p.acc.withValues(alpha: .28),
          onTap: onTap,
          child: SizedBox(
            width: d,
            height: d,
            child: Center(
              child: Icon(
                icon,
                color: small ? p.sub : p.txt,
                size: small ? 18 : 19,
              ),
            ),
          ),
        ),
      ),
    );
  }
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
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: secondary ? raisedGradient(p, p.chip) : accentGradient(p),
        border: secondary ? Border.all(color: p.line) : null,
        boxShadow: secondary
            ? raisedShadow(p, e: .6)
            : [
                BoxShadow(
                  color: p.acc.withValues(alpha: .35),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: Material(
        type: MaterialType.transparency,
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
    ),
  );
}

BoxDecoration _box(Pal p, {Color? color, double r = 18, Color? border}) =>
    BoxDecoration(
      color: color ?? p.card,
      gradient: raisedGradient(p, color ?? p.card),
      borderRadius: BorderRadius.circular(r),
      border: Border.all(color: border ?? p.line),
      boxShadow: raisedShadow(p),
    );

class _TopBar extends StatelessWidget {
  final NoxController c;
  final Pal p;
  const _TopBar({required this.c, required this.p});
  @override
  Widget build(BuildContext context) {
    final th = (c.settings['theme'] ?? 'dark') as String;
    final logo = Text.rich(
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
    );
    // Equal Expanded sides keep the logo exactly centred whatever the button counts.
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _GhostBtn(
                    key: TourKeys.add,
                    p: p,
                    icon: Icons.add,
                    tip: 'Добавить подписку',
                    onTap: () => addSheet(context, c, p),
                  ),
                  const SizedBox(width: 2),
                  _GhostBtn(
                    key: TourKeys.theme,
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
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: logo,
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canFullScreen) ...[
                    ValueListenableBuilder<bool>(
                      valueListenable: fullScreen,
                      builder: (_, fs, _) => _GhostBtn(
                        p: p,
                        icon: fs ? Icons.fullscreen_exit : Icons.fullscreen,
                        tip: fs
                            ? 'Выйти из полноэкранного режима (F11)'
                            : 'Во весь экран (F11)',
                        onTap: () => toggleFullScreen(),
                      ),
                    ),
                    const SizedBox(width: 2),
                  ],
                  _MailBtn(c: c, p: p),
                  const SizedBox(width: 2),
                  _GhostBtn(
                    key: TourKeys.settings,
                    p: p,
                    icon: Icons.settings_outlined,
                    tip: 'Настройки',
                    onTap: () => settingsSheet(context, c, p),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Flat header button: no fill, circular ripple, accent focus ring for TV D-pad.
class _GhostBtn extends StatefulWidget {
  final Pal p;
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final Color? tint;
  final bool badge;
  const _GhostBtn({
    super.key,
    required this.p,
    required this.icon,
    required this.tip,
    required this.onTap,
    this.tint,
    this.badge = false,
  });
  @override
  State<_GhostBtn> createState() => _GhostBtnState();
}

class _GhostBtnState extends State<_GhostBtn> {
  bool _f = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    return Tooltip(
      message: widget.tip,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _f = f),
          focusColor: p.acc.withValues(alpha: .16),
          hoverColor: p.acc.withValues(alpha: .10),
          splashColor: p.acc.withValues(alpha: .22),
          highlightColor: p.acc.withValues(alpha: .10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _f ? p.acc2 : Colors.transparent,
                width: 2,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(widget.icon, size: 22, color: widget.tint ?? p.txt),
                if (widget.badge)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: p.acc2,
                        shape: BoxShape.circle,
                        border: Border.all(color: p.bg, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final NoxController c;
  final Pal p;
  final bool wide; // wide layout has its own big graph card
  const _Hero({required this.c, required this.p, this.wide = false});
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
            key: TourKeys.power,
            autofocus: c.isTv,
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
                      // volumetric knob: lit from the top-left, deeper at the bottom-right
                      gradient: RadialGradient(
                        center: const Alignment(-.35, -.45),
                        radius: 1.05,
                        colors: on
                            ? [
                                Color.lerp(p.acc2, Colors.white, .28)!,
                                p.acc,
                                Color.lerp(p.acc, Colors.black, .35)!,
                              ]
                            : wait
                            ? [
                                Color.lerp(p.amb, Colors.white, .3)!,
                                p.amb,
                                Color.lerp(p.amb, Colors.black, .3)!,
                              ]
                            : [
                                Color.alphaBlend(
                                  Colors.white.withValues(
                                    alpha: p.light ? .9 : .10,
                                  ),
                                  p.chip,
                                ),
                                Color.alphaBlend(
                                  Colors.white.withValues(
                                    alpha: p.light ? .2 : .03,
                                  ),
                                  p.chip,
                                ),
                                p.light
                                    ? Color.lerp(p.chip, Colors.black, .06)!
                                    : p.chip,
                              ],
                        stops: const [0, .55, 1],
                      ),
                      border: f
                          ? Border.all(color: p.acc2, width: 3)
                          : Border.all(
                              color: on
                                  ? Colors.white.withValues(alpha: .18)
                                  : p.line,
                            ),
                      boxShadow: [
                        // halo ring + glow (stronger when connected)
                        BoxShadow(
                          color: p.acc.withValues(alpha: on ? .28 : .08),
                          spreadRadius: on ? 8 : 6,
                        ),
                        BoxShadow(
                          color: (wait && !on ? p.amb : p.acc).withValues(
                            alpha: on
                                ? .6
                                : wait
                                ? .35
                                : .12,
                          ),
                          blurRadius: on ? 40 : 22,
                          spreadRadius: on ? 2 : 0,
                        ),
                        if (!p.amoled)
                          const BoxShadow(
                            color: Color(0x55000000),
                            blurRadius: 14,
                            offset: Offset(0, 6),
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
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    _Pill(p: p, text: '↓ ${fmtBytes(t?['Down'] ?? 0)}/с'),
                    _Pill(p: p, text: '↑ ${fmtBytes(t?['Up'] ?? 0)}/с'),
                  ],
                ),
                // Always reserve the graph when connected so the card never looks empty.
                if (on && !wide)
                  SizedBox(
                    height: 40,
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: LiveGraph(
                        series: c.speed,
                        p: p,
                        active: c.animSmooth,
                      ),
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

/// Wide layout: big live speed graph with totals under the connect card.
/// Marks where the wide layout puts the flexing graph card.
class _GraphSlot extends StatelessWidget {
  const _GraphSlot();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _GraphCard extends StatelessWidget {
  final NoxController c;
  final Pal p;
  const _GraphCard({required this.c, required this.p});
  @override
  Widget build(BuildContext context) {
    final t = c.traffic;
    final on = c.connected && t != null;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: _box(p, r: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Скорость',
                style: TextStyle(
                  color: p.sub,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 12),
              if (on)
                Expanded(
                  child: Text(
                    'за сеанс: ↓ ${fmtBytes(t['DownTotal'] ?? 0)}  ↑ ${fmtBytes(t['UpTotal'] ?? 0)}',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(color: p.sub, fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: LiveGraph(
              series: c.speed,
              p: p,
              active: on && c.animSmooth,
              span: 120,
              labels: true,
            ),
          ),
        ],
      ),
    );
  }
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

/// 0.7.x «конверт»: always in the header; red badge when an update is available.
class _MailBtn extends StatelessWidget {
  final NoxController c;
  final Pal p;
  const _MailBtn({required this.c, required this.p});
  @override
  Widget build(BuildContext context) {
    final has = c.s['update'] is Map;
    return _GhostBtn(
      key: TourKeys.mail,
      p: p,
      icon: has ? Icons.mark_email_unread_outlined : Icons.mail_outline,
      tint: has ? p.acc2 : null,
      badge: has,
      tip: has ? 'Доступно обновление' : 'Обновления и сообщения',
      onTap: () => updateSheet(context, c, p),
    );
  }
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
            onPressed: () => openUpdate(context, c, p),
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
  const _SubBlock({
    super.key,
    required this.c,
    required this.p,
    required this.b,
  });
  @override
  Widget build(BuildContext context) {
    final n = c.servers.where((s) => s['subId'] == b['id']).length;
    final used = ((b['upload'] ?? 0) as num) + ((b['download'] ?? 0) as num);
    final total = (b['total'] ?? 0) as num;
    final expire = (b['expire'] ?? 0) as int;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final left = expire > 0 ? (expire - now) / 86400 : null;
    final days = left == null ? null : math.max(0, left.ceil());
    final ann = (b['announce'] ?? '') as String;
    final expireTxt = left == null
        ? 'Бессрочно'
        : left <= 0
        ? 'Истекла'
        : '$days ${plural(days!, 'д', 'д', 'д')}';
    final trafficTxt = total > 0
        ? '${fmtBytes(used)} / ${fmtBytes(total)}'
        : 'без лимита';
    final bar = total > 0 ? math.min(1.0, used / total) : 1.0;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: _box(p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: ClipRect(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LayoutBuilder(
                        builder: (_, box) => Row(
                          children: [
                            // Expiry has priority: never ellipsized; only at extreme
                            // scales (wider than the whole row) it scales down to fit.
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: math.max(0, box.maxWidth - 12),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  expireTxt,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: TextStyle(
                                    color: left != null && left <= 0
                                        ? p.red
                                        : (left != null && left <= 3
                                              ? p.amb
                                              : p.txt),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '$n серв.',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.sub, fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                trafficTxt,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: TextStyle(color: p.ter, fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: bar,
                          minHeight: 3,
                          backgroundColor: p.chip,
                          color: p.acc,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
              _IconBtn(
                p: p,
                icon: Icons.more_vert,
                tip: 'Ещё',
                onTap: () => subSheet(context, c, p, b),
              ),
            ],
          ),
          if (ann.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: p.acc.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(ann, style: TextStyle(color: p.txt, fontSize: 11.5)),
            ),
          if ((b['webPage'] ?? '') != '' || (b['support'] ?? '') != '')
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Wrap(
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
      onTap: () async {
        if (await openUrl(url)) return;
        Clipboard.setData(ClipboardData(text: url));
        if (context.mounted) toast(context, 'Ссылка скопирована: $url');
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

/// One row: horizontally scrolling text tabs (small flags, accent text + underline when
/// selected, fade at the edges) and three fixed icon buttons on the right (ping-all,
/// refresh subscriptions, ⋮ which also shows «N из M · пинг: …»). D-pad friendly.
class _FilterBar extends StatefulWidget {
  final NoxController c;
  final Pal p;
  final int shown;
  const _FilterBar({required this.c, required this.p, required this.shown});
  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  final _sc = ScrollController();
  bool _fadeL = false, _fadeR = true;

  @override
  void initState() {
    super.initState();
    _sc.addListener(_edges);
    WidgetsBinding.instance.addPostFrameCallback((_) => _edges());
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  void _edges() {
    if (!_sc.hasClients || !mounted) return;
    final m = _sc.position;
    final l = m.pixels > 2, r = m.pixels < m.maxScrollExtent - 2;
    if (l != _fadeL || r != _fadeR) setState(() => (_fadeL = l, _fadeR = r));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c, p = widget.p;
    final cs = c.chips(), cat = c.category;
    final s = c.s;
    final pinging = s['pinging'] == true;
    final ts = MediaQuery.textScalerOf(context);
    final h = ts.scale(13) + 24; // text + paddings + indicator
    WidgetsBinding.instance.addPostFrameCallback((_) => _edges());
    final strip = ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => LinearGradient(
        colors: [
          _fadeL ? Colors.transparent : Colors.white,
          Colors.white,
          Colors.white,
          _fadeR ? Colors.transparent : Colors.white,
        ],
        stops: const [0, .06, .90, 1],
      ).createShader(r),
      child: ListView.builder(
        controller: _sc,
        scrollDirection: Axis.horizontal,
        itemCount: cs.length,
        itemBuilder: (_, i) {
          final (k, t, iso) = cs[i];
          return _Tab(
            p: p,
            text: t,
            iso: iso,
            on: k == cat,
            onTap: () => c.setPref('cat', k),
          );
        },
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(key: TourKeys.tabs, height: h, child: strip),
              ),
              const SizedBox(width: 4),
              _IconBtn(
                key: TourKeys.ping,
                p: p,
                small: true,
                icon: Icons.bolt,
                tip: 'Пинг',
                onTap: () {
                  c.ping(c.visible().map((e) => e['id'] as String).toList());
                  toast(context, 'Проверяю пинг…');
                },
              ),
              _IconBtn(
                key: TourKeys.refresh,
                p: p,
                small: true,
                icon: Icons.refresh,
                tip: 'Обновить подписки',
                onTap: () async {
                  toast(context, 'Обновляю подписки…');
                  final r = await c.call('RefreshSubs');
                  await c.refresh();
                  if (context.mounted) {
                    toast(context, (r ?? 'Готово').toString());
                  }
                },
              ),
              _IconBtn(
                key: TourKeys.more,
                p: p,
                small: true,
                icon: Icons.more_vert,
                tip: 'Ещё',
                onTap: () => listSheet(
                  context,
                  c,
                  p,
                  caption: listCaption(c, widget.shown),
                ),
              ),
            ],
          ),
          // hairline under the strip; ping progress as a tiny caption only while pinging
          Container(height: 1, color: p.line.withValues(alpha: .6)),
          if (pinging)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Пинг ${s['pingDone']}/${s['pingAll']}…',
                style: TextStyle(color: p.sub, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

/// «25 из 25 · пинг: через прокси» (shown in the ⋮ list sheet).
String listCaption(NoxController c, int shown) =>
    '$shown из ${c.servers.length} · пинг: ${c.settings['pingMode'] == 'tcp' ? 'TCP' : 'через прокси'}';

class _Tab extends StatelessWidget {
  final Pal p;
  final String text;
  final String? iso;
  final bool on;
  final VoidCallback onTap;
  const _Tab({
    required this.p,
    required this.text,
    required this.iso,
    required this.on,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    selected: on,
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      focusColor: p.acc.withValues(alpha: .22),
      hoverColor: p.acc.withValues(alpha: .10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: IntrinsicWidth(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (iso != null && hasFlag(iso!)) ...[
                    ClipOval(
                      child: SvgPicture.asset(
                        'assets/flags/${iso!.toLowerCase()}.svg',
                        width: 14,
                        height: 14,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    text,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: on ? p.acc2 : p.sub,
                      fontSize: 13,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 2.5,
                decoration: BoxDecoration(
                  color: on ? p.acc2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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

class _Tap extends StatefulWidget {
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
  State<_Tap> createState() => _TapState();
}

class _TapState extends State<_Tap> {
  bool focused = false;
  @override
  Widget build(BuildContext context) {
    final w = widget, p = w.p;
    return Material(
      color: w.sel ? p.sel : p.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        // D-pad / keyboard focus: a clear ring, not only the ink overlay (TV)
        side: BorderSide(
          color: focused ? p.acc2 : (w.sel ? p.acc : p.line),
          width: focused ? 2.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        focusColor: p.acc.withValues(alpha: .18),
        onFocusChange: (f) => setState(() => focused = f),
        onTap: w.onTap,
        onLongPress: w.onLong,
        onSecondaryTap: w.onLong,
        child: Padding(padding: w.padding, child: w.child),
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  final NoxController c;
  final Pal p;
  final J s;
  final bool first; // carries the tour target
  const _ServerRow({
    required this.c,
    required this.p,
    required this.s,
    this.first = false,
  });
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
            key: first ? TourKeys.server : null,
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
  final bool first;
  const _ServerCard({
    required this.c,
    required this.p,
    required this.s,
    this.first = false,
  });
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
              key: first ? TourKeys.server : null,
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
  return _SheetItem(
    p: p,
    onTap: onTap,
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
  );
}

/// Sheet row. The sheet body is an opaque container above the Material, so InkWell's
/// own focus ink would be hidden: draw the D-pad focus (TV, keyboard) here instead.
class _SheetItem extends StatefulWidget {
  final Pal p;
  final VoidCallback? onTap;
  final Widget child;
  const _SheetItem({required this.p, required this.onTap, required this.child});
  @override
  State<_SheetItem> createState() => _SheetItemState();
}

class _SheetItemState extends State<_SheetItem> {
  bool _f = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    return InkWell(
      onTap: widget.onTap,
      focusColor: Colors.transparent,
      onFocusChange: (v) => setState(() => _f = v),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        decoration: BoxDecoration(
          color: _f ? p.acc.withValues(alpha: .18) : null,
          border: _f
              ? Border.all(color: p.acc, width: 2)
              : Border(bottom: BorderSide(color: p.line)),
          borderRadius: _f ? BorderRadius.circular(10) : null,
        ),
        child: widget.child,
      ),
    );
  }
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

void updateSheet(BuildContext context, NoxController c, Pal p) async {
  // Re-check like 0.7.x Mail.open so a fresh publish is not missed.
  final msg = await c.call('CheckUpdateMsg');
  await c.refresh();
  if (!context.mounted) return;
  final u = c.s['update'];
  if (u is Map) {
    final m = u.cast<String, dynamic>();
    final v = '${m['versionName']}';
    final notes = '${m['notes'] ?? ''}';
    sheet(
      context,
      p,
      'Доступна версия $v',
      (ctx) => [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            notes.isEmpty ? 'Установлена ${c.s['version']}.' : notes,
            style: TextStyle(color: p.sub, fontSize: 13),
          ),
        ),
        item(
          p,
          'Обновить',
          onTap: () {
            Navigator.pop(ctx);
            openUpdate(context, c, p);
          },
        ),
        item(
          p,
          'Позже',
          onTap: () async {
            Navigator.pop(ctx);
            await c.call('HideUpdate', [v]);
            c.refresh();
          },
        ),
      ],
    );
  } else {
    toast(context, msg is String ? msg : 'У вас последняя версия');
  }
}

void scaleSheet(
  BuildContext context,
  NoxController c,
  Pal p, {
  required bool font,
}) {
  final key = font ? 'fontScale' : 'uiScale';
  final lo = font ? 0.85 : 0.80;
  final hi = 1.30;
  final title = font ? 'Размер шрифта' : 'Масштаб интерфейса';
  final def = c.isTv ? (font ? 1.1 : 1.15) : 1.0;
  final live = ValueNotifier<double>(font ? c.fontScale : c.uiScale);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: p.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: ValueListenableBuilder<double>(
          valueListenable: live,
          builder: (_, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: p.txt,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                font
                    ? 'Только текст (${(v * 100).round()}%). На TV по умолчанию чуть крупнее.'
                    : 'Кнопки, отступы и карточки (${(v * 100).round()}%). На TV по умолчанию 115%.',
                style: TextStyle(color: p.sub, fontSize: 12),
              ),
              // Live preview of the chosen scale on this label
              Text(
                'Пример: Лондон · VLESS XHTTP',
                style: TextStyle(
                  color: p.txt,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Slider(
                value: v,
                min: lo,
                max: hi,
                divisions: ((hi - lo) / 0.05).round(),
                activeColor: p.acc,
                label: '${(v * 100).round()}%',
                onChanged: (x) {
                  live.value = x;
                  // preview immediately without RPC storm: patch ui in memory
                  c.setPrefLive(key, x.toStringAsFixed(2));
                },
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      live.value = def;
                      c.setPrefLive(key, def.toStringAsFixed(2));
                    },
                    child: Text('Сбросить', style: TextStyle(color: p.sub)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'Готово',
                      style: TextStyle(
                        color: p.acc2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  ).whenComplete(live.dispose);
}

void settingsSheet(BuildContext context, NoxController c, Pal p) {
  sheet(context, p, 'Настройки', (ctx) {
    final s = c.settings;
    Widget swItem(String k, String t, [String? d]) => item(
      p,
      t,
      desc: d,
      trailing: sw(p, s[k] == true),
      onTap: () async {
        Navigator.pop(ctx);
        await c.saveSettings({k: !(s[k] == true)});
        // routing is part of the running config: reconnect to apply now
        const live = {'directRu', 'ruApps', 'blockAds', 'ipv6'};
        if (live.contains(k) && c.connected) {
          await c.call('Disconnect');
          await c.call('Connect');
        }
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
      if (canSplitApps)
        item(
          p,
          'Приложения через VPN',
          desc: splitDesc(s),
          arrow: true,
          onTap: () {
            Navigator.pop(ctx);
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => SplitAppsPage(c: c)));
          },
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 2),
        child: Text(
          'Маршрутизация',
          style: TextStyle(
            color: p.acc2,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      swItem(
        'directRu',
        'Российские сайты напрямую',
        '.ru .рф .su, Госуслуги, банки, Яндекс, VK, маркетплейсы и российские IP — мимо VPN',
      ),
      if (canSplitApps)
        swItem(
          'ruApps',
          'Российские приложения напрямую',
          'Банки, Госуслуги, Ozon, Wildberries, онлайн-кинотеатры… — мимо VPN',
        ),
      swItem('blockAds', 'Блокировка рекламы'),
      item(
        p,
        'Свои правила',
        desc: domainsDesc(s),
        arrow: true,
        onTap: () {
          Navigator.pop(ctx);
          domainsSheet(context, c, p);
        },
      ),
      const SizedBox(height: 10),
      swItem(
        'autoSwitch',
        'Автопереключение при блокировке',
        'Каждые 20 с проверка через туннель; после 3 неудач — переход на рабочий сервер (сначала та же страна, другой протокол)',
      ),
      swItem('autoConnect', 'Автоподключение при запуске'),
      swItem('autostart', 'Запуск вместе с системой'),
      item(
        p,
        'Размер шрифта',
        desc: '${(c.fontScale * 100).round()}%',
        arrow: true,
        onTap: () {
          Navigator.pop(ctx);
          scaleSheet(context, c, p, font: true);
        },
      ),
      item(
        p,
        'Масштаб интерфейса',
        desc: '${(c.uiScale * 100).round()}%',
        arrow: true,
        onTap: () {
          Navigator.pop(ctx);
          scaleSheet(context, c, p, font: false);
        },
      ),
      item(
        p,
        'Плавные анимации (60fps+)',
        desc: 'График на частоте экрана; выключите для экономии на слабых устройствах',
        trailing: sw(p, c.animSmooth),
        onTap: () {
          c.setPref('anim60', c.animSmooth ? '0' : '1');
          Navigator.pop(ctx);
        },
      ),
      item(
        p,
        'Показать подсказки снова',
        desc: 'Короткий тур: где что находится',
        arrow: true,
        onTap: () {
          Navigator.pop(ctx);
          c.replayTour();
        },
      ),
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
        desc: 'Время TCP-подключения к серверу напрямую, мимо VPN (и когда VPN включён). Быстрый TCP ≠ рабочий туннель.',
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

void listSheet(
  BuildContext context,
  NoxController c,
  Pal p, {
  String? caption,
}) {
  sheet(context, p, 'Список', (ctx) {
    final h = c.flag('hideDead', true),
        d = c.flag('dedup', true),
        v = c.pref('view', 'list');
    final undo = (c.s['canUndo'] ?? 0) as int;
    return [
      if (caption != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(caption, style: TextStyle(color: p.sub, fontSize: 12.5)),
        ),
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
        'Обновлено: ${ago((b['updated'] ?? 0) as int)}',
        desc: (b['name'] ?? '') as String,
      ),
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
      for (final send in c.isTv ? [false, true] : [true, false])
        send
            ? item(
                p,
                'Передать на ТВ',
                desc: 'Подписки и серверы на ТВ в этой же Wi‑Fi сети',
                arrow: true,
                onTap: () {
                  Navigator.pop(ctx);
                  openSend(context, c);
                },
              )
            : item(
                p,
                'Принять с телефона',
                desc: 'QR-код и код для передачи профилей с другого устройства',
                arrow: true,
                onTap: () {
                  Navigator.pop(ctx);
                  openReceive(context, c);
                },
              ),
      const SizedBox(height: 12),
      TextField(
        controller: tc,
        maxLines: 5,
        style: TextStyle(color: p.txt),
        decoration: InputDecoration(
          hintText: 'Ссылка на подписку, vless://, trojan://, ss://, hy2://, tuic://, qwdtt://, sstp://user:pass@host:443#Имя',
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
      // QR import: camera on Android phones; image file / clipboard picture on desktop
      if (!c.isTv)
        Row(
          children: [
            if (isAndroid)
              Expanded(
                child: _Btn(
                  p: p,
                  secondary: true,
                  label: 'Сканировать QR-код',
                  onTap: () => _qrInto(context, tc, scanQr),
                ),
              )
            else ...[
              Expanded(
                child: _Btn(
                  p: p,
                  secondary: true,
                  label: 'QR из файла',
                  onTap: () => _qrInto(context, tc, qrFromFile),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Btn(
                  p: p,
                  secondary: true,
                  label: 'QR из буфера',
                  onTap: () => _qrInto(context, tc, qrFromClipboard),
                ),
              ),
            ],
          ],
        ),
      if (!c.isTv) const SizedBox(height: 10),
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

String domainsDesc(Map<String, dynamic> s) {
  final d = ((s['directDomains'] as List?) ?? []).length;
  final x = ((s['proxyDomains'] as List?) ?? []).length;
  if (d == 0 && x == 0) return 'Свои сайты напрямую или через VPN';
  return 'Напрямую: $d · через VPN: $x';
}

/// Custom domain lists: one per line; suffix match (site.ru also covers www.site.ru).
void domainsSheet(BuildContext context, NoxController c, Pal p) {
  String join(String k) =>
      ((c.settings[k] as List?) ?? const []).map((e) => '$e').join('\n');
  final direct = TextEditingController(text: join('directDomains'));
  final proxy = TextEditingController(text: join('proxyDomains'));
  List<String> lines(TextEditingController t) => t.text
      .split(RegExp(r'[\n,; ]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  InputDecoration dec(String h) => InputDecoration(
    hintText: h,
    hintStyle: TextStyle(color: p.ter, fontSize: 13),
    filled: true,
    fillColor: p.chip,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: p.line),
    ),
  );
  sheet(
    context,
    p,
    'Свои правила',
    (ctx) => [
      Text(
        'По одному сайту в строке. Правило действует и на поддомены. «Через VPN» сильнее, чем «Российские сайты напрямую».',
        style: TextStyle(color: p.sub, fontSize: 12),
      ),
      const SizedBox(height: 12),
      Text('Напрямую (мимо VPN)', style: TextStyle(color: p.txt)),
      const SizedBox(height: 6),
      TextField(
        controller: direct,
        minLines: 2,
        maxLines: 6,
        style: TextStyle(color: p.txt),
        decoration: dec('example.com\nмойсайт.рф'),
      ),
      const SizedBox(height: 12),
      Text('Всегда через VPN', style: TextStyle(color: p.txt)),
      const SizedBox(height: 6),
      TextField(
        controller: proxy,
        minLines: 2,
        maxLines: 6,
        style: TextStyle(color: p.txt),
        decoration: dec('kinopoisk.ru'),
      ),
      const SizedBox(height: 14),
      _Btn(
        p: p,
        label: 'Сохранить',
        onTap: () async {
          Navigator.pop(ctx);
          await c.saveSettings({
            'directDomains': lines(direct),
            'proxyDomains': lines(proxy),
          });
          if (c.connected) {
            await c.call('Disconnect');
            await c.call('Connect');
          }
          if (context.mounted) toast(context, 'Правила сохранены');
        },
      ),
    ],
  );
}

/// Reads a QR (camera / file / clipboard) and appends its text to the link field.
Future<void> _qrInto(
  BuildContext context,
  TextEditingController tc,
  Future<String?> Function() src,
) async {
  final r = await src();
  if (r == null || !context.mounted) return;
  if (r.startsWith('error:')) {
    toast(context, qrError(r));
    return;
  }
  final t = r.trim();
  if (t.toLowerCase().startsWith('nox://pair')) {
    toast(
      context,
      'Это QR для передачи профилей — используйте «Принять с телефона»',
    );
    return;
  }
  tc.text = tc.text.trim().isEmpty ? t : '${tc.text.trim()}\n$t';
  toast(context, 'Ссылка из QR-кода вставлена');
}
