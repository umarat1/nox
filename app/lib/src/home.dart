import 'dart:convert';
import 'dart:ui' as ui;
import 'split_apps.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'controller.dart';
import 'country_groups.dart';
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
        final p = Pal.of(
          c.settings['theme'] as String?,
          c.pref('tpl', 'glass'),
        );
        vol3d = vol3dFromUi(c.ui);
        graphStyle = graphFromUi(c.ui);
        return Theme(
          data: materialTheme(p),
          child: Scaffold(
            backgroundColor: p.bg,
            body: _WithTitleBar(
              p: p,
              child: PairGlue(
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
                          // 2.1: Windows/macOS keep the phone layout at any window size (as on Android)
                          final wide = c.isTv && box.maxWidth >= 640;
                          // 2.2.2: Windows/macOS: mobile column; from 860 dp (maximized /
                          // fullscreen) two mobile-style panes: card + subscriptions | servers.
                          final split = isSplit(c, box.maxWidth);
                          return Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: wide || split ? double.infinity : 560,
                              ),
                              child: _Body(
                                c: c,
                                p: p,
                                wide: wide,
                                split: split,
                                w: box.maxWidth,
                                h: box.maxHeight,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // 2.1.7: «＋» moved from the top bar to the bottom of the screen (TV keeps it
                    // in the header for the D-pad).
                    // 2.1.8: bottom bar, left to right: «＋», «Добавить из буфера» (only while
                    // nothing is added), then the connect pill filling the rest. It floats over
                    // the server list (which keeps bottom padding for it).
                    if (showAddFab(c))
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SafeArea(
                          top: false,
                          child: LayoutBuilder(
                            builder: (_, box) {
                              final bar = BottomBar(c: c, p: p);
                              if (isSplit(c, box.maxWidth)) {
                                // two panes: the bar sits under the left column
                                return Align(
                                  alignment: Alignment.bottomLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      left: _splitPad - 14,
                                    ),
                                    child: SizedBox(
                                      width: splitLeftW(box.maxWidth) + 28,
                                      child: bar,
                                    ),
                                  ),
                                );
                              }
                              return Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 560,
                                  ),
                                  child: bar,
                                ),
                              );
                            },
                          ),
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
          ),
        );
      },
    );
  }
}

const _splitPad = 18.0, _splitGap = 18.0;

/// Desktop (Windows/macOS) window wide enough for the two-pane mobile-style layout.
bool isSplit(NoxController c, double w) => desktopUi && !c.isTv && w >= 860;

/// Width of the left pane (connection card, banners, subscriptions, bottom bar).
double splitLeftW(double w) => (w * .40).clamp(380.0, 500.0);

/// 2.2.2 Windows: frameless window with a slim title bar in the app colours
/// (drag to move, double-click to maximize, ⎯ ▢ ✕; ✕ hides to the tray). Gone in fullscreen.
class _WithTitleBar extends StatelessWidget {
  final Pal p;
  final Widget child;
  const _WithTitleBar({required this.p, required this.child});
  @override
  Widget build(BuildContext context) {
    if (!customTitleBar && !debugTitleBar) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: fullScreen,
      builder: (_, fs, _) => fs
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WinTitleBar(p: p),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: child,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Widget tests / screenshots: draw the Windows title bar on other hosts.
bool debugTitleBar = false;

class WinTitleBar extends StatelessWidget {
  final Pal p;
  const WinTitleBar({super.key, required this.p});
  static const height = 34.0;
  @override
  Widget build(BuildContext context) {
    Widget btn(
      IconData i,
      String tip,
      VoidCallback onTap, {
      bool close = false,
    }) => _TitleBtn(p: p, icon: i, tip: tip, onTap: onTap, close: close);
    return Container(
      key: const Key('win-title-bar'),
      height: height,
      color: p.bg,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => winStartDrag(),
              onDoubleTap: winToggleMaximize,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.asset(
                        'assets/icon.png',
                        width: 18,
                        height: 18,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Nox',
                      style: TextStyle(
                        color: p.txt.withValues(alpha: .80),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          btn(Icons.remove_rounded, 'Свернуть', winMinimize),
          btn(Icons.crop_square_rounded, 'Развернуть', winToggleMaximize),
          btn(
            Icons.close_rounded,
            'Закрыть (Nox останется в трее)',
            winClose,
            close: true,
          ),
        ],
      ),
    );
  }
}

class _TitleBtn extends StatefulWidget {
  final Pal p;
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final bool close;
  const _TitleBtn({
    required this.p,
    required this.icon,
    required this.tip,
    required this.onTap,
    this.close = false,
  });
  @override
  State<_TitleBtn> createState() => _TitleBtnState();
}

class _TitleBtnState extends State<_TitleBtn> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final bg = !_hover
        ? Colors.transparent
        : widget.close
        ? const Color(0xFFE81123)
        : p.txt.withValues(alpha: .08);
    return Tooltip(
      message: widget.tip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: 46,
            height: WinTitleBar.height,
            color: bg,
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: widget.icon == Icons.crop_square_rounded ? 14 : 17,
              color: _hover && widget.close
                  ? Colors.white
                  : p.txt.withValues(alpha: .75),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> finishRefresh(
  BuildContext context,
  NoxController c,
  dynamic r,
) async {
  await c.refresh();
  if (!context.mounted) return;
  if (r is String && r.isNotEmpty) {
    toast(context, r);
  } else if (c.fatal != null && c.fatal!.isNotEmpty) {
    toast(context, c.fatal!);
  } else if (r == null) {
    toast(context, 'Не удалось обновить');
  } else {
    toast(context, 'Обновлено');
  }
}

void toast(BuildContext ctx, String t) {
  ScaffoldMessenger.of(ctx)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(t, maxLines: 3, overflow: TextOverflow.ellipsis),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xDD000000),
      ),
    );
}

class _Body extends StatefulWidget {
  final NoxController c;
  final Pal p;
  final bool wide;
  final bool split; // 2.2.2 desktop: two mobile-style panes
  final double w, h;
  const _Body({
    required this.c,
    required this.p,
    this.wide = false,
    this.split = false,
    this.w = 0,
    this.h = 0,
  });

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final GlobalKey _compactKey = GlobalKey();
  double? _baseViewHeight;
  double? _appliedViewHeight;

  NoxController get c => widget.c;
  Pal get p => widget.p;
  bool get wide => widget.wide;
  bool get split => widget.split;
  double get w => widget.w;
  double get h => widget.h;

  void _scheduleSizeSync(bool hdrCol, bool subCol, bool srvCol) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (c.isTv) return;
      // 2.2.2 desktop: collapsing a card no longer shrinks the window
      if (desktopUi) return;
      final rv = RendererBinding.instance.renderViews.firstOrNull;
      if (rv == null || !rv.hasConfiguration) return;
      final curH = rv.size.height;
      final anyCol = hdrCol || subCol || srvCol;
      if (_baseViewHeight == null ||
          (!anyCol && _appliedViewHeight == null) ||
          ((_appliedViewHeight == null ||
                  (curH - _appliedViewHeight!).abs() > 2.0) &&
              curH > (_baseViewHeight ?? 0))) {
        _baseViewHeight = curH;
      }
      final baseH = _baseViewHeight ?? curH;
      double? targetH;
      if (srvCol) {
        final rb = _compactKey.currentContext?.findRenderObject() as RenderBox?;
        if (rb != null && rb.hasSize && rb.size.height > 0) {
          final mq = MediaQuery.maybeOf(context);
          final safeV = mq != null ? (mq.padding.top + mq.padding.bottom) : 0.0;
          targetH = ((rb.size.height + safeV) * c.uiScale).ceilToDouble();
        }
      } else if (hdrCol || subCol) {
        final subCount = c.subs.isEmpty ? 1 : c.subs.length;
        final saved =
            ((hdrCol ? 36.0 : 0.0) + (subCol ? 148.0 * subCount : 0.0)) *
            c.uiScale;
        targetH = (baseH - saved).clamp(320.0, baseH);
      }

      final desiredViewH = targetH ?? baseH;
      if ((desiredViewH - curH).abs() > 1.0 &&
          (_appliedViewHeight == null ||
              (_appliedViewHeight! - desiredViewH).abs() > 1.0 ||
              targetH == null)) {
        _appliedViewHeight = targetH;
        final dpr = rv.configuration.devicePixelRatio;
        final curW = rv.size.width;
        rv.configuration = ViewConfiguration(
          logicalConstraints: BoxConstraints.tight(Size(curW, desiredViewH)),
          physicalConstraints: BoxConstraints.tight(
            Size(curW * dpr, desiredViewH * dpr),
          ),
          devicePixelRatio: dpr,
        );
        WidgetsBinding.instance.scheduleFrame();
      } else if (targetH == null) {
        _appliedViewHeight = null;
      }
      syncWindowCollapse(compactHeight: targetH, viewportHeight: baseH);
    });
  }

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
    if (c.pref('panel', '') == 'text') {
      _scheduleSizeSync(false, false, false);
      return _TextPanel(c: c, p: p);
    }
    final view = c.pref('view', 'list');
    final list = c.visible();
    final mobile = !c.isTv;
    final phone = !wide;
    final hdrCol = mobile && c.flag('hdrCol', false);
    final subCol = mobile && c.flag('subCol', false);
    // Phone column stays open: a saved collapse and the chip chevron are desktop-only.
    final srvCol = !phone && !desktopUi && mobile && c.flag('srvCol', false);
    _scheduleSizeSync(hdrCol, subCol, srvCol);
    if (c.s['update'] is Map) maybeOfferUpdate(context, c, p);
    final head = <Widget>[
      // 2.2.0: no top bar on Android; МТС, mail and settings sit in the connection card's corner (_HeroCorner).
      if (!wide && !srvCol && !noTopBar)
        _TopBar(
          c: c,
          p: p,
          mobile: true,
          collapsed: hdrCol,
          onToggleCollapse: () => c.setPrefLive('hdrCol', hdrCol ? '0' : '1'),
        ),
      _Hero(c: c, p: p, wide: wide),
      if (wide) const _GraphSlot(),
      if (c.vpnDenied)
        _Banner(
          p: p,
          text:
              'Нужно разрешение на VPN: нажмите кнопку питания и подтвердите системный запрос.',
          color: p.red,
          onTap: () {
            c.vpnDenied = false;
            c.refresh();
          },
        ),
      if (c.captcha != null && canCaptcha && !c.captchaOpen)
        _Banner(
          p: p,
          text:
              'qWDTT: VK просит пройти проверку «я не робот». Нажмите, чтобы открыть.',
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
        _SubBlock(
          key: i == 0 ? TourKeys.sub : null,
          c: c,
          p: p,
          b: b,
          first: i == 0,
          mobile: mobile,
          collapsed: subCol,
          onToggleCollapse: mobile
              ? () => c.setPrefLive('subCol', subCol ? '0' : '1')
              : null,
        ),
    ];
    final listHead = <Widget>[
      _FilterBar(
        c: c,
        p: p,
        shown: list.length,
        mobile: mobile,
        collapsed: srvCol,
        onToggleCollapse: phone
            ? null
            : mobile
            ? () => c.setPrefLive('srvCol', srvCol ? '0' : '1')
            : null,
      ),
    ];
    final servers = _serverSlivers(context, list, view);
    if (split) {
      // 2.2.2 desktop, wide window / fullscreen: the phone UI in two panes. Left: the
      // connection card (corner buttons), banners and subscriptions, bottom bar under it.
      // Right: the server accordion with its pinned list header.
      final leftW = splitLeftW(w);
      final hero = head.firstWhere((x) => x is _Hero);
      final rest = [
        for (final x in head)
          if (x is! _Hero && x is! _TopBar && x is! _GraphSlot) x,
      ];
      return Padding(
        padding: const EdgeInsets.fromLTRB(_splitPad, 12, _splitPad, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: leftW,
              child: FocusTraversalGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    hero,
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.only(
                          bottom: showAddFab(c) ? 96 : 16,
                        ),
                        children: rest,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: _splitGap),
            Expanded(
              child: FocusTraversalGroup(
                child: CustomScrollView(
                  slivers: [
                    PinnedHeaderSliver(
                      child: ColoredBox(
                        color: p.bg,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: listHead,
                        ),
                      ),
                    ),
                    ...servers,
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (wide && !c.isTv) {
      // 1.0.20+ desktop: top row = connection card (left) + speed graph stretching the rest of
      // the width; below, full-width scroll with banners, subscriptions, filters and a grid of
      // server cards.
      const pad = 20.0, gap = 16.0;
      final heroW = (w * .36).clamp(380.0, 520.0);
      final hero = head.firstWhere((x) => x is _Hero);
      final rest = [
        for (final x in head)
          if (x is! _Hero && x is! _GraphSlot) x,
      ];
      final topRow = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: heroW, child: hero),
            const SizedBox(width: gap),
            Expanded(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: srvCol ? 172 : 210),
                child: _GraphCard(c: c, p: p, marginTop: 0),
              ),
            ),
          ],
        ),
      );
      if (srvCol) {
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Padding(
            key: _compactKey,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(
                  c: c,
                  p: p,
                  mobile: true,
                  showFullScreen: canFullScreen,
                  collapsed: true,
                  onToggleCollapse: () {
                    c.setPrefLive('srvCol', '0');
                    c.setPrefLive('hdrCol', '0');
                  },
                ),
                topRow,
                ...rest,
                ...listHead,
              ],
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopBar(
              c: c,
              p: p,
              mobile: true,
              showFullScreen: canFullScreen,
              collapsed: hdrCol,
              onToggleCollapse: () =>
                  c.setPrefLive('hdrCol', hdrCol ? '0' : '1'),
            ),
            topRow,
            const SizedBox(height: 12),
            Expanded(
              child: FocusTraversalGroup(
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      sliver: SliverList.list(children: rest),
                    ),
                    PinnedHeaderSliver(
                      // 1.0.20: category tabs stay pinned while the list scrolls
                      child: ColoredBox(
                        color: p.bg,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: listHead,
                        ),
                      ),
                    ),
                    ..._serverSlivers(context, list, 'grid'),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (wide) {
      // TV: two columns sharing top and bottom edges, equal outer padding (pad) on every side:
      // left = connect card, live graph (flexes to fill), subscriptions; right = one panel
      // with filters on top and the server list scrolling inside it.
      const pad = 20.0, gap = 16.0;
      final leftW = (w * .34).clamp(390.0, 540.0);
      final graph = _GraphCard(c: c, p: p);
      final banners = head.length - 2 - c.subs.length; // between hero and graph
      final need = 140 + 230 + 60.0 * banners + 225.0 * c.subs.length;
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
    if (srvCol) {
      return SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Padding(
          key: _compactKey,
          padding: EdgeInsets.fromLTRB(10, 6, 10, showAddFab(c) ? 90 : 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(
                c: c,
                p: p,
                mobile: true,
                collapsed: true,
                onToggleCollapse: () {
                  c.setPrefLive('srvCol', '0');
                  c.setPrefLive('hdrCol', '0');
                },
              ),
              for (final wdg in head)
                if (wdg is! _TopBar) wdg,
              ...listHead,
            ],
          ),
        ),
      );
    }
    final pinned = <Widget>[
      for (final wdg in head)
        if (wdg is _TopBar || wdg is _Hero) wdg,
    ];
    final scrollHead = <Widget>[
      for (final wdg in head)
        if (wdg is! _TopBar && wdg is! _Hero) wdg,
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
              PinnedHeaderSliver(
                // 1.0.20: category tabs stay pinned while the list scrolls
                child: ColoredBox(
                  color: p.bg,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: listHead,
                    ),
                  ),
                ),
              ),
              ...servers,
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _serverSlivers(BuildContext context, List<J> list, String view) {
    final h = wide
        ? const EdgeInsets.fromLTRB(14, 0, 14, 14)
        : split
        ? const EdgeInsets.fromLTRB(0, 0, 0, 18)
        : EdgeInsets.fromLTRB(12, 0, 12, showAddFab(c) ? 96 : 40);
    if (list.isEmpty) {
      // 2.1.7: nothing added yet → a big «Добавить из буфера»; it goes away with the first
      // subscription/server (a filter that hides everything keeps the plain hint).
      final none = c.subs.isEmpty && c.servers.isEmpty;
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              28,
              none ? 28 : 40,
              28,
              showAddFab(c) ? 100 : 40,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (none && !showAddFab(c)) ...[
                  ClipboardAddButton(c: c, p: p),
                  const SizedBox(height: 14),
                ],
                Text(
                  none
                      ? (showAddFab(c)
                            ? 'Скопируйте ссылку на подписку или сервер (vless, trojan, ss, hy2, tuic, qwdtt, sstp) и нажмите «Добавить из буфера» внизу. Другие способы — кнопка «＋».'
                            : 'Скопируйте ссылку на подписку или сервер (vless, trojan, ss, hy2, tuic, qwdtt, sstp) и нажмите кнопку выше. Другие способы — кнопка «＋» внизу.')
                      : 'Нет серверов. Нажмите «＋», чтобы добавить подписку или ссылку (vless, trojan, ss, hy2, tuic, qwdtt, sstp).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.sub),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    if (c.accordion) return _accordionSlivers(list, h);
    if (view == 'grid') {
      final ts = MediaQuery.textScalerOf(context);
      final cardH = math.max(104.0, ts.scale(64) + 40);
      return [
        SliverPadding(
          padding: h,
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 260,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              mainAxisExtent: cardH,
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
          padding: EdgeInsets.fromLTRB(0, 0, 0, showAddFab(c) ? 96 : 40),
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
              _ServerRow(c: c, p: p, s: list[i], first: i == 0, protocol: wide),
        ),
      ),
    ];
  }

  /// Android: «Автовыбор» on top, then one collapsible card per country (subscription order),
  /// entries grouped by protocol inside, qWDTT of that country last, «Другое» at the bottom.
  List<Widget> _accordionSlivers(List<J> list, EdgeInsets pad) {
    final tree = groupServers(list, order: c.allServers);
    final open = c.accOpen;
    var first = true;
    final kids = <Widget>[
      if (tree.auto.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 2, bottom: 8),
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 1),
          decoration: glassBox(p, r: 20, strength: .55),
          child: Column(
            children: [
              for (final (i, s) in tree.auto.indexed)
                _ServerRow(
                  c: c,
                  p: p,
                  s: s,
                  first: (first, first = false).$1,
                  protocol: false,
                  flat: true,
                  listMenu: i == 0 ? listCaption(c, list.length) : null,
                ),
            ],
          ),
        ),
      for (final g in tree.groups)
        _CountryCard(
          key: ValueKey('cc-${g.key}'),
          c: c,
          p: p,
          g: g,
          open: open[g.key] ?? g.has(c.selected),
          listMenu: tree.auto.isEmpty && g == tree.groups.first
              ? listCaption(c, list.length)
              : null,
          firstRow: (first, first = false).$1,
          onToggle: (v) => c.setAccOpen(g.key, v),
        ),
    ];
    return [
      SliverPadding(
        padding: pad,
        sliver: SliverList.list(children: kids),
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
          height: 108,
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

/// Volumetric round button: soft gradient sphere, glow, press-scale; optional spin while onTap runs.
/// ⚡ on the subscription card (phone). While a ping runs it turns into a pill with a
/// spinner and «41/69», so progress never needs its own row above the list.
class _PingOrb extends StatelessWidget {
  final NoxController c;
  final Pal p;
  final bool mobile;
  final VoidCallback onTap;
  const _PingOrb({
    super.key,
    required this.c,
    required this.p,
    required this.onTap,
    this.mobile = false,
  });
  @override
  Widget build(BuildContext context) {
    final s = c.s;
    if (s['pinging'] != true) {
      return _OrbBtn(
        p: p,
        icon: Icons.bolt_rounded,
        tip: 'Пинг',
        mobile: mobile,
        onTap: () async {
          onTap();
          toast(context, 'Проверяю пинг…');
        },
      );
    }
    final done = (s['pingDone'] ?? 0) as num, all = (s['pingAll'] ?? 0) as num;
    return Tooltip(
      message: 'Идёт пинг: $done из $all',
      child: Container(
        height: mobile ? 32 : 38,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: p.acc.withValues(alpha: .22),
          borderRadius: BorderRadius.circular(mobile ? 10 : 12),
          border: Border.all(color: p.acc.withValues(alpha: .60)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: all > 0 ? (done / all).clamp(0, 1).toDouble() : null,
                color: p.acc2,
                backgroundColor: p.acc2.withValues(alpha: .20),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$done/$all',
              style: TextStyle(
                color: p.txt,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrbBtn extends StatefulWidget {
  final Pal p;
  final IconData icon;
  final String tip;
  final Future<void> Function() onTap;
  final bool spinWhileBusy;
  final bool mobile;
  const _OrbBtn({
    super.key,
    required this.p,
    required this.icon,
    required this.tip,
    required this.onTap,
    this.spinWhileBusy = false,
    this.mobile = false,
  });
  @override
  State<_OrbBtn> createState() => _OrbBtnState();
}

class _OrbBtnState extends State<_OrbBtn> with SingleTickerProviderStateMixin {
  late final AnimationController spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool down = false, busy = false;
  @override
  void dispose() {
    spin.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    if (busy) return;
    if (widget.spinWhileBusy) {
      setState(() => busy = true);
      spin.repeat();
    }
    try {
      await widget.onTap();
    } finally {
      if (mounted && widget.spinWhileBusy) {
        spin.stop();
        spin.reset();
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final acc = p.acc;
    if (widget.mobile) {
      return Tooltip(
        message: widget.tip,
        child: GestureDetector(
          onTapDown: (_) => setState(() => down = true),
          onTapCancel: () => setState(() => down = false),
          onTapUp: (_) => setState(() => down = false),
          onTap: _tap,
          child: AnimatedScale(
            scale: down ? .90 : 1,
            duration: const Duration(milliseconds: 120),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: acc.withValues(
                  alpha: busy || down ? .22 : (p.light ? .10 : .15),
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: acc.withValues(
                    alpha: busy ? .60 : (p.light ? .22 : .32),
                  ),
                  width: 1,
                ),
              ),
              child: Center(
                child: RotationTransition(
                  turns: spin,
                  child: Icon(widget.icon, size: 18, color: p.acc2),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final top = Color.lerp(p.chip, Colors.white, p.light ? .5 : .10)!;
    final bot = p.amoled
        ? const Color(0xFF000000)
        : Color.lerp(p.chip, Colors.black, .25)!;
    return Tooltip(
      message: widget.tip,
      child: GestureDetector(
        onTapDown: (_) => setState(() => down = true),
        onTapCancel: () => setState(() => down = false),
        onTapUp: (_) => setState(() => down = false),
        onTap: _tap,
        child: AnimatedScale(
          scale: down ? .88 : 1,
          duration: const Duration(milliseconds: 120),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: vol3d
                  ? RadialGradient(
                      center: const Alignment(-.35, -.45),
                      radius: 1.0,
                      colors: [top, bot],
                    )
                  : null,
              color: vol3d ? null : p.chip,
              border: Border.all(
                color: (busy ? acc : p.line).withValues(alpha: vol3d ? .55 : 1),
                width: 1,
              ),
              boxShadow: vol3d
                  ? [
                      BoxShadow(
                        color: acc.withValues(alpha: busy || down ? .45 : .22),
                        blurRadius: busy || down ? 16 : 10,
                      ),
                      if (!p.amoled)
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .35),
                          offset: const Offset(0, 3),
                          blurRadius: 6,
                        ),
                    ]
                  : const [],
            ),
            child: Center(
              child: RotationTransition(
                turns: spin,
                child: Icon(widget.icon, size: 20, color: busy ? acc : p.txt),
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
            : !vol3d
            ? const []
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

class _CollapsedHeaderPill extends StatelessWidget {
  final Pal p;
  final VoidCallback onTap;
  const _CollapsedHeaderPill({required this.p, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Tooltip(
        message: 'Развернуть шапку',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: p.amoled
                    ? const Color(0xFF0A0A12)
                    : p.card.withValues(alpha: .92),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: p.amoled ? const Color(0xFF222230) : p.line,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
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
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .4,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: p.sub,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final NoxController c;
  final Pal p;
  final bool mobile;
  final bool showFullScreen;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;
  const _TopBar({
    required this.c,
    required this.p,
    this.mobile = false,
    this.showFullScreen = false,
    this.collapsed = false,
    this.onToggleCollapse,
  });
  @override
  Widget build(BuildContext context) {
    if (mobile && collapsed && onToggleCollapse != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _CollapsedHeaderPill(p: p, onTap: onToggleCollapse!),
      );
    }
    final th = (c.settings['theme'] ?? 'dark') as String;
    final logoText = Text.rich(
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
      style: TextStyle(
        fontSize: mobile ? 20 : 22,
        fontWeight: FontWeight.w800,
        letterSpacing: .5,
      ),
    );
    final Widget logo = mobile
        ? GestureDetector(
            onTap: onToggleCollapse,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: p.acc.withValues(alpha: p.light ? .09 : .15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: p.acc.withValues(alpha: p.light ? .22 : .32),
                  width: 1,
                ),
              ),
              child: logoText,
            ),
          )
        : logoText;
    // Equal Expanded sides keep the logo exactly centred whatever the button counts.
    final row = Row(
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (c.isTv) ...[
                  _GhostBtn(
                    key: TourKeys.add,
                    p: p,
                    icon: Icons.add_rounded,
                    tip: 'Добавить подписку',
                    mobile: mobile,
                    accent: mobile,
                    onTap: () => addSheet(context, c, p),
                  ),
                  SizedBox(width: mobile ? 6 : 2),
                ],
                // «МТС прокси» (Android only); «＋» is the bottom button on phones/desktop
                if (isAndroid) ...[
                  _MtsBtn(
                    p: p,
                    on: c.mtsOn,
                    onTap: () async {
                      final on = !c.mtsOn;
                      await c.setMtsProxy(on);
                      if (!context.mounted) return;
                      toast(
                        context,
                        on
                            ? 'МТС прокси включён: только AnyTLS, mieru, VLESS и прокси'
                            : 'МТС прокси выключен',
                      );
                      if (on) await mtsApnDialog(context);
                    },
                  ),
                  SizedBox(width: mobile ? 6 : 2),
                ],
                _GhostBtn(
                  key: TourKeys.theme,
                  p: p,
                  icon: th == 'light'
                      ? Icons.light_mode_outlined
                      : th == 'mono'
                      ? Icons.contrast_rounded
                      : Icons.dark_mode_outlined,
                  tip: 'Тема',
                  mobile: mobile,
                  onTap: () {
                    final i = themeNames.indexWhere((e) => e.$1 == th);
                    final n = themeNames[(i + 1) % themeNames.length].$1;
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
                if ((!mobile || showFullScreen) && canFullScreen) ...[
                  ValueListenableBuilder<bool>(
                    valueListenable: fullScreen,
                    builder: (_, fs, _) => _GhostBtn(
                      p: p,
                      icon: fs ? Icons.fullscreen_exit : Icons.fullscreen,
                      tip: fs
                          ? 'Выйти из полноэкранного режима (F11)'
                          : 'Во весь экран (F11)',
                      mobile: mobile,
                      onTap: () => toggleFullScreen(),
                    ),
                  ),
                  SizedBox(width: mobile ? 6 : 2),
                ],
                _MailBtn(c: c, p: p, mobile: mobile),
                SizedBox(width: mobile ? 6 : 2),
                _GhostBtn(
                  key: TourKeys.settings,
                  p: p,
                  icon: Icons.settings_outlined,
                  tip: 'Настройки',
                  mobile: mobile,
                  onTap: () => settingsSheet(context, c, p),
                ),
                if (mobile && onToggleCollapse != null) ...[
                  const SizedBox(width: 6),
                  _GhostBtn(
                    p: p,
                    icon: Icons.keyboard_arrow_up_rounded,
                    tip: 'Свернуть шапку',
                    mobile: true,
                    onTap: onToggleCollapse!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
    if (mobile) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: _box(p, r: 20),
        child: row,
      );
    }
    return Padding(padding: const EdgeInsets.fromLTRB(0, 2, 0, 8), child: row);
  }
}

/// 2.2.0: Android has no top bar (no «nox» wordmark); tests may flip this.
/// 2.2.2: neither do Windows/macOS (mobile UI).
bool noTopBar = isAndroid || desktopUi;

/// 2.2.2: protocol names (VLESS, Hysteria2…) are not shown on desktop: no protocol in the
/// connection card, no protocol chips/badges in the server list. Tests may flip this.
bool showProto = !desktopUi;

/// 2.2.2: desktop shows server names exactly as the subscription/config gives them
/// (no stripping of a leading flag emoji or country word). Tests may flip this.
bool rawNames = desktopUi;
String _dispName(String n) => rawNames ? n : dispName(n);
String _shortName(String n) => rawNames ? n : shortName(n);

/// 2.2.1: МТС, mail and settings as small glass buttons in the connection card's
/// top-right corner (Android, no top bar). Theme lives in Настройки → Тема.
class _HeroCorner extends StatelessWidget {
  final NoxController c;
  final Pal p;
  const _HeroCorner({required this.c, required this.p});

  /// Only on the phone column of Android-style layouts (tests flip [noTopBar]).
  static Widget? of(NoxController c, Pal p, {bool wide = false}) =>
      noTopBar && !wide && !c.isTv ? _HeroCorner(c: c, p: p) : null;

  Widget _btn({
    Key? key,
    required String tip,
    required VoidCallback onTap,
    IconData? icon,
    String? text,
    bool hot = false,
    bool dot = false,
    Color? fill,
  }) {
    final acc = p.acc;
    return Tooltip(
      key: key,
      message: tip,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 28,
                constraints: const BoxConstraints(minWidth: 28),
                padding: EdgeInsets.symmetric(horizontal: text != null ? 7 : 0),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fill ?? acc.withValues(alpha: p.light ? .10 : .16),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: fill ?? acc.withValues(alpha: p.light ? .22 : .34),
                  ),
                ),
                child: text != null
                    ? Text(
                        text,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: fill != null
                              ? Colors.white
                              : p.txt.withValues(alpha: .78),
                        ),
                      )
                    : Icon(
                        icon,
                        size: 15,
                        color: hot ? p.acc2 : p.txt.withValues(alpha: .85),
                      ),
              ),
              if (dot)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: p.acc2,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final upd = c.s['update'] is Map;
    return Row(
      key: const Key('hero-corner'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // МТС прокси works through the Android APN; desktop gets fullscreen instead
        if (desktopUi && canFullScreen) ...[
          ValueListenableBuilder<bool>(
            valueListenable: fullScreen,
            builder: (_, fs, _) => _btn(
              key: const Key('corner-fullscreen'),
              tip: fs
                  ? 'Выйти из полноэкранного режима (F11 / Esc)'
                  : 'Во весь экран (F11)',
              icon: fs
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              onTap: () => toggleFullScreen(),
            ),
          ),
          const SizedBox(width: 5),
        ],
        if (!desktopUi) ...[
          _btn(
            tip: c.mtsOn ? 'МТС прокси: вкл' : 'МТС прокси: выкл',
            text: 'МТС',
            fill: c.mtsOn ? _MtsBtn._red : null,
            onTap: () async {
              final on = !c.mtsOn;
              await c.setMtsProxy(on);
              if (!context.mounted) return;
              toast(
                context,
                on
                    ? 'МТС прокси включён: только AnyTLS, mieru, VLESS и прокси'
                    : 'МТС прокси выключен',
              );
              if (on) await mtsApnDialog(context);
            },
          ),
          const SizedBox(width: 5),
        ],
        _btn(
          key: TourKeys.mail,
          tip: upd ? 'Доступно обновление' : 'Обновления и сообщения',
          icon: upd ? Icons.mark_email_unread_outlined : Icons.mail_outline,
          hot: upd,
          dot: upd,
          onTap: () => updateSheet(context, c, p),
        ),
        const SizedBox(width: 5),
        _btn(
          key: TourKeys.settings,
          tip: 'Настройки',
          icon: Icons.settings_outlined,
          onTap: () => settingsSheet(context, c, p),
        ),
      ],
    );
  }
}

/// Flat header button: no fill, circular ripple, accent focus ring for TV D-pad.
/// «МТС прокси» pill in the top bar: red when on.
class _MtsBtn extends StatelessWidget {
  final Pal p;
  final bool on;
  final VoidCallback onTap;
  const _MtsBtn({required this.p, required this.on, required this.onTap});
  static const _red = Color(0xFFE30611);
  @override
  Widget build(BuildContext context) => Tooltip(
    message: on ? 'МТС прокси: вкл' : 'МТС прокси: выкл',
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on
                ? _red
                : (p.amoled
                      ? const Color(0xFF101018)
                      : (p.light ? p.bg : p.chip.withValues(alpha: .80))),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: on ? _red : (p.amoled ? const Color(0xFF222230) : p.line),
            ),
          ),
          child: Text(
            'МТС',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: on ? Colors.white : p.txt.withValues(alpha: .75),
            ),
          ),
        ),
      ),
    ),
  );
}

class _GhostBtn extends StatefulWidget {
  final Pal p;
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final Color? tint;
  final bool badge;
  final bool mobile;
  final bool accent;
  const _GhostBtn({
    super.key,
    required this.p,
    required this.icon,
    required this.tip,
    required this.onTap,
    this.tint,
    this.badge = false,
    this.mobile = false,
    this.accent = false,
  });
  @override
  State<_GhostBtn> createState() => _GhostBtnState();
}

class _GhostBtnState extends State<_GhostBtn> {
  bool _f = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    if (widget.mobile) {
      final acc = widget.accent;
      return Tooltip(
        message: widget.tip,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            onFocusChange: (f) => setState(() => _f = f),
            focusColor: p.acc.withValues(alpha: .16),
            hoverColor: p.acc.withValues(alpha: .10),
            splashColor: p.acc.withValues(alpha: .22),
            highlightColor: p.acc.withValues(alpha: .10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: acc
                    ? p.acc.withValues(alpha: p.light ? .12 : .20)
                    : (p.amoled
                          ? const Color(0xFF101018)
                          : (p.light ? p.bg : p.chip.withValues(alpha: .80))),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _f
                      ? p.acc2
                      : (acc
                            ? p.acc.withValues(alpha: p.light ? .28 : .38)
                            : (p.amoled ? const Color(0xFF222230) : p.line)),
                  width: _f ? 2 : 1,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    widget.icon,
                    size: 19,
                    color: widget.tint ?? (acc ? p.acc2 : p.txt),
                  ),
                  if (widget.badge)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: p.acc2,
                          shape: BoxShape.circle,
                          border: Border.all(color: p.card, width: 1.5),
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

/// Power knob shared by every connection-card layout (TourKeys.power, D-pad Enter toggles).
Widget _powerKnob(NoxController c, Pal p, {double size = 84}) {
  final on = c.connected, wait = c.busy;
  return Focus(
    key: TourKeys.power,
    autofocus: c.isTv,
    child: Builder(
      builder: (ctx) {
        final f = Focus.of(ctx).hasFocus;
        return GestureDetector(
          onTap: c.toggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on
                  ? p.acc
                  : wait
                  ? p.amb
                  : p.chip,
              // volumetric knob: lit from the top-left, deeper at the bottom-right
              gradient: !vol3d
                  ? null
                  : RadialGradient(
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
                      color: on ? Colors.white.withValues(alpha: .18) : p.line,
                    ),
              boxShadow: !vol3d
                  ? const []
                  : [
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
              size: size * .40,
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
  );
}

class _Hero extends StatelessWidget {
  final NoxController c;
  final Pal p;
  final bool wide; // wide layout has its own big graph card
  const _Hero({required this.c, required this.p, this.wide = false});
  @override
  Widget build(BuildContext context) {
    // 2.1.4: «Таймер» card is the default on phone and desktop; TV keeps the D-pad knob card.
    if (!c.isTv && heroStyle != 'classic') {
      return _HeroAlt(c: c, p: p, style: heroStyle, wide: wide);
    }
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
      padding: EdgeInsets.all(wide ? 16 : 14),
      decoration: _box(p, color: p.hero, r: 22),
      child: Row(
        children: [
          _powerKnob(c, p),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                    ),
                    ?_HeroCorner.of(c, p, wide: wide),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  cur == null
                      ? 'Сервер не выбран'
                      : _dispName(cur['name'] ?? ''),
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
                      : [
                          if (NoxController.proto(cur).isEmpty)
                            'Автовыбор'
                          else if (showProto)
                            NoxController.proto(cur),
                          if (on && since > 0)
                            fmtDur(
                              DateTime.now().millisecondsSinceEpoch ~/ 1000 -
                                  since,
                            ),
                        ].join(' · '),
                  style: TextStyle(color: p.sub, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    _Pill(
                      p: p,
                      icon: Icons.south_rounded,
                      text: '${fmtBytes(t?['Down'] ?? 0)}/с',
                    ),
                    _Pill(
                      p: p,
                      icon: Icons.north_rounded,
                      text: '${fmtBytes(t?['Up'] ?? 0)}/с',
                    ),
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
                        calm: true,
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
  final IconData? icon;
  const _Pill({required this.p, required this.text, this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: p.chip,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: p.acc2),
          const SizedBox(width: 3),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: TextStyle(color: p.txt, fontSize: 12),
          ),
        ),
      ],
    ),
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
  final double marginTop;
  const _GraphCard({required this.c, required this.p, this.marginTop = 10});
  @override
  Widget build(BuildContext context) {
    final t = c.traffic;
    final on = c.connected && t != null;
    return Container(
      margin: EdgeInsets.only(top: marginTop),
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
  final bool mobile;
  const _MailBtn({required this.c, required this.p, this.mobile = false});
  @override
  Widget build(BuildContext context) {
    final has = c.s['update'] is Map;
    return _GhostBtn(
      key: TourKeys.mail,
      p: p,
      icon: has ? Icons.mark_email_unread_outlined : Icons.mail_outline,
      tint: has ? p.acc2 : null,
      badge: has,
      mobile: mobile,
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
          if (u['mandatory'] != true)
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
  final bool first;
  final bool mobile;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;
  const _SubBlock({
    super.key,
    required this.c,
    required this.p,
    required this.b,
    this.first = false,
    this.mobile = false,
    this.collapsed = false,
    this.onToggleCollapse,
  });

  /// Refresh / ••• / collapse, shared by every card style.
  Widget _subActions(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (c.accordion) ...[
        _PingOrb(
          key: first ? TourKeys.ping : null,
          c: c,
          p: p,
          mobile: mobile,
          onTap: () {
            final multi = c.subs.length > 1;
            c.ping(
              c
                  .visible()
                  .where((e) => !multi || e['subId'] == b['id'])
                  .map((e) => e['id'] as String)
                  .toList(),
            );
          },
        ),
        const SizedBox(width: 6),
      ],
      _OrbBtn(
        key: first && mobile ? TourKeys.refresh : null,
        p: p,
        icon: Icons.refresh_rounded,
        tip: 'Обновить',
        spinWhileBusy: true,
        mobile: mobile,
        onTap: () async {
          final r = await c.call('RefreshSub', [b['id']]);
          if (context.mounted) await finishRefresh(context, c, r);
        },
      ),
      const SizedBox(width: 6),
      _OrbBtn(
        p: p,
        icon: Icons.more_horiz_rounded,
        tip: 'Действия с подпиской',
        mobile: mobile,
        onTap: () async => subSheet(context, c, p, b),
      ),
      if (c.accordion && c.subs.length > 1) ...[
        const SizedBox(width: 6),
        _OrbBtn(
          p: p,
          icon: Icons.more_vert_rounded,
          tip: 'Меню списка',
          mobile: mobile,
          onTap: () async => listSheet(
            context,
            c,
            p,
            caption: listCaption(c, c.visible().length),
          ),
        ),
      ],
      if (mobile && onToggleCollapse != null) ...[
        const SizedBox(width: 6),
        _OrbBtn(
          p: p,
          icon: collapsed
              ? Icons.keyboard_arrow_down_rounded
              : Icons.keyboard_arrow_up_rounded,
          tip: collapsed ? 'Развернуть подписку' : 'Свернуть подписку',
          mobile: true,
          onTap: () async => onToggleCollapse!(),
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final n = c.servers.where((s) => s['subId'] == b['id']).length;
    final used = ((b['upload'] ?? 0) as num) + ((b['download'] ?? 0) as num);
    final total = (b['total'] ?? 0) as num;
    final expire = (b['expire'] ?? 0) as int;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final left = expire > 0 ? (expire - now) / 86400 : null;
    final ann = (b['announce'] ?? '') as String;
    final dt = expire > 0
        ? DateTime.fromMillisecondsSinceEpoch(expire * 1000)
        : null;
    return _SubStyled(
      c: c,
      p: p,
      b: b,
      d: _SubData(n: n, used: used, total: total, left: left, dt: dt),
      ann: ann,
      actions: _subActions(context),
      mobile: mobile,
      collapsed: mobile && collapsed,
    );
  }
}

/// Subscription card (2.1.4): gradient glass, big traffic number, thin line, icon links.

class _SubData {
  final int n;
  final num used, total;
  final double? left;
  final DateTime? dt;
  const _SubData({
    required this.n,
    required this.used,
    required this.total,
    required this.left,
    required this.dt,
  });
  bool get unlimited => total <= 0;
  bool get forever => left == null;
  int get days => left == null ? 0 : math.max(0, left!.ceil());
  String get expShort => forever
      ? 'Бессрочно'
      : left! <= 0
      ? 'Истекла'
      : '$days ${plural(days, 'день', 'дня', 'дней')}';
  String get dateTxt => dt == null
      ? 'без срока'
      : 'до ${dt!.day.toString().padLeft(2, '0')}.${dt!.month.toString().padLeft(2, '0')}.${dt!.year}';
  num get trafficLeft => math.max(0, total - used);
  double get tFrac => unlimited ? 1.0 : (1 - used / total).clamp(0.0, 1.0);
  double get dFrac => forever ? 1.0 : (left! / 30).clamp(0.0, 1.0);
  String get usedTxt => fmtBytes(used);
  String get servTxt => '$n ${plural(n, 'сервер', 'сервера', 'серверов')}';
}

class _SubStyled extends StatelessWidget {
  final NoxController c;
  final Pal p;
  final J b;
  final _SubData d;
  final String ann;
  final Widget actions;
  final bool mobile, collapsed;
  const _SubStyled({
    required this.c,
    required this.p,
    required this.b,
    required this.d,
    required this.ann,
    required this.actions,
    required this.mobile,
    required this.collapsed,
  });

  static const _links = _SubLinksBar._items;
  static const _donate = _SubLinksBar._donateUrl;
  static const _linkIcons = <IconData>[
    Icons.send_rounded,
    Icons.language_rounded,
    Icons.live_tv_rounded,
    Icons.public_rounded,
  ];

  @override
  Widget build(BuildContext context) => _glass(context);

  // ── B: gradient glass — big traffic number, thin line, icon links ──
  Widget _glass(BuildContext context) {
    final tCol = levelColor(p, d.tFrac);
    final a = p.light ? .55 : 1.0;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: EdgeInsets.fromLTRB(14, 8, 8, collapsed ? 8 : 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(p.acc.withValues(alpha: .30 * a), p.card),
            Color.alphaBlend(p.acc2.withValues(alpha: .10 * a), p.card),
            p.card,
          ],
          stops: const [0, .55, 1],
        ),
        border: Border.all(color: p.acc2.withValues(alpha: .32)),
        boxShadow: [
          BoxShadow(
            color: p.acc.withValues(alpha: p.light ? .10 : .22),
            blurRadius: 26,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'ПОДПИСКА',
                        style: TextStyle(
                          color: p.acc2,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                      TextSpan(
                        text: '   ${d.servTxt}',
                        style: TextStyle(color: p.sub),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              actions,
            ],
          ),
          if (!collapsed) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.unlimited ? d.usedTxt : fmtBytes(d.trafficLeft),
                          style: TextStyle(
                            color: p.txt,
                            fontSize: 32,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.5,
                          ),
                        ),
                        Text(
                          d.unlimited
                              ? 'израсходовано · трафик без лимита'
                              : 'осталось из ${fmtBytes(d.total)}',
                          style: TextStyle(color: p.sub, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            d.forever
                                ? Icons.all_inclusive_rounded
                                : Icons.event_rounded,
                            size: 16,
                            color: levelColor(p, d.dFrac),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            d.expShort,
                            style: TextStyle(
                              color: p.txt,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        d.dateTxt,
                        style: TextStyle(color: p.sub, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 4,
                  child: Stack(
                    children: [
                      Container(color: p.line.withValues(alpha: .8)),
                      FractionallySizedBox(
                        widthFactor: d.unlimited ? 1 : d.tFrac,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: d.unlimited
                                  ? [p.acc, p.acc2, p.grn]
                                  : [tCol.withValues(alpha: .7), tCol],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (ann.isNotEmpty) _Announce(c: c, p: p, text: ann),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(
                children: [
                  for (final (i, l) in _links.indexed)
                    Expanded(
                      child: _iconLink(
                        context,
                        _linkIcons[i],
                        l.$1,
                        l.$2,
                        l.$4,
                      ),
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        _CoinDonateBtn(p: p, url: _donate, size: 28),
                        const SizedBox(height: 3),
                        Text(
                          'Донат',
                          style: TextStyle(color: p.sub, fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _iconLink(
    BuildContext context,
    IconData icon,
    String text,
    String url,
    bool primary,
  ) => Tooltip(
    message: url,
    child: InkWell(
      onTap: () => _openSubUrl(context, url),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          Container(
            width: 28, // 2.2.0: compact (was 40)
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary
                  ? p.acc.withValues(alpha: .28)
                  : (p.light
                        ? Colors.white
                        : Colors.white.withValues(alpha: .05)),
              border: Border.all(
                color: primary
                    ? p.acc2.withValues(alpha: .6)
                    : p.acc2.withValues(alpha: .22),
              ),
            ),
            child: Icon(icon, size: 13, color: primary ? p.txt : p.acc2),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              maxLines: 1,
              style: TextStyle(
                color: primary ? p.acc2 : p.sub,
                fontSize: 9,
                fontWeight: primary ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Provider announcement: icon + title, collapsible text, dismiss (remembered per text).
class _Announce extends StatefulWidget {
  final NoxController c;
  final Pal p;
  final String text;
  const _Announce({required this.c, required this.p, required this.text});
  @override
  State<_Announce> createState() => _AnnounceState();
}

class _AnnounceState extends State<_Announce> {
  bool open = false;

  /// Light markup: **bold**, lines starting with •/-/* become bullets, URLs accent-coloured.
  List<InlineSpan> _rich(Pal p, String t) {
    final out = <InlineSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*|(https?://\S+)');
    final lines = t.split('\n');
    for (var li = 0; li < lines.length; li++) {
      var line = lines[li];
      final m = RegExp(r'^\s*[•\-*]\s+').firstMatch(line);
      if (m != null) {
        out.add(
          TextSpan(
            text: '•  ',
            style: TextStyle(color: p.acc2, fontWeight: FontWeight.w800),
          ),
        );
        line = line.substring(m.end);
      }
      var i = 0;
      for (final x in re.allMatches(line)) {
        if (x.start > i) out.add(TextSpan(text: line.substring(i, x.start)));
        if (x.group(1) != null) {
          out.add(
            TextSpan(
              text: x.group(1),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          );
        } else {
          out.add(
            TextSpan(
              text: x.group(2),
              style: TextStyle(
                color: p.acc2,
                decoration: TextDecoration.underline,
                decorationColor: p.acc2,
              ),
            ),
          );
        }
        i = x.end;
      }
      if (i < line.length) out.add(TextSpan(text: line.substring(i)));
      if (li < lines.length - 1) out.add(const TextSpan(text: '\n'));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final key = '${widget.text.hashCode}';
    if (widget.c.ui['annHide'] == key) return const SizedBox.shrink();
    final long = widget.text.length > 90 || widget.text.contains('\n');
    final r = BorderRadius.circular(18);
    final glass = Stack(
      children: [
        // soft glow blobs behind the glass
        if (vol3d)
          Positioned(
            right: -30,
            top: -40,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    p.acc2.withValues(alpha: .35),
                    p.acc2.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        if (vol3d)
          Positioned(
            left: -40,
            bottom: -50,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    p.acc.withValues(alpha: .30),
                    p.acc.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: vol3d
                    ? [
                        Colors.white.withValues(alpha: p.light ? .55 : .09),
                        p.acc.withValues(alpha: p.amoled ? .14 : .18),
                        p.acc2.withValues(alpha: p.amoled ? .06 : .10),
                      ]
                    : [
                        p.acc.withValues(alpha: .10),
                        p.acc.withValues(alpha: .10),
                      ],
              ),
            ),
            child: InkWell(
              onTap: long ? () => setState(() => open = !open) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // glowing orb icon
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          center: const Alignment(-.35, -.4),
                          colors: [
                            Color.lerp(p.acc2, Colors.white, .35)!,
                            p.acc,
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .25),
                        ),
                        boxShadow: vol3d
                            ? [
                                BoxShadow(
                                  color: p.acc.withValues(alpha: .55),
                                  blurRadius: 16,
                                ),
                              ]
                            : const [],
                      ),
                      child: const Icon(
                        Icons.campaign_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: ShaderMask(
                                  shaderCallback: (b) => LinearGradient(
                                    colors: [p.txt, p.acc2],
                                  ).createShader(b),
                                  child: const Text(
                                    'Объявление',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                      letterSpacing: .2,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  color: p.acc.withValues(alpha: .22),
                                  border: Border.all(
                                    color: p.acc2.withValues(alpha: .4),
                                  ),
                                ),
                                child: Text(
                                  'новое',
                                  style: TextStyle(
                                    color: p.acc2,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topCenter,
                            child: Text.rich(
                              TextSpan(children: _rich(p, widget.text)),
                              maxLines: open ? null : 3,
                              overflow: open
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.txt.withValues(alpha: .92),
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ),
                          if (long)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    open ? 'Свернуть' : 'Читать полностью',
                                    style: TextStyle(
                                      color: p.acc2,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Icon(
                                    open
                                        ? Icons.expand_less_rounded
                                        : Icons.expand_more_rounded,
                                    size: 16,
                                    color: p.acc2,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Скрыть',
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => widget.c.setPref('annHide', key),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(
                              alpha: p.light ? .5 : .07,
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .14),
                            ),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 15,
                            color: p.sub,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10, right: 6),
      decoration: BoxDecoration(
        borderRadius: r,
        border: Border.all(
          color: Colors.white.withValues(alpha: vol3d ? .16 : .08),
        ),
        boxShadow: vol3d
            ? [
                BoxShadow(
                  color: p.acc.withValues(alpha: .28),
                  blurRadius: 22,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: .45),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : const [],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Material(type: MaterialType.transparency, child: glass),
      ),
    );
  }
}

Future<void> _openSubUrl(BuildContext context, String url) async {
  if (await openUrl(url)) return;
  Clipboard.setData(ClipboardData(text: url));
  if (context.mounted) toast(context, 'Ссылка скопирована: $url');
}

/// Provider links + donate target shown on the subscription card.
abstract final class _SubLinksBar {
  static const _items = <(String, String, IconData?, bool)>[
    ('Поддержка', 'https://t.me/sessiatop', Icons.send_rounded, true),
    ('sessia.top', 'https://sessia.top', null, false),
    ('etv24.ru', 'https://etv24.ru', null, false),
    ('iji.by', 'https://iji.by', null, false),
  ];
  static const _donateUrl =
      'https://t.tb.ru/c2c-qr-choose-bank?requisiteNumber=+79111112787&bankCode=100000000004';
}

class _CoinDonateBtn extends StatelessWidget {
  final Pal p;
  final String url;
  final double size;
  const _CoinDonateBtn({required this.p, required this.url, this.size = 30});

  @override
  Widget build(BuildContext context) {
    final baseBg = p.amoled
        ? const Color(0xFF0B0B14)
        : (p.light ? p.card : p.chip);
    final rimGrad = p.light
        ? [p.acc2.withValues(alpha: .30), p.acc.withValues(alpha: .16)]
        : [p.acc2.withValues(alpha: .42), p.acc.withValues(alpha: .24), baseBg];
    final faceGrad = p.light
        ? [Colors.white, p.acc.withValues(alpha: .14)]
        : [p.acc2.withValues(alpha: .28), p.acc.withValues(alpha: .16), baseBg];
    final symColor = p.light ? p.acc : p.acc2;
    return Tooltip(
      message: 'Пожертвование',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: () => _openSubUrl(context, url),
          customBorder: const CircleBorder(),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: rimGrad,
              ),
              border: Border.all(
                color: p.acc2.withValues(alpha: p.light ? .50 : .62),
                width: 1.3,
              ),
              boxShadow: [
                BoxShadow(
                  color: p.acc.withValues(alpha: p.light ? .16 : .26),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Container(
              margin: const EdgeInsets.all(2.4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.25, -0.3),
                  radius: 0.95,
                  colors: faceGrad,
                ),
                border: Border.all(
                  color: p.acc2.withValues(alpha: p.light ? .35 : .44),
                  width: 1,
                ),
              ),
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Text(
                    '₽',
                    style: TextStyle(
                      color: symColor,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      shadows: [
                        Shadow(
                          color: p.acc.withValues(alpha: p.light ? .15 : .45),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row: horizontally scrolling text tabs (small flags, accent text + underline when
/// selected, fade at the edges) and three fixed icon buttons on the right (ping-all,
/// refresh subscriptions, ⋮ which also shows «N из M · пинг: …»). D-pad friendly.
class _FilterBar extends StatefulWidget {
  final NoxController c;
  final Pal p;
  final int shown;
  final bool mobile;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;
  const _FilterBar({
    required this.c,
    required this.p,
    required this.shown,
    this.mobile = false,
    this.collapsed = false,
    this.onToggleCollapse,
  });
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
    // 2.1.5 phone accordion: never a header row. ⚡ (+ ping progress) lives on the
    // subscription card, ⋮ on «Автовыбор» or on the first country card.
    if (c.accordion) return const SizedBox(height: 6);
    final ts = MediaQuery.textScalerOf(context);
    final h = widget.mobile ? ts.scale(14) + 22 : ts.scale(13) + 24;
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
            on: k == cat && !widget.collapsed,
            mobile: widget.mobile,
            onTap: () {
              if (widget.mobile) {
                if (widget.collapsed) {
                  c.setPref('cat', k);
                  widget.onToggleCollapse?.call();
                } else if (k == cat && widget.onToggleCollapse != null) {
                  widget.onToggleCollapse!.call();
                } else {
                  c.setPref('cat', k);
                }
              } else {
                c.setPref('cat', k);
              }
            },
          );
        },
      ),
    );
    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: widget.collapsed ? 0 : 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  key: TourKeys.tabs,
                  height: h,
                  child: c.accordion
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'СЕРВЕРЫ',
                                  style: TextStyle(
                                    color: p.acc2,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _CountPill(p: p, n: widget.shown, strong: true),
                              ],
                            ),
                          ),
                        )
                      : strip,
                ),
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
              if (!widget.mobile || c.subs.isEmpty)
                _IconBtn(
                  key: TourKeys.refresh,
                  p: p,
                  small: true,
                  icon: Icons.refresh,
                  tip: 'Обновить подписки',
                  onTap: () async {
                    toast(context, 'Обновляю подписки…');
                    final r = await c.call('RefreshSubs');
                    if (context.mounted) await finishRefresh(context, c, r);
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
              if (widget.mobile && widget.onToggleCollapse != null)
                _IconBtn(
                  p: p,
                  small: true,
                  icon: widget.collapsed
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                  tip: widget.collapsed
                      ? 'Развернуть серверы'
                      : 'Свернуть серверы',
                  onTap: widget.onToggleCollapse!,
                ),
            ],
          ),
          if (!widget.mobile)
            Container(height: 1, color: p.line.withValues(alpha: .6)),
          if (pinging)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Пинг ${s['pingDone']}/${s['pingAll']}…',
                style: TextStyle(
                  color: p.amoled
                      ? const Color(0xFFE6E8F0)
                      : p.txt.withValues(alpha: .85),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
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
  final bool mobile;
  final VoidCallback onTap;
  const _Tab({
    required this.p,
    required this.text,
    required this.iso,
    required this.on,
    required this.onTap,
    this.mobile = false,
  });
  @override
  Widget build(BuildContext context) {
    if (mobile) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Semantics(
          selected: on,
          button: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              focusColor: p.acc.withValues(alpha: .22),
              hoverColor: p.acc.withValues(alpha: .10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  gradient: on ? accentGradient(p) : null,
                  color: on
                      ? null
                      : (p.amoled
                            ? const Color(0xFF0A0A12)
                            : (p.light ? p.card : p.chip)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: on
                        ? p.acc2.withValues(alpha: .65)
                        : (p.amoled ? const Color(0xFF222230) : p.line),
                    width: 1,
                  ),
                  boxShadow: on && vol3d
                      ? [
                          BoxShadow(
                            color: p.acc.withValues(alpha: p.light ? .22 : .32),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (iso != null && hasFlag(iso!) && !p.mono) ...[
                        ClipOval(
                          child: SvgPicture.asset(
                            'assets/flags/${iso!.toLowerCase()}.svg',
                            width: 16,
                            height: 16,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        text,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: on
                              ? Colors.white
                              : p.txt.withValues(alpha: .90),
                          fontSize: 14,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Semantics(
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
                    if (iso != null && hasFlag(iso!) && !p.mono) ...[
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
}

// ------------------------------------------------------------------ servers

Widget _flag(Pal p, J s, {double size = 36}) {
  Widget inner;
  if (NoxController.isBal(s)) {
    inner = Icon(Icons.bolt_rounded, size: size * .62, color: p.acc2);
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
    if (r != null && (hasFlag(r) || p.mono)) return countryBadge(p, r, size);
    final t = r ?? (showProto ? NoxController.proto(s) : '');
    inner = t.isEmpty
        ? Icon(Icons.public, size: size * .6, color: p.sub)
        : Text(
            t.length > 2 ? t.substring(0, 2).toUpperCase() : t.toUpperCase(),
            style: TextStyle(
              color: p.sub,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
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
/// Glass surface of the 2.1.4 look: accent tint top-left fading into the card colour.
BoxDecoration glassBox(
  Pal p, {
  double r = 20,
  double strength = 1,
  Color? border,
}) {
  final a = (p.light ? .55 : 1.0) * strength;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(r),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.alphaBlend(p.acc.withValues(alpha: .26 * a), p.card),
        Color.alphaBlend(p.acc2.withValues(alpha: .08 * a), p.card),
        p.card,
      ],
      stops: const [0, .55, 1],
    ),
    border: Border.all(
      color: border ?? p.acc2.withValues(alpha: .14 + .14 * strength),
    ),
    boxShadow: [
      BoxShadow(
        color: p.acc.withValues(alpha: (p.light ? .06 : .14) * strength),
        blurRadius: 20,
        offset: const Offset(0, 6),
      ),
    ],
  );
}

/// Flag, or in the monochrome theme a neutral circle with the 2-letter code.
Widget countryBadge(Pal p, String iso, double size) {
  if (!p.mono && hasFlag(iso)) {
    return ClipOval(
      child: SvgPicture.asset(
        'assets/flags/${iso.toLowerCase()}.svg',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [p.chip, p.card],
      ),
      border: Border.all(color: p.txt.withValues(alpha: .28)),
    ),
    child: Text(
      iso.toUpperCase(),
      style: TextStyle(
        color: p.txt,
        fontSize: size * .38,
        fontWeight: FontWeight.w800,
        letterSpacing: .4,
        height: 1,
      ),
    ),
  );
}

/// Category tint for the accordion chips and protocol badges (greys in mono).
Color catColor(Pal p, String cat) {
  if (p.mono) return p.acc2;
  final k = cat.toLowerCase();
  if (k.startsWith('qwdtt')) return const Color(0xFF34D399);
  if (k.contains('xhttp')) return const Color(0xFF60A5FA);
  if (k.startsWith('vless')) return const Color(0xFFA78BFA);
  if (k.startsWith('anytls')) return const Color(0xFF2DD4BF);
  if (k.startsWith('hysteria')) return const Color(0xFFFBBF24);
  if (k.startsWith('tuic')) return const Color(0xFFFB923C);
  if (k.startsWith('mieru')) return const Color(0xFFF472B6);
  if (k.startsWith('naive')) return const Color(0xFF38BDF8);
  if (k.startsWith('trojan')) return const Color(0xFFF87171);
  if (k.startsWith('vmess')) return const Color(0xFFC084FC);
  if (k.startsWith('ss') || k.startsWith('shadowsocks'))
    return const Color(0xFF4ADE80);
  return p.acc2;
}

class _CatChip extends StatelessWidget {
  final Pal p;
  final String text;
  final int n;
  final Color color;
  const _CatChip({
    required this.p,
    required this.text,
    required this.n,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: p.light ? .12 : .14),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: color.withValues(alpha: .38)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: p.light ? p.txt : color,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: .2,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$n',
          style: TextStyle(
            color: p.sub,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _CountPill extends StatelessWidget {
  final Pal p;
  final int n;
  final bool strong;
  const _CountPill({required this.p, required this.n, this.strong = false});
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 28),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: strong
          ? p.acc.withValues(alpha: p.light ? .12 : .22)
          : (p.light ? const Color(0x0A000000) : const Color(0x0DFFFFFF)),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: p.acc2.withValues(alpha: strong ? .40 : .18)),
    ),
    child: Text(
      '$n',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: strong ? p.txt : p.sub,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Two-letter protocol badge used on rows inside a country card.
class _ProtoGlyph extends StatelessWidget {
  final Pal p;
  final J s;
  final Color color;
  const _ProtoGlyph({required this.p, required this.s, required this.color});
  @override
  Widget build(BuildContext context) {
    final t = NoxController.isQw(s)
        ? 'qW'
        : (() {
            final pr = NoxController.proto(
              s,
            ).replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
            return pr.isEmpty
                ? '•'
                : pr.substring(0, math.min(2, pr.length)).toUpperCase();
          })();
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: p.light ? .14 : .16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Text(
        t,
        style: TextStyle(
          color: p.light ? p.txt : color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

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
  final pr = showProto ? NoxController.proto(s) : '';
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
  final bool flat;
  const _Tap({
    required this.p,
    required this.sel,
    this.flat = false,
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
    final rad = w.flat ? 14.0 : 16.0;
    return Material(
      color: w.flat
          ? (w.sel
                ? p.acc.withValues(alpha: p.light ? .14 : .24)
                : (p.light ? const Color(0x08000000) : const Color(0x0AFFFFFF)))
          : (w.sel ? p.sel : p.card),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(rad),
        // D-pad / keyboard focus: a clear ring, not only the ink overlay (TV)
        side: BorderSide(
          color: focused
              ? p.acc2
              : w.flat
              ? (w.sel
                    ? p.acc2.withValues(alpha: .60)
                    : p.line.withValues(alpha: .55))
              : (w.sel ? p.acc : p.line),
          width: focused ? 2.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(rad),
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
  final bool
  protocol; // desktop keeps the protocol line; the phone column does not
  final bool inCountry; // accordion: the country card already names the country
  final Color? glyph; // accordion: protocol badge colour instead of the flag
  final bool flat; // accordion: light glass row instead of a bordered card
  final String? listMenu; // first row: ⋮ also opens the list menu (caption)
  const _ServerRow({
    this.listMenu,
    required this.c,
    required this.p,
    required this.s,
    this.first = false,
    this.protocol = true,
    this.inCountry = false,
    this.glyph,
    this.flat = false,
  });
  @override
  Widget build(BuildContext context) {
    final sub = _sub(s);
    return Padding(
      padding: EdgeInsets.only(bottom: inCountry ? 5 : 3),
      child: _Tap(
        p: p,
        sel: s['id'] == c.selected,
        flat: flat || inCountry,
        onTap: () => c.select(s['id']),
        onLong: () => serverSheet(context, c, p, s),
        padding: EdgeInsets.fromLTRB(
          10,
          inCountry ? 6 : 4,
          0,
          inCountry ? 6 : 4,
        ),
        child: Row(
          children: [
            glyph != null
                ? _ProtoGlyph(p: p, s: s, color: glyph!)
                : _flag(p, s, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    inCountry
                        ? _shortName(s['name'] ?? '')
                        : _dispName(s['name'] ?? ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.txt,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                  if (protocol && sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.sub, fontSize: 11, height: 1.1),
                    ),
                ],
              ),
            ),
            PingChip(p: p, text: _pingOf(c, s)),
            KeyedSubtree(
              key: first ? TourKeys.server : null,
              child: IconButton(
                key: listMenu != null ? TourKeys.more : null,
                onPressed: () =>
                    serverSheet(context, c, p, s, listCaption: listMenu),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                icon: Icon(
                  Icons.more_vert,
                  color: listMenu != null ? p.acc2 : p.sub,
                  size: 18,
                ),
                tooltip: listMenu != null ? 'Сервер и список' : 'Ещё',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Accordion card: flag, country, count · best ping, chevron; body animates open/closed.
class _CountryCard extends StatelessWidget {
  final NoxController c;
  final Pal p;
  final CountryGroup g;
  final bool open;
  final bool firstRow;
  final ValueChanged<bool> onToggle;

  /// Caption of the ⋮ list menu, set on the first card when there is no «Автовыбор».
  final String? listMenu;
  const _CountryCard({
    super.key,
    required this.c,
    required this.p,
    required this.g,
    required this.open,
    required this.onToggle,
    this.firstRow = false,
    this.listMenu,
  });
  @override
  Widget build(BuildContext context) {
    final iso = g.iso;
    final best = g.bestPing;
    final sel = g.has(c.selected);
    final flag = Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: p.acc2.withValues(alpha: .30)),
      ),
      child: iso != null && (hasFlag(iso) || p.mono)
          ? countryBadge(p, iso, 30)
          : Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.chip, shape: BoxShape.circle),
              child: Icon(Icons.public, size: 17, color: p.sub),
            ),
    );
    var first = firstRow;
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 2.2.2 desktop: no protocol chips/badges, just flag, name and ping
          if (!showProto) ...[
            const SizedBox(height: 4),
            for (final s in g.all)
              _ServerRow(
                c: c,
                p: p,
                s: s,
                first: (first, first = false).$1,
                protocol: false,
                inCountry: true,
              ),
          ] else
            for (final (cat, items) in g.cats) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _CatChip(
                    p: p,
                    text: cat == 'qWDTT' ? 'Антиблок · qWDTT' : cat,
                    n: items.length,
                    color: catColor(p, cat),
                  ),
                ),
              ),
              for (final s in items)
                _ServerRow(
                  c: c,
                  p: p,
                  s: s,
                  first: (first, first = false).$1,
                  protocol: false,
                  inCountry: true,
                  glyph: catColor(p, cat),
                ),
            ],
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        decoration: glassBox(
          p,
          r: 20,
          strength: open || sel ? 1 : .55,
          border: sel ? p.acc2.withValues(alpha: .55) : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => onToggle(!open),
                focusColor: p.acc.withValues(alpha: .18),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  child: Row(
                    children: [
                      flag,
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          g.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.txt,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.2,
                          ),
                        ),
                      ),
                      _CountPill(p: p, n: g.count),
                      if (best != null) ...[
                        const SizedBox(width: 6),
                        PingChip(p: p, text: pingText(best)),
                      ],
                      const SizedBox(width: 6),
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: open
                              ? p.acc.withValues(alpha: .22)
                              : (p.light
                                    ? const Color(0x0A000000)
                                    : const Color(0x0DFFFFFF)),
                          border: Border.all(
                            color: p.acc2.withValues(alpha: open ? .45 : .18),
                          ),
                        ),
                        child: AnimatedRotation(
                          turns: open ? .5 : 0,
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeInOutCubic,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: open ? p.txt : p.acc2,
                            size: 20,
                          ),
                        ),
                      ),
                      if (listMenu != null)
                        IconButton(
                          key: TourKeys.more,
                          onPressed: () =>
                              listSheet(context, c, p, caption: listMenu),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 30,
                            height: 30,
                          ),
                          icon: Icon(Icons.more_vert, color: p.acc2, size: 18),
                          tooltip: 'Меню списка',
                        ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeInOutCubic,
                alignment: Alignment.topCenter,
                child: open ? body : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
    padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _flag(p, s, size: 26),
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
          _dispName(s['name'] ?? ''),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: p.txt,
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
        ),
        Text(
          _sub(s),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: p.sub, fontSize: 11, height: 1.1),
        ),
        const SizedBox(height: 4),
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
  backgroundColor: Colors.transparent,
  constraints: const BoxConstraints(maxWidth: 560),
  builder: (ctx) => Container(
    decoration: BoxDecoration(
      color: p.hero,
      gradient: vol3d && !p.amoled
          ? LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(p.hero, Colors.white, p.light ? .3 : .05)!,
                p.hero,
              ],
            )
          : null,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      border: vol3d
          ? Border(
              top: BorderSide(color: p.acc.withValues(alpha: .45), width: 1.2),
            )
          : (p.amoled ? Border(top: BorderSide(color: p.line)) : null),
      boxShadow: vol3d
          ? [
              BoxShadow(
                color: p.acc.withValues(alpha: .25),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ]
          : const [],
    ),
    child: SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * .88,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty) ...[
                Text(
                  title,
                  style: TextStyle(
                    color: p.txt,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              ...items(ctx),
            ],
          ),
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
      borderRadius: vol3d ? BorderRadius.circular(14) : null,
      child: Container(
        margin: vol3d ? const EdgeInsets.symmetric(vertical: 3) : null,
        padding: vol3d
            ? const EdgeInsets.symmetric(vertical: 12, horizontal: 12)
            : const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        decoration: vol3d
            ? BoxDecoration(
                gradient: raisedGradient(
                  p,
                  p.amoled ? const Color(0xFF000000) : p.card,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _f
                      ? p.acc
                      : p.line.withValues(alpha: p.amoled ? 1 : .7),
                  width: _f ? 2 : 1,
                ),
                boxShadow: raisedShadow(p, e: .5),
              )
            : BoxDecoration(
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
    gradient: vol3d && on ? accentGradient(p) : null,
    borderRadius: BorderRadius.circular(12),
    boxShadow: vol3d && on
        ? [BoxShadow(color: p.acc.withValues(alpha: .45), blurRadius: 10)]
        : const [],
  ),
  child: AnimatedAlign(
    duration: const Duration(milliseconds: 150),
    alignment: on ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.all(3),
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: Colors.white,
        gradient: vol3d
            ? const RadialGradient(
                center: Alignment(-.3, -.4),
                colors: [Colors.white, Color(0xFFCDD2E0)],
              )
            : null,
        shape: BoxShape.circle,
        boxShadow: vol3d
            ? const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ]
            : const [],
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
  ('auto', 'Авто (Cloudflare по DoH)'),
  ('cloudflare', 'Cloudflare (1.1.1.1)'),
  ('google', 'Google (8.8.8.8)'),
  ('quad9', 'Quad9 (9.9.9.9)'),
  ('adguard', 'AdGuard (94.140.14.14, без рекламы)'),
  ('yandex', 'Яндекс (77.88.8.8)'),
  ('dnsai', 'DNS-AI (dns-ai.ru, нейросети)'),
  ('comss', 'Comss.one DNS'),
  ('xbox', 'xbox-dns.ru'),
  ('controld', 'Control D (без фильтров)'),
  ('mullvad', 'Mullvad DNS'),
  ('nextdns', 'NextDNS'),
  ('custom', 'Свой…'),
];

/// Custom DNS: IPv4/IPv6 address (optionally udp://), tls://host or https://host/path.
/// Returns null when valid, else a Russian error.
String? validateDns(String v) {
  final s = v.trim();
  if (s.isEmpty) return 'Введите адрес DNS';
  if (s.startsWith('https://') || s.startsWith('tls://')) {
    final h =
        Uri.tryParse(
          s.startsWith('tls://') ? 'https://${s.substring(6)}' : s,
        )?.host ??
        '';
    return h.isEmpty || h.contains(' ') ? 'Неверный адрес' : null;
  }
  final ip = s.startsWith('udp://') ? s.substring(6) : s;
  return InternetAddressCheck.isIp(ip) ? null : 'Неверный IP-адрес';
}

class InternetAddressCheck {
  static bool isIp(String s) {
    final v4 = RegExp(
      r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
    ).firstMatch(s);
    if (v4 != null) {
      return [1, 2, 3, 4].every((i) => int.parse(v4.group(i)!) <= 255) &&
          s != '0.0.0.0';
    }
    return s.contains(':') &&
        RegExp(r'^[0-9a-fA-F:]+$').hasMatch(s) &&
        Uri.tryParse('http://[$s]/') != null;
  }
}

String dnsDesc(Map s) {
  final k = s['dns'] ?? 'auto';
  if (k == 'custom') return 'Свой: ${s['customDns'] ?? ''}';
  return _dns.firstWhere((e) => e.$1 == k, orElse: () => _dns[0]).$2;
}

Future<void> customDnsDialog(
  BuildContext context,
  NoxController c,
  Pal p,
) async {
  final ctl = TextEditingController(text: '${c.settings['customDns'] ?? ''}');
  String? err;
  final v = await showDialog<String>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        backgroundColor: p.card,
        title: Text('Свой DNS', style: TextStyle(color: p.txt)),
        content: TextField(
          key: const Key('customDns'),
          controller: ctl,
          autofocus: true,
          style: TextStyle(color: p.txt),
          decoration: InputDecoration(
            hintText: '1.1.1.1 или https://dns.example/dns-query',
            errorText: err,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              final e = validateDns(ctl.text);
              if (e != null) return set(() => err = e);
              Navigator.pop(d, ctl.text.trim());
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
  if (v != null) await c.saveSettings({'dns': 'custom', 'customDns': v});
}

void updateSheet(BuildContext context, NoxController c, Pal p) async {
  // Re-check like 0.7.x Mail.open so a fresh publish is not missed.
  final msg = await c.call('CheckUpdateMsg');
  await c.refresh();
  if (!context.mounted) return;
  if (c.s['update'] is Map) {
    await offerUpdate(context, c, p); // changelog + «Обновить» / «Позже»
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

/// «МТС прокси» on: the phone must use the MTS WAP access point; apps cannot switch the APN.
Future<void> mtsApnDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (d) => AlertDialog(
    title: const Text('МТС прокси включён'),
    content: const Text(
      'Для работы МТС прокси включите точку доступа (APN) wap.mts.ru в настройках мобильной сети.\n\n'
      'Прокси 192.168.192.192:80 доступен только в сети МТС. Серверы на UDP '
      '(Hysteria2, TUIC, WireGuard, qWDTT) через него не работают и помечены «не через МТС».',
    ),
    actions: [
      if (isAndroid)
        TextButton(
          onPressed: () async {
            Navigator.pop(d);
            await openApnSettings();
          },
          child: const Text('Открыть настройки APN'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(d),
        child: const Text('Понятно'),
      ),
    ],
  ),
);

void settingsSheet(BuildContext context, NoxController c, Pal p) {
  sheet(context, p, 'Настройки', (ctx) {
    final s = c.settings;
    Widget swItem(String k, String t, [String? d]) => item(
      p,
      t,
      desc: d,
      trailing: sw(
        p,
        k == 'noSysProxyOn' ? s['noSysProxy'] != true : s[k] == true,
      ),
      onTap: () async {
        Navigator.pop(ctx);
        if (k == 'noSysProxyOn') {
          await c.saveSettings({'noSysProxy': !(s['noSysProxy'] == true)});
          return;
        }
        final on = !(s[k] == true);
        await c.saveSettings({k: on});
        if (k == 'mtsProxy' && on && context.mounted) {
          await mtsApnDialog(context);
        }
        // routing is part of the running config: reconnect to apply now
        const live = {
          'mtsProxy',
          'directRu',
          'ruApps',
          'blockAds',
          'ipv6',
          'allowLan',
          'fastDial',
        };
        if (live.contains(k) && c.connected) {
          await c.call('Disconnect');
          await c.call('Connect');
        }
      },
    );
    return [
      // «МТС прокси» moved to the top bar next to «+» (_MtsBtn)
      item(
        p,
        'Режим',
        desc: s['mode'] == 'proxy'
            ? 'Прокси-сервер'
            : 'VPN (TUN) — весь трафик',
        arrow: true,
        onTap: () {
          Navigator.pop(ctx);
          sheet(
            context,
            p,
            'Режим',
            (c2) => [
              for (final (k, n, d) in [
                ('tun', 'VPN (TUN)', 'Весь трафик компьютера идёт через VPN'),
                (
                  'proxy',
                  'Прокси-сервер',
                  'HTTP и SOCKS5 на 127.0.0.1, без виртуального адаптера',
                ),
              ])
                item(
                  p,
                  n,
                  desc: d,
                  checked: (s['mode'] ?? 'tun') == k,
                  onTap: () async {
                    Navigator.pop(c2);
                    await c.saveSettings({'mode': k});
                    if (c.connected) {
                      await c.call('Disconnect');
                      await c.call('Connect');
                    }
                  },
                ),
            ],
          );
        },
      ),
      if (s['mode'] == 'proxy') ...[
        item(
          p,
          'Порт прокси',
          desc: '127.0.0.1:${s['proxyPort'] ?? 10808} · HTTP и SOCKS5',
          arrow: true,
          onTap: () async {
            Navigator.pop(ctx);
            final v = await portDialog(
              context,
              p,
              (s['proxyPort'] as int?) ?? 10808,
            );
            if (v != null) {
              await c.saveSettings({'proxyPort': v});
              if (c.connected) {
                await c.call('Disconnect');
                await c.call('Connect');
              }
            }
          },
        ),
        swItem(
          'noSysProxyOn',
          'Системный прокси',
          'Включать прокси Windows при подключении',
        ),
        swItem(
          'allowLan',
          'Разрешить из локальной сети',
          'Прокси доступен другим устройствам в вашей сети',
        ),
      ],
      if (isAndroid && !c.isTv)
        item(
          p,
          'Раздача VPN',
          desc: 'На ПК через точку доступа или USB-модем',
          arrow: true,
          onTap: () {
            Navigator.pop(ctx);
            shareVpnDialog(context, c, p);
          },
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
        child: Text(
          'Внешний вид',
          style: TextStyle(
            color: p.sub,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
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
        'Объёмный 3D-дизайн',
        desc: 'Тени, градиенты и свечение',
        trailing: sw(p, vol3dFromUi(c.ui)),
        onTap: () {
          Navigator.pop(ctx);
          c.setPref('vol3d', vol3dFromUi(c.ui) ? '0' : '1');
        },
      ),
      item(
        p,
        'Цветовой шаблон',
        desc:
            templateOf(c.pref('tpl', 'glass')).name +
            (c.pref('tpl', 'glass') == 'mono' ? ' · без флагов' : ''),
        arrow: true,
        onTap: () {
          Navigator.pop(ctx);
          templateSheet(context, c, p);
        },
      ),
      item(
        p,
        'Шаблон',
        desc: c.pref('panel', '') == 'text' ? 'Текстовый' : 'Стандартный',
        arrow: true,
        onTap: () {
          Navigator.pop(ctx);
          sheet(
            context,
            p,
            'Шаблон',
            (c2) => [
              item(
                p,
                'Стандартный',
                desc: 'Кнопка, график скорости, карточки',
                checked: c.pref('panel', '') != 'text',
                onTap: () {
                  c.setPref('panel', '');
                  Navigator.pop(c2);
                },
              ),
              item(
                p,
                'Текстовый',
                desc:
                    'Статус, страна, пинг, протокол и скорости текстом. Без графиков',
                checked: c.pref('panel', '') == 'text',
                onTap: () {
                  c.setPref('panel', 'text');
                  Navigator.pop(c2);
                },
              ),
            ],
          );
        },
      ),
      item(
        p,
        'Вид графика',
        desc: graphStyles
            .firstWhere(
              (x) => x.$1 == graphFromUi(c.ui),
              orElse: () => graphStyles.first,
            )
            .$2,
        arrow: true,
        onTap: () {
          Navigator.pop(ctx);
          sheet(
            context,
            p,
            'Вид графика',
            (c2) => [
              for (final (k, n) in graphStyles)
                item(
                  p,
                  n,
                  desc: k == ''
                      ? 'Линии скорости как раньше'
                      : k == 'smooth'
                      ? 'Сглаженные кривые, градиентная заливка и свечение'
                      : 'Зелёный цифровой дождь и светящаяся линия',
                  checked: graphFromUi(c.ui) == k,
                  onTap: () {
                    Navigator.pop(c2);
                    c.setPref('graph', k);
                  },
                ),
            ],
          );
        },
      ),
      item(
        p,
        'DNS',
        desc: dnsDesc(s),
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
                  checked: (s['dns'] ?? 'auto') == k,
                  onTap: () async {
                    Navigator.pop(c2);
                    if (k == 'custom') {
                      await customDnsDialog(context, c, p);
                    } else {
                      await c.saveSettings({'dns': k});
                    }
                    if (c.connected) {
                      await c.call('Disconnect');
                      await c.call('Connect');
                    }
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
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => SplitAppsPage(c: c)));
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
        'autoBest',
        'Автовыбор самого быстрого',
        'После пинга, пока нет соединения, выбирается сервер с меньшей задержкой',
      ),
      swItem(
        'fastDial',
        'Быстрое соединение',
        'TCP Fast Open и мультиплексирование там, где это безопасно (не VLESS+Vision и не QUIC)',
      ),
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
        desc:
            'График на частоте экрана; выключите для экономии на слабых устройствах',
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
          await c.refresh();
          if (!ctx.mounted) return;
          if (c.s['update'] is Map) {
            await offerUpdate(ctx, c, p);
          } else {
            toast(ctx, '$r');
          }
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

void listSheet(
  BuildContext context,
  NoxController c,
  Pal p, {
  String? caption,
}) => sheet(
  context,
  p,
  noTopBar ? '' : 'Список',
  (ctx) => listItems(context, ctx, c, p, caption: noTopBar ? null : caption),
);

/// Items of the list menu (sort, view, filters…); also appended to the first server's ⋮.
List<Widget> listItems(
  BuildContext context,
  BuildContext ctx,
  NoxController c,
  Pal p, {
  String? caption,
}) {
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
    if (c.accordion && c.subs.isEmpty)
      item(
        p,
        'Пинг всех серверов',
        onTap: () {
          Navigator.pop(ctx);
          c.ping(c.visible().map((e) => e['id'] as String).toList());
          toast(context, 'Проверяю пинг…');
        },
      ),
    // 2.2.1: Android keeps the current sort and view; the rows are gone from the menu.
    if (!noTopBar) ...[
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
    ],
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
          if (context.mounted) await finishRefresh(context, c, r);
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
        'Показать QR',
        desc: 'Отсканировать подписку другим устройством',
        onTap: () async {
          Navigator.pop(ctx);
          final t = await c.call('SubLink', [b['id']]);
          if (context.mounted && t is String && t.isNotEmpty)
            showLinkQr(context, (b['name'] ?? 'Подписка') as String, t);
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

void serverSheet(
  BuildContext context,
  NoxController c,
  Pal p,
  J s, {
  String? listCaption,
}) {
  sheet(
    context,
    p,
    _dispName(s['name'] ?? ''),
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
        'Показать QR',
        desc: 'Отсканировать сервер другим устройством',
        onTap: () async {
          Navigator.pop(ctx);
          final t = await c.call('ServerLink', [s['id']]);
          if (context.mounted && t is String && t.isNotEmpty)
            showLinkQr(context, (s['name'] ?? 'Сервер') as String, t);
        },
      ),
      if (s['type'] == 'qWDTT')
        item(
          p,
          'TURN по TCP',
          desc: 'Если по UDP не подключается (Nox и так пробует TCP сам)',
          trailing: sw(p, (s['outbound'] as Map?)?['turn_tcp'] == true),
          onTap: () async {
            Navigator.pop(ctx);
            await c.call('SetQwdttTCP', [
              s['id'],
              (s['outbound'] as Map?)?['turn_tcp'] != true,
            ]);
            c.refresh();
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
      // first server's ⋮ also carries the list menu (the list header is gone on phones)
      if (listCaption != null) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Text(
            'СПИСОК СЕРВЕРОВ',
            style: TextStyle(
              color: p.acc2,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        ...listItems(context, ctx, c, p, caption: listCaption),
      ],
    ],
  );
}

/// Error line inside the add sheet. The sheet stays open when import fails,
/// because a toast behind the modal is easy to miss.
class _ImportButton extends StatefulWidget {
  final BuildContext host;
  final BuildContext sheet;
  final NoxController c;
  final Pal p;
  final TextEditingController tc;
  const _ImportButton({
    required this.host,
    required this.sheet,
    required this.c,
    required this.p,
    required this.tc,
  });
  @override
  State<_ImportButton> createState() => _ImportButtonState();
}

class _ImportButtonState extends State<_ImportButton> {
  bool busy = false;
  String? err;
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (err != null) ...[
          Text(err!, style: TextStyle(color: p.red, fontSize: 13)),
          const SizedBox(height: 8),
        ],
        _Btn(
          p: p,
          label: busy ? 'Добавляю…' : 'Добавить',
          onTap: () async {
            if (busy) return;
            setState(() {
              busy = true;
              err = null;
            });
            final r = await widget.c.call('Import', [widget.tc.text]);
            if (!mounted) return;
            if (r is Map && r['ok'] == true) {
              if (widget.sheet.mounted) Navigator.pop(widget.sheet);
              await widget.c.refresh();
              if (widget.host.mounted) {
                final errs = (r['errors'] as List?)?.length ?? 0;
                toast(
                  widget.host,
                  '${r['msg']}${errs > 0 ? ' · ошибок: $errs' : ''}',
                );
              }
              return;
            }
            final msg = r is Map && '${r['msg'] ?? ''}'.isNotEmpty
                ? '${r['msg']}'
                : (widget.c.fatal ?? 'Не удалось добавить');
            setState(() {
              busy = false;
              err = msg;
            });
          },
        ),
      ],
    );
  }
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
                'Передать на другое устройство',
                desc:
                    'ТВ, магнитола и т.п. в этой же Wi‑Fi сети: сканируйте их QR или введите код',
                arrow: true,
                onTap: () {
                  Navigator.pop(ctx);
                  openSend(context, c);
                },
              )
            : item(
                p,
                'Принять с телефона',
                desc:
                    'Для устройств без камеры (ТВ, магнитола): покажет QR и код, телефон передаст подписки по Wi‑Fi',
                arrow: true,
                onTap: () {
                  Navigator.pop(ctx);
                  openReceive(context, c);
                },
              ),
      if (!isAndroid && !c.isTv)
        item(
          p,
          'Подключиться к телефону',
          desc: 'Интернет через VPN телефона (Nox → «Раздача VPN»)',
          arrow: true,
          onTap: () {
            Navigator.pop(ctx);
            connectPhoneDialog(context, c, p);
          },
        ),
      if (!c.isTv)
        item(
          p,
          'Цепочка',
          desc:
              'Свой маршрут из 2–3 серверов: каждый следующий идёт через предыдущий',
          arrow: true,
          onTap: () {
            Navigator.pop(ctx);
            chainSheet(context, c, p);
          },
        ),
      item(
        p,
        'Добавить вручную',
        desc: 'Форма по протоколу, цифровая клавиатура для адреса и порта',
        arrow: true,
        onTap: () {
          Navigator.pop(ctx);
          manualSheet(context, c, p);
        },
      ),
      const SizedBox(height: 12),
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
      _ImportButton(host: context, sheet: ctx, c: c, p: p, tc: tc),
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

bool _chainable(J s) {
  final t = '${s['type'] ?? ''}';
  const bad = [
    'qWDTT',
    'SSTP',
    'WireGuard',
    'Автовыбор',
    'Цепочка',
    'AmneziaWG',
  ];
  return !bad.contains(t) && !t.contains('XHTTP');
}

/// Exclave-style client chain: pick 2-3 servers in order; hop N dials through hop N-1.
void chainSheet(BuildContext context, NoxController c, Pal p) {
  final picked = <String>[];
  final nc = TextEditingController();
  final list = c.servers.where(_chainable).toList();
  sheet(
    context,
    p,
    'Цепочка',
    (ctx) => [
      StatefulBuilder(
        builder: (ctx2, set) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Выберите 2–3 сервера по порядку: первый — вход, последний — выход в интернет. '
              'Подходят VLESS, Trojan, VMess, Shadowsocks, SOCKS, HTTP, AnyTLS, TUIC, Hysteria2. '
              'qWDTT, XHTTP, WireGuard, Naive, Mieru, Juicity, TrustTunnel, Snell и ShadowQUIC в прокси-цепь не ставятся.',
              style: TextStyle(color: p.sub, fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nc,
              style: TextStyle(color: p.txt),
              decoration: InputDecoration(
                hintText: 'Название (необязательно)',
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
            if (list.isEmpty)
              Text('Нет подходящих серверов', style: TextStyle(color: p.sub)),
            for (final s in list)
              item(
                p,
                '${s['name']}',
                desc: '${s['type']}',
                checked: picked.contains(s['id']),
                trailing: picked.contains(s['id'])
                    ? Text(
                        '${picked.indexOf(s['id']) + 1}',
                        style: TextStyle(
                          color: p.txt,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      )
                    : null,
                onTap: () => set(() {
                  final id = s['id'] as String;
                  if (picked.contains(id)) {
                    picked.remove(id);
                  } else if (picked.length < 3) {
                    picked.add(id);
                  }
                }),
              ),
            const SizedBox(height: 12),
            _Btn(
              p: p,
              label: picked.length < 2
                  ? 'Выберите ещё ${2 - picked.length}'
                  : 'Сохранить прокси-цепь',
              onTap: () async {
                if (picked.length < 2) return;
                final r = await c.call('CreateChain', [nc.text.trim(), picked]);
                c.refresh();
                if (!ctx.mounted) return;
                if (r != null && '$r'.isNotEmpty) {
                  toast(ctx, '$r');
                  return;
                }
                Navigator.pop(ctx);
                if (context.mounted) toast(context, 'Прокси-цепь сохранена');
              },
            ),
          ],
        ),
      ),
    ],
  );
}

/// One form field of «Добавить вручную».
class _MF {
  final String k, label;
  final String def;
  final List<String>? opts; // dropdown
  final bool flag; // switch
  const _MF(this.k, this.label, {this.def = '', this.opts, this.flag = false});
}

const _mfHost = _MF('host', 'Адрес (IP или домен)');
const _mfPort = _MF('port', 'Порт', def: '443');
const _mfName = _MF('name', 'Название');
const _mfSni = _MF('sni', 'SNI (необязательно)');
const _mfIns = _MF('insecure', 'Не проверять сертификат', flag: true);

Iterable<String> get manualProtocols => _manualProtos.keys;

final Map<String, List<_MF>> _manualProtos = {
  'HTTP': [
    _mfName,
    _mfHost,
    const _MF('port', 'Порт', def: '8080'),
    const _MF('user', 'Логин'),
    const _MF('pass', 'Пароль'),
    const _MF('tls', 'TLS (HTTPS)', flag: true),
    _mfSni,
  ],
  'SOCKS5': [
    _mfName,
    _mfHost,
    const _MF('port', 'Порт', def: '1080'),
    const _MF('user', 'Логин'),
    const _MF('pass', 'Пароль'),
  ],
  'Shadowsocks': [
    _mfName,
    _mfHost,
    const _MF('port', 'Порт', def: '8388'),
    const _MF(
      'method',
      'Шифрование',
      def: '2022-blake3-aes-128-gcm',
      opts: [
        '2022-blake3-aes-128-gcm',
        '2022-blake3-aes-256-gcm',
        '2022-blake3-chacha20-poly1305',
        'aes-128-gcm',
        'aes-256-gcm',
        'chacha20-ietf-poly1305',
      ],
    ),
    const _MF('pass', 'Пароль'),
  ],
  'VLESS': [
    _mfName,
    _mfHost,
    _mfPort,
    const _MF('uuid', 'UUID'),
    const _MF(
      'security',
      'Защита',
      def: 'tls',
      opts: ['tls', 'reality', 'none'],
    ),
    _mfSni,
    const _MF('pbk', 'Публичный ключ Reality'),
    const _MF('sid', 'Short ID Reality'),
    const _MF('flow', 'Flow', def: '', opts: ['', 'xtls-rprx-vision']),
    const _MF(
      'type',
      'Транспорт',
      def: 'tcp',
      opts: ['tcp', 'ws', 'grpc', 'httpupgrade', 'xhttp'],
    ),
    const _MF('path', 'Путь / serviceName'),
    const _MF(
      'fp',
      'Отпечаток TLS',
      def: 'chrome',
      opts: ['chrome', 'firefox', 'safari', 'edge', 'random', 'none'],
    ),
  ],
  'VMess': [
    _mfName,
    _mfHost,
    _mfPort,
    const _MF('uuid', 'UUID'),
    const _MF('tls', 'TLS', flag: true),
    _mfSni,
    const _MF(
      'type',
      'Транспорт',
      def: 'tcp',
      opts: ['tcp', 'ws', 'grpc', 'httpupgrade'],
    ),
    const _MF('path', 'Путь / serviceName'),
  ],
  'Trojan': [
    _mfName,
    _mfHost,
    _mfPort,
    const _MF('pass', 'Пароль'),
    _mfSni,
    const _MF('type', 'Транспорт', def: 'tcp', opts: ['tcp', 'ws', 'grpc']),
    const _MF('path', 'Путь / serviceName'),
    _mfIns,
  ],
  'AnyTLS': [
    _mfName,
    _mfHost,
    _mfPort,
    const _MF('pass', 'Пароль'),
    _mfSni,
    _mfIns,
  ],
  'TUIC': [
    _mfName,
    _mfHost,
    _mfPort,
    const _MF('uuid', 'UUID'),
    const _MF('pass', 'Пароль'),
    _mfSni,
    const _MF(
      'cc',
      'Управление перегрузкой',
      def: 'bbr',
      opts: ['bbr', 'cubic', 'new_reno'],
    ),
    _mfIns,
  ],
  'Hysteria2': [
    _mfName,
    _mfHost,
    _mfPort,
    const _MF('pass', 'Пароль'),
    _mfSni,
    const _MF('obfs', 'Обфускация salamander (пароль)'),
    _mfIns,
  ],
  'WireGuard': [
    _mfName,
    _mfHost,
    const _MF('port', 'Порт', def: '51820'),
    const _MF('priv', 'Приватный ключ'),
    const _MF('pub', 'Публичный ключ сервера'),
    const _MF('addr', 'Адрес интерфейса', def: '10.0.0.2/32'),
    const _MF('psk', 'Общий ключ (необязательно)'),
    const _MF('mtu', 'MTU', def: '1420'),
  ],
  'Naive': [
    _mfName,
    _mfHost,
    _mfPort,
    const _MF('user', 'Логин'),
    const _MF('pass', 'Пароль'),
    const _MF('quic', 'QUIC вместо HTTPS', flag: true),
    _mfSni,
  ],
  'Mieru': [
    _mfName,
    _mfHost,
    const _MF('port', 'Порт или диапазон', def: '2999'),
    const _MF('user', 'Логин'),
    const _MF('pass', 'Пароль'),
    const _MF('proto', 'Транспорт', def: 'TCP', opts: ['TCP', 'UDP']),
    const _MF(
      'mux',
      'Мультиплексирование',
      def: 'MULTIPLEXING_LOW',
      opts: [
        'MULTIPLEXING_OFF',
        'MULTIPLEXING_LOW',
        'MULTIPLEXING_MIDDLE',
        'MULTIPLEXING_HIGH',
      ],
    ),
  ],
  'Juicity': [
    _mfName,
    _mfHost,
    _mfPort,
    const _MF('uuid', 'UUID'),
    const _MF('pass', 'Пароль'),
    _mfSni,
    const _MF(
      'cc',
      'Управление перегрузкой',
      def: 'bbr',
      opts: ['bbr', 'cubic', 'new_reno'],
    ),
    _mfIns,
  ],
  'TrustTunnel': [
    _mfName,
    _mfHost,
    _mfPort,
    const _MF('user', 'Логин'),
    const _MF('pass', 'Пароль'),
    _mfSni,
    const _MF('quic', 'HTTP/3 (QUIC)', flag: true),
    _mfIns,
  ],
  'Snell': [
    _mfName,
    _mfHost,
    _mfPort,
    const _MF('psk', 'Ключ (PSK)'),
    const _MF('ver', 'Версия', def: '4', opts: ['1', '2', '3', '4', '5']),
    const _MF('obfs', 'Обфускация', def: 'none', opts: ['none', 'http', 'tls']),
    const _MF('ohost', 'Хост обфускации'),
  ],
  'ShadowQUIC': [
    _mfName,
    _mfHost,
    _mfPort,
    const _MF('user', 'Логин'),
    const _MF('pass', 'Пароль'),
    _mfSni,
    const _MF('alpn', 'ALPN', def: 'h3'),
    const _MF(
      'cc',
      'Управление перегрузкой',
      def: 'bbr',
      opts: ['bbr', 'cubic', 'new_reno'],
    ),
  ],
};

String _enc(String s) => Uri.encodeComponent(s);

String _q(Map<String, String> m) {
  final e = m.entries
      .where((x) => x.value.isNotEmpty)
      .map((x) => '${x.key}=${_enc(x.value)}');
  return e.isEmpty ? '' : '?${e.join('&')}';
}

/// Builds a share link from the form; the engine parses it like any subscription link.
String manualLink(String proto, Map<String, String> v) {
  String g(String k) => (v[k] ?? '').trim();
  final hp =
      '${g('host').contains(':') && !g('host').startsWith('[') ? '[${g('host')}]' : g('host')}:${g('port')}';
  final name = g('name').isEmpty ? '' : '#${_enc(g('name'))}';
  final ins = g('insecure') == '1' ? '1' : '';
  String up(String u, String p) => u.isEmpty && p.isEmpty
      ? ''
      : '${_enc(u)}${p.isEmpty ? '' : ':${_enc(p)}'}@';
  switch (proto) {
    case 'HTTP':
      return '${g('tls') == '1' ? 'https' : 'http'}://${up(g('user'), g('pass'))}$hp${_q({'sni': g('sni')})}$name';
    case 'SOCKS5':
      return 'socks5://${up(g('user'), g('pass'))}$hp$name';
    case 'Shadowsocks':
      final ui = base64Url
          .encode(utf8.encode('${g('method')}:${g('pass')}'))
          .replaceAll('=', '');
      return 'ss://$ui@$hp$name';
    case 'VLESS':
      final t = g('type');
      return 'vless://${g('uuid')}@$hp${_q({'encryption': 'none', 'security': g('security'), 'sni': g('sni'), 'pbk': g('pbk'), 'sid': g('sid'), 'flow': g('flow'), 'type': t, if (t == 'grpc') 'serviceName': g('path') else 'path': g('path'), 'fp': g('fp')})}$name';
    case 'VMess':
      final j = {
        'v': '2',
        'ps': g('name'),
        'add': g('host'),
        'port': g('port'),
        'id': g('uuid'),
        'aid': '0',
        'scy': 'auto',
        'net': g('type'),
        'path': g('path'),
        'tls': g('tls') == '1' ? 'tls' : '',
        'sni': g('sni'),
      };
      return 'vmess://${base64.encode(utf8.encode(jsonEncode(j)))}';
    case 'Trojan':
      final t = g('type');
      return 'trojan://${_enc(g('pass'))}@$hp${_q({'security': 'tls', 'sni': g('sni'), 'type': t, if (t == 'grpc') 'serviceName': g('path') else 'path': g('path'), 'allowInsecure': ins})}$name';
    case 'AnyTLS':
      return 'anytls://${_enc(g('pass'))}@$hp${_q({'sni': g('sni'), 'insecure': ins})}$name';
    case 'TUIC':
      return 'tuic://${up(g('uuid'), g('pass'))}$hp${_q({'sni': g('sni'), 'congestion_control': g('cc'), 'alpn': 'h3', 'allow_insecure': ins})}$name';
    case 'Hysteria2':
      return 'hy2://${_enc(g('pass'))}@$hp${_q({'sni': g('sni'), if (g('obfs').isNotEmpty) 'obfs': 'salamander', 'obfs-password': g('obfs'), 'insecure': ins})}$name';
    case 'WireGuard':
      return 'wireguard://${_enc(g('priv'))}@$hp${_q({'publickey': g('pub'), 'address': g('addr'), 'presharedkey': g('psk'), 'mtu': g('mtu')})}$name';
    case 'Naive':
      return '${g('quic') == '1' ? 'naive+quic' : 'naive+https'}://${up(g('user'), g('pass'))}$hp${_q({'sni': g('sni')})}$name';
    case 'Mieru':
      return 'mierus://${up(g('user'), g('pass'))}${g('host')}${_q({'port': g('port'), 'protocol': g('proto'), 'multiplexing': g('mux')})}$name';
    case 'Juicity':
      return 'juicity://${up(g('uuid'), g('pass'))}$hp${_q({'sni': g('sni'), 'congestion_control': g('cc'), 'allow_insecure': ins})}$name';
    case 'TrustTunnel':
      return 'trusttunnel://${up(g('user'), g('pass'))}$hp${_q({'sni': g('sni'), 'quic': g('quic'), 'insecure': ins})}$name';
    case 'Snell':
      return 'snell://${_enc(g('psk'))}@$hp${_q({'version': g('ver'), 'obfs': g('obfs') == 'none' ? '' : g('obfs'), 'obfs-host': g('ohost')})}$name';
    case 'ShadowQUIC':
      return 'shadowquic://${up(g('user'), g('pass'))}$hp${_q({'sni': g('sni'), 'alpn': g('alpn'), 'congestion': g('cc')})}$name';
  }
  return '';
}

/// «Добавить вручную»: protocol picker + per-protocol form (Exclave-style).
class _NumPad extends StatelessWidget {
  final Pal p;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool dot;
  final bool colon;
  const _NumPad({
    required this.p,
    required this.controller,
    required this.onChanged,
    this.dot = false,
    this.colon = false,
  });

  void _set(String next) {
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final keys = <String>[
      for (var i = 1; i <= 9; i++) '$i',
      if (dot) '.',
      '0',
      if (colon) ':',
      '⌫',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final k in keys)
            InkWell(
              onTap: () {
                final t = controller.text;
                if (k == '⌫') {
                  if (t.isNotEmpty) _set(t.substring(0, t.length - 1));
                  return;
                }
                _set(t + k);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 36,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.chip,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: p.line),
                ),
                child: Text(k, style: TextStyle(color: p.txt, fontSize: 14)),
              ),
            ),
        ],
      ),
    );
  }
}

String _countryOf(String name) {
  final iso = region(name);
  if (iso == null) return '';
  return regionName[iso] ?? '';
}

class _TextPanel extends StatelessWidget {
  final NoxController c;
  final Pal p;
  const _TextPanel({required this.c, required this.p});

  @override
  Widget build(BuildContext context) {
    final on = c.connected;
    final st = c.status;
    final label = on
        ? 'Подключено'
        : st == 'connecting'
        ? 'Подключение…'
        : st == 'disconnecting'
        ? 'Отключение…'
        : 'Отключено';
    final cur = c.current;
    final name = cur == null ? '' : '${cur['name'] ?? ''}';
    final country = _countryOf(name);
    final proto = cur == null ? '' : '${cur['type'] ?? ''}';
    final ping = cur == null ? '—' : pingText(cur['ping'] as int?);
    final t = c.traffic;
    final servers = c.servers.where((s) => s['type'] != '_balancer').toList();
    Text row(String k, String v) => Text(
      '$k: $v',
      style: TextStyle(color: p.txt, fontSize: 16, height: 1.4),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          label,
          style: TextStyle(
            color: p.txt,
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        row('Сервер', name.isEmpty ? 'не выбран' : _dispName(name)),
        row('Страна', country.isEmpty ? '—' : country),
        row('Пинг', ping),
        row('Протокол', proto.isEmpty ? '—' : proto),
        row(
          'Скорость',
          '↓ ${fmtBytes(t?['Down'] ?? 0)}/с   ↑ ${fmtBytes(t?['Up'] ?? 0)}/с',
        ),
        row(
          'Трафик',
          '↓ ${fmtBytes(t?['DownTotal'] ?? 0)}   ↑ ${fmtBytes(t?['UpTotal'] ?? 0)}',
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 64,
          child: Material(
            color: p.acc,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: c.busy ? null : c.toggle,
              child: Center(
                child: Text(
                  on ? 'Отключить' : 'Подключить',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
        Wrap(
          spacing: 4,
          children: [
            TextButton(
              onPressed: () => settingsSheet(context, c, p),
              child: Text('Настройки', style: TextStyle(color: p.acc2)),
            ),
            TextButton(
              onPressed: () => addSheet(context, c, p),
              child: Text('Добавить', style: TextStyle(color: p.acc2)),
            ),
            TextButton(
              onPressed: () => c.ping(const []),
              child: Text('Пинг', style: TextStyle(color: p.acc2)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              'Подписки',
              style: TextStyle(
                color: p.txt,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () async {
                final r = await c.call('RefreshSubs');
                if (context.mounted) await finishRefresh(context, c, r);
              },
              child: Text('Обновить', style: TextStyle(color: p.acc2)),
            ),
          ],
        ),
        if (c.subs.isEmpty)
          Text('Нет подписок', style: TextStyle(color: p.sub))
        else
          for (final sub in c.subs)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${sub['name'] ?? sub['url'] ?? 'Подписка'}',
                      style: TextStyle(color: p.txt, fontSize: 14),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final r = await c.call('RefreshSub', [sub['id']]);
                      if (context.mounted) await finishRefresh(context, c, r);
                    },
                    child: Text('Обновить', style: TextStyle(color: p.sub)),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 8),
        Text(
          'Серверы',
          style: TextStyle(
            color: p.txt,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        for (final s in servers)
          InkWell(
            onTap: () => c.call('Select', [s['id']]),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${s['id'] == c.selected ? '● ' : ''}${_dispName('${s['name'] ?? ''}')}'
                      '${_countryOf('${s['name'] ?? ''}') == '' ? '' : ' · ${_countryOf('${s['name'] ?? ''}')}'}'
                      ' · ${s['type'] ?? ''}',
                      style: TextStyle(color: p.txt, fontSize: 15, height: 1.3),
                    ),
                  ),
                  Text(
                    pingText(s['ping'] as int?),
                    style: TextStyle(color: p.txt, fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

void manualSheet(BuildContext context, NoxController c, Pal p) {
  var proto = 'VLESS';
  final vals = <String, Map<String, String>>{};
  final ctrls = <String, TextEditingController>{};
  final paste = TextEditingController();
  Map<String, String> cur() => vals.putIfAbsent(
    proto,
    () => {for (final f in _manualProtos[proto]!) f.k: f.def},
  );
  TextEditingController tc(String k) => ctrls.putIfAbsent(
    '$proto/$k',
    () => TextEditingController(text: cur()[k]),
  );
  InputDecoration deco(String l) => InputDecoration(
    labelText: l,
    labelStyle: TextStyle(color: p.sub, fontSize: 13),
    filled: true,
    fillColor: p.chip,
    isDense: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: p.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: p.line),
    ),
  );
  sheet(
    context,
    p,
    'Добавить вручную',
    (ctx) => [
      StatefulBuilder(
        builder: (ctx2, set) {
          final v = cur();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: paste,
                minLines: 1,
                maxLines: 4,
                style: TextStyle(color: p.txt, fontSize: 14),
                decoration: deco(
                  'Вставить ссылку vless://, vmess:// или подписку',
                ),
              ),
              const SizedBox(height: 8),
              _Btn(
                p: p,
                secondary: true,
                label: 'Добавить из ссылки или буфера',
                onTap: () async {
                  var text = paste.text.trim();
                  if (text.isEmpty) {
                    final clip = await Clipboard.getData('text/plain');
                    text = clip?.text?.trim() ?? '';
                  }
                  if (!ctx.mounted) return;
                  if (text.isEmpty) {
                    toast(ctx, 'Нечего добавить');
                    return;
                  }
                  final r = await c.call('Import', [text]);
                  await c.refresh();
                  if (!ctx.mounted) return;
                  if (r is Map) {
                    final errs = (r['errors'] as List?)?.length ?? 0;
                    toast(
                      ctx,
                      '${r['msg']}${errs > 0 ? ' · ошибок: $errs' : ''}',
                    );
                    if (errs == 0 && '${r['msg']}'.contains('Добавлено')) {
                      Navigator.pop(ctx);
                    }
                  }
                },
              ),
              const SizedBox(height: 12),
              Text('Протокол', style: TextStyle(color: p.sub, fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in _manualProtos.keys)
                    ChoiceChip(
                      label: Text(k),
                      selected: proto == k,
                      onSelected: (_) => set(() => proto = k),
                      labelStyle: TextStyle(
                        color: proto == k ? Colors.white : p.txt,
                        fontSize: 12.5,
                      ),
                      selectedColor: p.acc,
                      backgroundColor: p.chip,
                      side: BorderSide(color: proto == k ? p.acc : p.line),
                      showCheckmark: false,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              for (final f in _manualProtos[proto]!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: f.flag
                      ? InkWell(
                          onTap: () =>
                              set(() => v[f.k] = v[f.k] == '1' ? '' : '1'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    f.label,
                                    style: TextStyle(
                                      color: p.txt,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                sw(p, v[f.k] == '1'),
                              ],
                            ),
                          ),
                        )
                      : f.opts != null
                      ? DropdownButtonFormField<String>(
                          key: ValueKey('$proto/${f.k}'),
                          initialValue: f.opts!.contains(v[f.k])
                              ? v[f.k]
                              : f.opts!.first,
                          decoration: deco(f.label),
                          dropdownColor: p.hero,
                          style: TextStyle(color: p.txt, fontSize: 14),
                          items: [
                            for (final o in f.opts!)
                              DropdownMenuItem(
                                value: o,
                                child: Text(
                                  o.isEmpty ? 'нет' : o,
                                  style: TextStyle(
                                    color: p.txt,
                                    fontSize: 14,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                              ),
                          ],
                          onChanged: (x) => set(() => v[f.k] = x ?? ''),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: tc(f.k),
                              onChanged: (x) => v[f.k] = x,
                              keyboardType: f.k == 'port' || f.k == 'mtu'
                                  ? TextInputType.number
                                  : TextInputType.text,
                              style: TextStyle(color: p.txt, fontSize: 14),
                              decoration: deco(f.label),
                            ),
                            if (f.k == 'host' || f.k == 'port' || f.k == 'mtu')
                              _NumPad(
                                p: p,
                                controller: tc(f.k),
                                dot: f.k == 'host',
                                colon: f.k == 'host',
                                onChanged: (x) => v[f.k] = x,
                              ),
                          ],
                        ),
                ),
              const SizedBox(height: 6),
              _Btn(
                p: p,
                label: 'Сохранить',
                onTap: () async {
                  if ((v['host'] ?? '').trim().isEmpty) {
                    toast(ctx, 'Укажите адрес сервера');
                    return;
                  }
                  final r = await c.call('AddManual', [manualLink(proto, v)]);
                  c.refresh();
                  if (!ctx.mounted) return;
                  if (r != null && '$r'.isNotEmpty) {
                    toast(ctx, '$r');
                    return;
                  }
                  Navigator.pop(ctx);
                  if (context.mounted) toast(context, 'Сервер добавлен');
                },
              ),
            ],
          );
        },
      ),
    ],
  );
}

Future<int?> portDialog(BuildContext context, Pal p, int cur) async {
  final ctl = TextEditingController(text: '$cur');
  String? err;
  return showDialog<int>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        backgroundColor: p.card,
        title: Text('Порт прокси', style: TextStyle(color: p.txt)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: TextStyle(color: p.txt),
          decoration: InputDecoration(hintText: '10808', errorText: err),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(ctl.text.trim());
              if (v == null || v < 1024 || v > 65535)
                return set(() => err = 'Порт от 1024 до 65535');
              Navigator.pop(d, v);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
}

// ---- 1.0.20 «Раздача VPN» (Android: hotspot / USB tethering) and «Подключиться к телефону» (PC) ----

Future<void> shareVpnDialog(
  BuildContext context,
  NoxController c,
  Pal p,
) async {
  J info = {};
  Future<void> load() async {
    final r = await c.call('ShareInfo');
    if (r is Map) info = r.cast<String, dynamic>();
  }

  await load();
  if (!context.mounted) return;
  final uc = TextEditingController(text: '${info['user'] ?? ''}');
  final pc = TextEditingController(text: '${info['pass'] ?? ''}');
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final on = info['on'] == true;
        final port = info['port'] ?? 10808;
        final ips = ((info['ips'] as List?) ?? []).cast<Map>();
        final st = TextStyle(color: p.txt, fontSize: 15);
        final sub = TextStyle(color: p.sub, fontSize: 13);
        return AlertDialog(
          backgroundColor: p.card,
          title: Text('Раздача VPN', style: TextStyle(color: p.txt)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Включите на телефоне точку доступа или USB-модем, подключите ПК, '
                  'затем на ПК в Nox: «+» → «Подключиться к телефону» (или укажите прокси вручную).',
                  style: sub,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: on,
                  title: Text('Раздавать через прокси', style: st),
                  subtitle: Text(
                    'HTTP и SOCKS5 на всех сетях телефона',
                    style: sub,
                  ),
                  onChanged: (v) async {
                    await c.saveSettings({
                      'allowLan': v,
                      'shareUser': uc.text.trim(),
                      'sharePass': pc.text,
                    });
                    if (c.connected) {
                      await c.call('Disconnect');
                      await c.call('Connect');
                    }
                    await load();
                    set(() {});
                  },
                ),
                TextField(
                  controller: uc,
                  style: st,
                  decoration: const InputDecoration(
                    labelText: 'Логин (необязательно)',
                  ),
                ),
                TextField(
                  controller: pc,
                  style: st,
                  decoration: const InputDecoration(
                    labelText: 'Пароль (необязательно)',
                  ),
                ),
                const SizedBox(height: 12),
                if (on && ips.isEmpty)
                  Text(
                    'Нет локальных сетей: включите точку доступа или USB-модем',
                    style: sub,
                  ),
                if (on)
                  for (final e in ips)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: SelectableText('${e['ip']}:$port', style: st),
                      subtitle: Text('${e['kind']} (${e['name']})', style: sub),
                      trailing: IconButton(
                        icon: Icon(Icons.copy_rounded, color: p.sub),
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: '${e['ip']}:$port'),
                        ),
                      ),
                    ),
                if (on && info['connected'] != true)
                  Text(
                    'Подключите VPN — прокси работает только при подключении',
                    style: TextStyle(color: p.amb, fontSize: 13),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Android не позволяет направить в VPN весь трафик точки доступа без root, '
                  'поэтому ПК использует прокси телефона.',
                  style: sub,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await c.saveSettings({
                  'shareUser': uc.text.trim(),
                  'sharePass': pc.text,
                });
                if (on && c.connected) {
                  await c.call('Disconnect');
                  await c.call('Connect');
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Готово'),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> connectPhoneDialog(
  BuildContext context,
  NoxController c,
  Pal p,
) async {
  final ac = TextEditingController();
  final uc = TextEditingController();
  final pc = TextEditingController();
  final st = TextStyle(color: p.txt, fontSize: 15);
  final link = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: p.card,
      title: Text('Подключиться к телефону', style: TextStyle(color: p.txt)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'На телефоне: Nox → Настройки → «Раздача VPN». Подключите ПК к его точке доступа '
            'или по USB (USB-модем) и введите адрес, показанный на телефоне.',
            style: TextStyle(color: p.sub, fontSize: 13),
          ),
          TextField(
            controller: ac,
            style: st,
            decoration: const InputDecoration(
              labelText: 'Адрес, например 192.168.43.1:10808',
            ),
          ),
          TextField(
            controller: uc,
            style: st,
            decoration: const InputDecoration(labelText: 'Логин (если задан)'),
          ),
          TextField(
            controller: pc,
            style: st,
            decoration: const InputDecoration(labelText: 'Пароль (если задан)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () {
            final a = ac.text.trim();
            if (!RegExp(r'^[0-9.]+:[0-9]{2,5}$').hasMatch(a)) return;
            final auth = uc.text.trim().isEmpty
                ? ''
                : '${Uri.encodeComponent(uc.text.trim())}:${Uri.encodeComponent(pc.text)}@';
            Navigator.pop(
              ctx,
              'socks://$auth$a#${Uri.encodeComponent('📱 Телефон')}',
            );
          },
          child: const Text('Подключить'),
        ),
      ],
    ),
  );
  if (link == null) return;
  final r = await c.call('AddManual', [link]);
  if (r is String && r.isNotEmpty) {
    if (context.mounted) toast(context, r);
    return;
  }
  await c.refresh();
  if (c.connected) await c.call('Disconnect');
  await c.call('Connect');
  c.refresh();
}

/// Settings → «Цветовой шаблон»: swatch cards for every template.
Future<void> templateSheet(BuildContext context, NoxController c, Pal p) =>
    sheet(context, p, 'Цветовой шаблон', (ctx) => [TemplatePicker(c: c)]);

class TemplatePicker extends StatelessWidget {
  final NoxController c;
  const TemplatePicker({super.key, required this.c});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final theme = c.settings['theme'] as String?;
      final cur = c.pref('tpl', 'glass');
      final p = Pal.of(theme, cur);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Цвета акцентов и градиентов. Тёмная/светлая/AMOLED — в «Тема».',
              style: TextStyle(color: p.sub, fontSize: 12.5),
            ),
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.25,
            children: [
              for (final t in templates)
                _TplCard(
                  p: p,
                  t: Pal.of(theme, t.key),
                  name: t.name,
                  mono: t.key == 'mono',
                  on: t.key == cur,
                  onTap: () => c.setPrefLive('tpl', t.key),
                ),
            ],
          ),
        ],
      );
    },
  );
}

class _TplCard extends StatelessWidget {
  final Pal p, t;
  final String name;
  final bool mono, on;
  final VoidCallback onTap;
  const _TplCard({
    required this.p,
    required this.t,
    required this.name,
    required this.mono,
    required this.on,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    selected: on,
    button: true,
    label: name,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: on ? t.acc2 : p.line, width: on ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // mini subscription card in the template's glass gradient
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
                decoration: glassBox(t, r: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [t.acc, t.acc2]),
                          ),
                          child: const Icon(
                            Icons.power_settings_new_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        countryBadge(t, 'TR', 16),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(
                          colors: [t.acc, t.acc2, t.grn],
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        for (final col in [t.acc, t.acc2, t.card, t.txt])
                          Container(
                            margin: const EdgeInsets.only(right: 4),
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: col,
                              shape: BoxShape.circle,
                              border: Border.all(color: t.line),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    mono ? '$name · без флагов' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.txt,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (on)
                  Icon(Icons.check_circle_rounded, size: 18, color: t.acc2),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Phone connection-card layout: 'classic' | 'ring' (1) | 'compact' (2) | 'timer' (3).
String heroStyle = 'timer';

String _hms(int s) {
  if (s < 0) s = 0;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(s ~/ 3600)}:${two((s % 3600) ~/ 60)}:${two(s % 60)}';
}

/// Flexible when [flex], else a bounded box (keeps a Flexible child inside legal).
Widget _flexOr(bool flex, {required Widget child}) => flex
    ? Flexible(child: child)
    : ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 150),
        child: child,
      );

class _HeroAlt extends StatelessWidget {
  final NoxController c;
  final Pal p;
  final String style;
  final bool wide; // desktop: the speed graph has its own card next to this one
  const _HeroAlt({
    required this.c,
    required this.p,
    required this.style,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final on = c.connected, wait = c.busy, st = c.status, cur = c.current;
    final since = (c.s['since'] ?? 0) as int;
    final secs = on && since > 0
        ? DateTime.now().millisecondsSinceEpoch ~/ 1000 - since
        : 0;
    final t = c.traffic;
    final name = cur == null
        ? 'Сервер не выбран'
        : _dispName(cur['name'] ?? '');
    final bal = cur != null && NoxController.isBal(cur);
    final iso = cur == null ? null : region(cur['name'] ?? '');
    final proto = cur == null
        ? ''
        : NoxController.proto(cur).isEmpty
        ? 'Автовыбор'
        : showProto
        ? NoxController.proto(cur)
        : '';
    final label = on
        ? 'Подключено'
        : st == 'connecting'
        ? 'Подключение…'
        : st == 'disconnecting'
        ? 'Отключение…'
        : 'Отключено';
    final stColor = on
        ? p.grn
        : wait
        ? p.amb
        : p.sub;
    final ping = cur == null ? '—' : _pingOf(c, cur);
    Widget badge(double size) => bal || iso == null
        ? Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [p.acc, p.acc2]),
            ),
            child: Icon(
              Icons.bolt_rounded,
              size: size * .6,
              color: Colors.white,
            ),
          )
        : countryBadge(p, iso, size);
    Widget graph(double h) => SizedBox(
      height: h,
      width: double.infinity,
      child: LiveGraph(
        series: c.speed,
        p: p,
        active: c.animSmooth,
        calm: true,
        span: 40,
      ),
    );
    final down = '${fmtBytes(t?['Down'] ?? 0)}/с';
    final up = '${fmtBytes(t?['Up'] ?? 0)}/с';
    final corner = _HeroCorner.of(c, p, wide: wide);

    switch (style) {
      case 'ring':
        return Container(
          padding: EdgeInsets.fromLTRB(
            16,
            corner == null ? 18 : 12,
            corner == null ? 16 : 12,
            12,
          ),
          decoration: glassBox(p, r: 26),
          child: Column(
            children: [
              if (corner != null)
                Align(alignment: Alignment.centerRight, child: corner),
              _GlowRing(
                p: p,
                on: on,
                wait: wait,
                spin: c.animSmooth && (on || wait),
                child: _powerKnob(c, p, size: 104),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  badge(22),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.txt,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  on ? _hms(secs) : label,
                  if (showProto || proto.isNotEmpty) proto,
                ].join('  ·  '),
                style: TextStyle(
                  color: on ? p.acc2 : stColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .6,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      p: p,
                      icon: Icons.south_rounded,
                      label: 'Загрузка',
                      value: down,
                      color: p.acc2,
                    ),
                  ),
                  Container(width: 1, height: 30, color: p.line),
                  Expanded(
                    child: _Stat(
                      p: p,
                      icon: Icons.north_rounded,
                      label: 'Отдача',
                      value: up,
                      color: p.mono ? p.sub : const Color(0xFF34D399),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              graph(52),
            ],
          ),
        );
      case 'compact':
        return Container(
          padding: EdgeInsets.fromLTRB(14, corner == null ? 14 : 10, 14, 10),
          decoration: glassBox(p, r: 22),
          child: Column(
            children: [
              if (corner != null) ...[
                Align(alignment: Alignment.centerRight, child: corner),
                const SizedBox(height: 6),
              ],
              Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: p.acc2.withValues(alpha: .5),
                            width: 1.5,
                          ),
                        ),
                        child: badge(40),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: stColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: p.card, width: 2.5),
                            boxShadow: [
                              if (on)
                                BoxShadow(
                                  color: p.grn.withValues(alpha: .6),
                                  blurRadius: 8,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.txt,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            label,
                            if (showProto || proto.isNotEmpty) proto,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: stColor,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _PillSwitch(c: c, p: p),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: p.bg.withValues(alpha: p.light ? .5 : .35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.line.withValues(alpha: .7)),
                ),
                child: Row(
                  children: [
                    for (final (i, x) in [
                      (Icons.south_rounded, down, p.acc2),
                      (
                        Icons.north_rounded,
                        up,
                        p.mono ? p.sub : const Color(0xFF34D399),
                      ),
                      (Icons.schedule_rounded, on ? _hms(secs) : '—', p.sub),
                      (Icons.bolt_rounded, ping, p.amb),
                    ].indexed) ...[
                      if (i > 0) Container(width: 1, height: 22, color: p.line),
                      Expanded(
                        child: Column(
                          children: [
                            Icon(x.$1, size: 14, color: x.$3),
                            const SizedBox(height: 2),
                            Text(
                              x.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.txt,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (on) ...[const SizedBox(height: 8), graph(30)],
            ],
          ),
        );
      default: // 'timer'
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: on
                  ? [
                      Color.alphaBlend(p.acc.withValues(alpha: .62), p.card),
                      Color.alphaBlend(p.acc2.withValues(alpha: .30), p.card),
                      Color.alphaBlend(p.acc.withValues(alpha: .12), p.card),
                    ]
                  : [
                      Color.alphaBlend(p.acc.withValues(alpha: .22), p.card),
                      Color.alphaBlend(p.acc2.withValues(alpha: .08), p.card),
                      p.card,
                    ],
            ),
            border: Border.all(color: p.acc2.withValues(alpha: .35)),
            boxShadow: [
              BoxShadow(
                color: p.acc.withValues(alpha: on ? .35 : .12),
                blurRadius: 26,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              if (on && !wide)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 70,
                  child: Opacity(opacity: .45, child: graph(48)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  mainAxisAlignment: wide
                      ? MainAxisAlignment.spaceBetween
                      : MainAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _flexOr(
                          corner == null,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .22),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: stColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    label.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: .92,
                                      ),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (corner != null) ...[
                          const Spacer(),
                          corner,
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          flex: 2,
                          child: _Side(
                            icon: Icons.south_rounded,
                            value: down,
                            label: 'загрузка',
                          ),
                        ),
                        Flexible(
                          flex: 5,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _hms(secs),
                              style: TextStyle(
                                color: Colors.white.withValues(
                                  alpha: on ? 1 : .55,
                                ),
                                fontSize: 40,
                                fontWeight: FontWeight.w800,
                                height: 1,
                                letterSpacing: -.5,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: _Side(
                            icon: Icons.north_rounded,
                            value: up,
                            label: 'отдача',
                            end: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 2.2.2: region + protocol prominently under the timer («🇷🇴 Румыния · qWDTT»).
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        badge(24),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            [
                              cur == null
                                  ? name
                                  : (_countryOf(cur['name'] ?? '').isNotEmpty
                                        ? _countryOf(cur['name'] ?? '')
                                        : name),
                              if (cur != null)
                                NoxController.proto(cur).isEmpty
                                    ? 'Автовыбор'
                                    : NoxController.proto(cur),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'пинг $ping',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .7),
                        fontSize: 12,
                      ),
                    ),
                    // 2.1.8: on phone/desktop the pill sits in the bottom bar next to «＋».
                    if (!pillAtBottom(c)) ...[
                      SizedBox(height: wide ? 18 : 40),
                      TapPill(c: c, p: p),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }
}

class _Stat extends StatelessWidget {
  final Pal p;
  final IconData icon;
  final String label, value;
  final Color color;
  const _Stat({
    required this.p,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(color: p.sub, fontSize: 11.5)),
        ],
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: TextStyle(
          color: p.txt,
          fontSize: 16,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

class _Side extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final bool end;
  const _Side({
    required this.icon,
    required this.value,
    required this.label,
    this.end = false,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 15, color: Colors.white.withValues(alpha: .85)),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white.withValues(alpha: .6),
          fontSize: 10.5,
        ),
      ),
    ],
  );
}

/// Variant 2: wide pill toggle switch.
class _PillSwitch extends StatelessWidget {
  final NoxController c;
  final Pal p;
  const _PillSwitch({required this.c, required this.p});
  @override
  Widget build(BuildContext context) {
    final on = c.connected, wait = c.busy;
    return Semantics(
      toggled: on,
      button: true,
      label: on ? 'Отключить' : 'Подключить',
      child: GestureDetector(
        key: TourKeys.power,
        onTap: c.toggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 72,
          height: 40,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: on ? LinearGradient(colors: [p.acc, p.acc2]) : null,
            color: on ? null : (wait ? p.amb.withValues(alpha: .4) : p.chip),
            border: Border.all(
              color: on ? Colors.white.withValues(alpha: .2) : p.line,
            ),
            boxShadow: [
              if (on)
                BoxShadow(color: p.acc.withValues(alpha: .5), blurRadius: 16),
            ],
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? Colors.white : p.sub.withValues(alpha: .7),
                boxShadow: const [
                  BoxShadow(color: Color(0x44000000), blurRadius: 6),
                ],
              ),
              child: Icon(
                Icons.power_settings_new_rounded,
                size: 18,
                color: on ? p.acc : p.card,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 2.2.0: tap still toggles, and the knob can also be dragged along the pill. A drag only
/// fires past [dragFire] of the travel (else the knob snaps back); the recognizer is
/// horizontal-only, so vertical drags keep scrolling the list, and drags shorter than the
/// touch slop never start. Haptic feedback when a drag fires.
/// Variant 3 (2.1.7): tap-to-toggle pill on the «Таймер» card. The 2.1.x swipe slider was
/// too sensitive (it fired while scrolling and missed slow slides), so it is now a plain
/// button: tap = connect, tap again = disconnect (also cancels «Подключение…»).
/// Taps are debounced: while a Connect/Disconnect call is in flight, during «Отключение…»
/// and for [debounce] after the last accepted tap, more taps are ignored. Every action goes
/// through [NoxController.toggle], the same path as the round power knob.
class TapPill extends StatefulWidget {
  final NoxController c;
  final Pal p;
  static Duration debounce = const Duration(milliseconds: 700);
  static const dragFire = .6;
  const TapPill({super.key, required this.c, required this.p});
  @override
  State<TapPill> createState() => TapPillState();
}

class TapPillState extends State<TapPill> {
  static const _knob = 42.0, _pad = 5.0;
  bool _sent = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  double? _drag; // knob position 0 (left) … 1 (right) while a finger drags it
  double _travel = 1;

  NoxController get c => widget.c;
  bool get _right => c.connected || c.status == 'connecting';
  bool get _blocked =>
      _sent ||
      c.status == 'disconnecting' ||
      DateTime.now().difference(_last) < TapPill.debounce;

  void _dragStart(DragStartDetails _) {
    if (_blocked) return;
    setState(() => _drag = _right ? 1 : 0);
  }

  void _dragUpdate(DragUpdateDetails d) {
    final v = _drag;
    if (v == null) return;
    setState(() => _drag = (v + d.delta.dx / _travel).clamp(0.0, 1.0));
  }

  void _dragEnd(DragEndDetails _) {
    final v = _drag;
    if (v == null) return;
    final fire = _right ? v <= 1 - TapPill.dragFire : v >= TapPill.dragFire;
    setState(() => _drag = null); // snap back (or animate on to the new side)
    if (fire) _toggle(drag: true);
  }

  void _toggle({bool drag = false}) {
    if (_blocked) return;
    _sent = true;
    _last = DateTime.now();
    drag ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact();
    c.toggle().whenComplete(() {
      _sent = false;
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final st = c.status, on = c.connected;
    final wait = c.busy || _sent;
    final right = on || st == 'connecting';
    final (String title, String hint) = switch (st) {
      'connected' => ('Подключено', 'нажмите, чтобы отключить'),
      'connecting' => ('Подключение…', 'нажмите — отмена'),
      'disconnecting' => ('Отключение…', ''),
      _ => ('Отключено', 'нажмите, чтобы подключить'),
    };
    final label = hint.isEmpty ? title : '$title · $hint';
    return LayoutBuilder(
      builder: (context, box) {
        _travel = (box.maxWidth - 2 * _pad - 2 - _knob).clamp(1.0, 4000.0);
        return _build(
          context,
          p,
          on,
          wait,
          right,
          title,
          box.maxWidth < 230 ? '' : hint,
          label,
          box.maxWidth < 230,
        );
      },
    );
  }

  Widget _build(
    BuildContext context,
    Pal p,
    bool on,
    bool wait,
    bool right,
    String title,
    String hint,
    String label,
    bool narrow,
  ) {
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _toggle();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        toggled: on,
        label: label,
        onTap: _toggle,
        child: GestureDetector(
          key: TourKeys.power,
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          onHorizontalDragStart: _dragStart,
          onHorizontalDragUpdate: _dragUpdate,
          onHorizontalDragEnd: _dragEnd,
          onHorizontalDragCancel: () {
            if (_drag != null) setState(() => _drag = null);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: 52,
            padding: const EdgeInsets.all(_pad),
            decoration: BoxDecoration(
              color: on
                  ? p.grn.withValues(alpha: .22)
                  : wait
                  ? p.amb.withValues(alpha: .18)
                  : Colors.black.withValues(alpha: .25),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: on
                    ? p.grn.withValues(alpha: .55)
                    : Colors.white.withValues(alpha: .18),
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  // narrow (bottom bar next to «Добавить из буфера»): keep clear of the knob only
                  padding: narrow
                      ? EdgeInsets.only(
                          left: right ? 4 : 46,
                          right: right ? 46 : 4,
                        )
                      : const EdgeInsets.symmetric(horizontal: 46),
                  child: Opacity(
                    // while dragging, the label fades as the knob leaves its side
                    opacity: _drag == null
                        ? 1
                        : (1 - ((_drag! - (right ? 1 : 0)).abs() * 1.6)).clamp(
                            0.0,
                            1.0,
                          ),
                    child: Center(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (hint.isNotEmpty)
                              TextSpan(
                                text: '\n$hint',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.25,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: .7),
                                ),
                              ),
                          ],
                        ),
                        key: const Key('pill-label'),
                        textAlign: TextAlign.center,
                        textScaler: MediaQuery.textScalerOf(
                          context,
                        ).clamp(maxScaleFactor: 1.15),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .92),
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ),
                ),
                AnimatedAlign(
                  key: const Key('pill-knob'),
                  duration: _drag != null
                      ? Duration.zero
                      : const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment(
                    _drag != null ? _drag! * 2 - 1 : (right ? 1 : -1),
                    0,
                  ),
                  child: Container(
                    width: _knob,
                    height: _knob,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: (wait ? p.amb : (on ? p.grn : p.acc))
                              .withValues(alpha: .6),
                          blurRadius: 14,
                        ),
                      ],
                    ),
                    child: wait
                        ? Padding(
                            padding: const EdgeInsets.all(11),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: p.amb,
                            ),
                          )
                        : Icon(
                            Icons.power_settings_new_rounded,
                            color: on ? p.grn : p.acc,
                            size: 24,
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

/// 2.1.7: the bottom «＋» (was the first top-bar button). Not on TV, not in the text panel.
bool showAddFab(NoxController c) =>
    !c.isTv && c.state != null && c.pref('panel', '') != 'text';

class AddFab extends StatelessWidget {
  final NoxController c;
  final Pal p;
  const AddFab({super.key, required this.c, required this.p});
  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Добавить подписку',
    child: Semantics(
      button: true,
      label: 'Добавить подписку',
      child: Material(
        key: TourKeys.add,
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: accentGradient(p),
            border: Border.all(color: Colors.white.withValues(alpha: .22)),
            boxShadow: [
              BoxShadow(
                color: p.acc.withValues(alpha: .45),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => addSheet(context, c, p),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
          ),
        ),
      ),
    ),
  );
}

/// Shared clipboard import (empty-state button): same engine call as «Добавить» in addSheet.
Future<void> importFromClipboard(BuildContext context, NoxController c) async {
  final d = await Clipboard.getData('text/plain');
  final text = (d?.text ?? '').trim();
  if (!context.mounted) return;
  if (text.isEmpty) {
    toast(
      context,
      'Буфер обмена пуст — скопируйте ссылку на подписку или сервер',
    );
    return;
  }
  final r = await c.call('Import', [text]);
  await c.refresh();
  if (!context.mounted) return;
  if (r is Map && r['ok'] == true) {
    final errs = (r['errors'] as List?)?.length ?? 0;
    toast(context, '${r['msg']}${errs > 0 ? ' · ошибок: $errs' : ''}');
  } else {
    final msg = r is Map && '${r['msg'] ?? ''}'.isNotEmpty
        ? '${r['msg']}'
        : (c.fatal ?? 'Не удалось добавить: в буфере нет ссылки');
    toast(context, msg);
  }
}

/// 2.1.8: the connect pill lives in the bottom bar whenever the bar is shown and the
/// «Таймер» card is used (the ring/compact/classic cards keep their own power knob).
bool pillAtBottom(NoxController c) =>
    showAddFab(c) && !const {'ring', 'compact', 'classic'}.contains(heroStyle);

class BottomBar extends StatelessWidget {
  final NoxController c;
  final Pal p;
  const BottomBar({super.key, required this.c, required this.p});
  @override
  Widget build(BuildContext context) {
    final none = c.subs.isEmpty && c.servers.isEmpty;
    final pill = pillAtBottom(c);
    return Padding(
      key: const Key('bottom-bar'),
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Row(
        children: [
          AddFab(c: c, p: p),
          if (none) ...[
            const SizedBox(width: 10),
            pill
                ? ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 128),
                    child: ClipboardAddButton(c: c, p: p, compact: true),
                  )
                : Expanded(
                    child: ClipboardAddButton(c: c, p: p),
                  ),
          ],
          if (pill) ...[
            const SizedBox(width: 10),
            Expanded(
              child: TapPill(c: c, p: p),
            ),
          ],
        ],
      ),
    );
  }
}

class ClipboardAddButton extends StatefulWidget {
  final NoxController c;
  final Pal p;
  final bool compact; // bottom bar next to the pill: 52 dp tall, two-line label
  const ClipboardAddButton({
    super.key,
    required this.c,
    required this.p,
    this.compact = false,
  });
  @override
  State<ClipboardAddButton> createState() => _ClipboardAddButtonState();
}

class _ClipboardAddButtonState extends State<ClipboardAddButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    return Material(
      key: const Key('clip-add'),
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: accentGradient(p),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: p.acc.withValues(alpha: .35), blurRadius: 16),
          ],
        ),
        child: InkWell(
          onTap: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    await importFromClipboard(context, widget.c);
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Padding(
            padding: widget.compact
                ? const EdgeInsets.symmetric(horizontal: 10)
                : const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
            child: SizedBox(
              height: widget.compact ? 52 : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.content_paste_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                  SizedBox(width: widget.compact ? 7 : 10),
                  Flexible(
                    child: Text(
                      busy
                          ? 'Добавляю…'
                          : widget.compact
                          ? 'Добавить\nиз буфера'
                          : 'Добавить из буфера',
                      maxLines: widget.compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: widget.compact
                          ? MediaQuery.textScalerOf(
                              context,
                            ).clamp(maxScaleFactor: 1.15)
                          : null,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: widget.compact ? 13 : 16,
                        height: widget.compact ? 1.15 : null,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Variant 1: rotating sweep-gradient glow ring around the power knob.
class _GlowRing extends StatefulWidget {
  final Pal p;
  final bool on, wait, spin;
  final Widget child;
  const _GlowRing({
    required this.p,
    required this.on,
    required this.wait,
    required this.spin,
    required this.child,
  });
  @override
  State<_GlowRing> createState() => _GlowRingState();
}

class _GlowRingState extends State<_GlowRing>
    with SingleTickerProviderStateMixin {
  late final _a = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _GlowRing old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.spin && !_a.isAnimating) {
      _a.repeat();
    } else if (!widget.spin && _a.isAnimating) {
      _a.stop();
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final c1 = widget.wait && !widget.on ? p.amb : p.acc;
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RotationTransition(
            turns: _a,
            child: Container(
              width: 146,
              height: 146,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    c1.withValues(alpha: 0),
                    c1.withValues(alpha: widget.on ? .9 : .35),
                    p.acc2.withValues(alpha: widget.on ? 1 : .45),
                    c1.withValues(alpha: 0),
                  ],
                  stops: const [0, .45, .7, 1],
                ),
              ),
            ),
          ),
          Container(
            width: 136,
            height: 136,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.alphaBlend(p.acc.withValues(alpha: .10), p.card),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}
