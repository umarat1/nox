part of 'home.dart';

// 2.4.0 Windows «design A» (Mica dark): a left navigation pane (search, Главная /
// Серверы / Подписки / Блокировка рекламы, the subscriptions, the update banner,
// Настройки) and content pages built from the phone shell's widgets: the timer card with
// the traffic graph, the current server, the subscription card with a ping check,
// quick settings (МТС прокси, Анти БПЛА) and the ad-block card.

/// Tests / screenshots: use the Windows shell on any host.
bool winShellForce = false;

/// GlassCard / glassCard draw Fluent cards (set every frame by Home).
bool winCards = false;

/// The Windows shell is on (Windows desktop UI; «Прежний интерфейс» turns it off).
bool winShell(NoxController c) =>
    (winShellForce || (isWindows && desktopUi)) &&
    !c.isTv &&
    c.flag('winUi', true);

/// Selected page: 0 Главная, 1 Серверы, 2 Подписки, 3 Блокировка рекламы, 4 Настройки.
final winTab = ValueNotifier<int>(0);

/// Navigation pane expanded (☰ folds it to icons; narrow windows fold it by themselves).
final winNavOpen = ValueNotifier<bool>(true);

const _winNavW = 236.0, _winNavCompact = 56.0;

/// Dark Mica palette of the mockup; light themes keep their colours.
Pal winPal(Pal p) => p.light || p.amoled
    ? p
    : p.copyWith(
        bg: const Color(0xFF1F1F1F),
        hero: const Color(0xFF2B2B2B),
        card: const Color(0xFF2B2B2B),
        line: const Color(0xFF3A3A3A),
        chip: const Color(0xFF333333),
        acc: const Color(0xFFE5484D),
        acc2: const Color(0xFFFF6369),
        sel: const Color(0xFF3A2224),
      );

BoxDecoration winCardDeco(Pal p, {double r = 8, Color? border}) =>
    BoxDecoration(
      color: p.light
          ? Colors.white.withValues(alpha: .86)
          : (p.amoled
                ? const Color(0xFF0C0C0C)
                : const Color(0xFF2B2B2B).withValues(alpha: .94)),
      borderRadius: BorderRadius.circular(r),
      border: Border.all(
        color:
            border ??
            (p.light
                ? const Color(0x14000000)
                : Colors.white.withValues(alpha: .07)),
      ),
    );

/// Mica-like backdrop: Windows draws real Mica on the frame (runner, DWM backdrop type 2);
/// the Flutter surface is opaque, so the client area imitates it — the dark base with a
/// faint wallpaper tint.
class MicaBackdrop extends StatelessWidget {
  final Pal p;
  const MicaBackdrop({super.key, required this.p});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const Key('mica'),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: p.light
            ? const [Color(0xFFF3F3F3), Color(0xFFEDEBEE)]
            : const [Color(0xFF202020), Color(0xFF1C1B1F)],
      ),
    ),
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-.9, -1),
          radius: 1.4,
          colors: [
            p.acc.withValues(alpha: p.light ? .04 : .06),
            Colors.transparent,
          ],
        ),
      ),
      child: const SizedBox.expand(),
    ),
  );
}

/// Section caption («Быстрые настройки»).
Widget _winH(Pal p, String t) => Padding(
  padding: const EdgeInsets.fromLTRB(2, 0, 0, 8),
  child: Text(
    t,
    style: TextStyle(color: p.txt, fontSize: 14, fontWeight: FontWeight.w700),
  ),
);

/// Fluent toggle switch.
Widget winSwitch(Pal p, bool on, {Key? key}) => AnimatedContainer(
  key: key,
  duration: const Duration(milliseconds: 140),
  width: 40,
  height: 20,
  decoration: BoxDecoration(
    color: on ? p.acc : Colors.transparent,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(
      color: on ? p.acc : p.sub.withValues(alpha: .8),
      width: 1,
    ),
  ),
  child: AnimatedAlign(
    duration: const Duration(milliseconds: 140),
    alignment: on ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: on ? 12 : 10,
      height: on ? 12 : 10,
      decoration: BoxDecoration(
        color: on ? Colors.white : p.sub,
        shape: BoxShape.circle,
      ),
    ),
  ),
);

/// Row of a settings card: icon / badge, title, caption, switch.
class _WinRow extends StatelessWidget {
  final Pal p;
  final Widget lead;
  final String title, desc;
  final bool on;
  final VoidCallback onTap;
  final String? count;
  const _WinRow({
    super.key,
    required this.p,
    required this.lead,
    required this.title,
    required this.desc,
    required this.on,
    required this.onTap,
    this.count,
  });
  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            SizedBox(width: 26, child: Center(child: lead)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.txt,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (desc.isNotEmpty)
                    Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.sub, fontSize: 11.5),
                    ),
                ],
              ),
            ),
            if (count != null) ...[
              Text(
                count!,
                style: TextStyle(
                  color: p.sub,
                  fontSize: 12,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
            ],
            winSwitch(p, on),
          ],
        ),
      ),
    ),
  );
}

/// Ad vendors of the mockup: (setting, title, caption, badge text, badge colour, counter key).
const _adVendors = [
  (
    'adsYandex',
    'Яндекс',
    'Директ, РСЯ, ADFOX, Метрика',
    'Я',
    Color(0xFFFC3F1D),
    'yandex',
  ),
  (
    'adsRutube',
    'Rutube',
    'Реклама в плеере и баннеры',
    'R',
    Color(0xFF100943),
    'rutube',
  ),
  (
    'adsMailVk',
    'Mail.ru / VK',
    'Top@Mail.ru, баннеры myTarget, VK Реклама',
    '@',
    Color(0xFF0077FF),
    'mailvk',
  ),
  (
    'adsGoogle',
    'Google',
    'AdSense, DoubleClick, AdMob',
    'G',
    Color(0xFF4285F4),
    'google',
  ),
];

Widget _badge(String t, Color col) => Container(
  width: 22,
  height: 22,
  alignment: Alignment.center,
  decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(5)),
  child: Text(
    t,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w800,
    ),
  ),
);

Map<String, dynamic> _ads(NoxController c) {
  final a = c.s['ads'];
  return a is Map ? a.cast<String, dynamic>() : const {};
}

int _adN(Map a, String k) => ((a[k] ?? 0) as num).toInt();

int _adSrc(Map a, String src) {
  final b = a['bySrc'];
  return b is Map ? ((b[src] ?? 0) as num).toInt() : 0;
}

String _num(int n) {
  final s = '$n';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('\u202F');
    b.write(s[i]);
  }
  return b.toString();
}

/// Save routing settings and reconnect so the running config picks them up.
Future<void> winSaveLive(NoxController c, Map<String, dynamic> m) async {
  await c.saveSettings(m);
  if (c.connected) {
    await c.call('Disconnect');
    await c.call('Connect');
  }
}

/// «example.com», «*.example.com», «https://example.com/x» → «example.com»; null if bad.
String? normAllowDomain(String raw) {
  var d = raw.trim().toLowerCase();
  d = d.replaceFirst(RegExp(r'^[a-z]+://'), '');
  d = d.split(RegExp(r'[/?#:]')).first;
  d = d.replaceFirst(RegExp(r'^\*?\.'), '');
  if (d.endsWith('.')) d = d.substring(0, d.length - 1);
  final ok = RegExp(
    r'^([a-z0-9\u0430-\u044f\u0451]([a-z0-9\u0430-\u044f\u0451-]*[a-z0-9\u0430-\u044f\u0451])?\.)+[a-z\u0430-\u044f\u0451]{2,}$',
  ).hasMatch(d);
  return ok ? d : null;
}

extension _WinShell on _BodyState {
  Widget winBody(BuildContext context, List<J> list, List<Widget> banners) =>
      LayoutBuilder(
        builder: (context, box) => ValueListenableBuilder<bool>(
          valueListenable: winNavOpen,
          builder: (context, open, _) => ValueListenableBuilder<int>(
            valueListenable: winTab,
            builder: (context, tab, _) {
              final wide = open && box.maxWidth >= 760;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: wide ? _winNavW : _winNavCompact,
                    child: _winNav(context, tab, wide),
                  ),
                  Expanded(
                    child: Container(
                      key: const Key('win-content'),
                      decoration: BoxDecoration(
                        color: p.light
                            ? Colors.white.withValues(alpha: .55)
                            : Colors.white.withValues(alpha: .028),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                        ),
                        border: Border(
                          left: BorderSide(
                            color: Colors.white.withValues(alpha: .05),
                          ),
                          top: BorderSide(
                            color: Colors.white.withValues(alpha: .05),
                          ),
                        ),
                      ),
                      child: ValueListenableBuilder<String>(
                        valueListenable: srvQuery,
                        builder: (context, q, _) => switch (tab) {
                          1 => _winServers(context, list, q),
                          2 => _winSubs(context),
                          3 => _winAdsPage(context),
                          4 => _winSettings(context),
                          _ => _winHome(context, list, banners),
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );

  // ------------------------------------------------------------------ navigation pane

  Widget _winNav(BuildContext context, int tab, bool wide) {
    Widget nav(int i, IconData ic, String t, {Key? key}) {
      final on = tab == i;
      final body = Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: key ?? Key('win-nav-$i'),
          borderRadius: BorderRadius.circular(6),
          onTap: () => winTab.value = i,
          child: Container(
            height: 36,
            margin: const EdgeInsets.symmetric(vertical: 1.5),
            decoration: BoxDecoration(
              color: on
                  ? (p.light
                        ? Colors.black.withValues(alpha: .06)
                        : Colors.white.withValues(alpha: .07))
                  : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 3,
                  height: on ? 16 : 0,
                  decoration: BoxDecoration(
                    color: p.acc,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(
                  width: wide ? 34 : 37,
                  child: Icon(ic, size: 18, color: on ? p.txt : p.sub),
                ),
                if (wide)
                  Expanded(
                    child: Text(
                      t,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.txt,
                        fontSize: 13.5,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      return wide ? body : Tooltip(message: t, child: body);
    }

    final subs = c.subs;
    final sIdx = (int.tryParse(c.pref('subIdx', '0')) ?? 0)
        .clamp(0, math.max(0, subs.length - 1))
        .toInt();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              key: const Key('win-hamburger'),
              tooltip: wide ? 'Свернуть меню' : 'Развернуть меню',
              onPressed: () => winNavOpen.value = !winNavOpen.value,
              icon: Icon(Icons.menu_rounded, size: 18, color: p.txt),
            ),
          ),
          if (wide) ...[
            _winSearch(),
            const SizedBox(height: 10),
          ] else
            nav(
              1,
              Icons.search_rounded,
              'Поиск сервера',
              key: const Key('win-nav-search'),
            ),
          nav(0, Icons.home_outlined, 'Главная'),
          nav(1, Icons.language_rounded, 'Серверы'),
          nav(2, Icons.credit_card_rounded, 'Подписки'),
          nav(3, Icons.block_rounded, 'Блокировка рекламы'),
          if (wide && subs.isNotEmpty) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 10, bottom: 6),
              child: Text(
                'подписки',
                style: TextStyle(
                  color: p.sub,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final (i, b) in subs.indexed)
                    _winSubRow(b, i, i == sIdx && subs.length > 1),
                ],
              ),
            ),
          ],
          const Spacer(),
          if (updPill(c) != null) _winUpdate(context, wide),
          const SizedBox(height: 6),
          KeyedSubtree(
            key: TourKeys.settings,
            child: nav(4, Icons.settings_outlined, 'Настройки'),
          ),
        ],
      ),
    );
  }

  Widget _winSearch() => Container(
    height: 34,
    decoration: BoxDecoration(
      color: p.light
          ? Colors.white.withValues(alpha: .8)
          : Colors.white.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(5),
      border: Border(bottom: BorderSide(color: p.sub.withValues(alpha: .5))),
    ),
    padding: const EdgeInsets.only(left: 10, right: 6),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('win-search'),
            controller: _srvQueryCtl,
            onChanged: (v) {
              srvQuery.value = v;
              if (v.isNotEmpty) winTab.value = 1;
            },
            onSubmitted: (_) => winTab.value = 1,
            style: TextStyle(color: p.txt, fontSize: 13),
            cursorColor: p.acc,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: 'Поиск сервера',
              hintStyle: TextStyle(color: p.sub, fontSize: 13),
              contentPadding: const EdgeInsets.symmetric(vertical: 9),
            ),
          ),
        ),
        ValueListenableBuilder<String>(
          valueListenable: srvQuery,
          builder: (_, q, _) => q.isEmpty
              ? Icon(Icons.search_rounded, size: 16, color: p.sub)
              : InkWell(
                  onTap: () {
                    _srvQueryCtl.clear();
                    srvQuery.value = '';
                  },
                  child: Icon(Icons.close_rounded, size: 16, color: p.sub),
                ),
        ),
      ],
    ),
  );

  Widget _winSubRow(J b, int i, bool on) {
    final used = ((b['upload'] ?? 0) as num) + ((b['download'] ?? 0) as num);
    final total = (b['total'] ?? 0) as num;
    final expire = (b['expire'] ?? 0) as int;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final d = _SubData(
      n: _subCount(c, b),
      used: used,
      total: total,
      left: expire > 0 ? (expire - now) / 86400 : null,
      dt: expire > 0
          ? DateTime.fromMillisecondsSinceEpoch(expire * 1000)
          : null,
    );
    final dead =
        (!d.forever && d.left! <= 0) || (!d.unlimited && d.trafficLeft <= 0);
    final line = [
      if (!d.unlimited) fmtBytes(d.trafficLeft),
      if (!d.forever) d.expShort,
      if (d.unlimited && d.forever) 'без лимита',
      if (d.unlimited && !d.forever) 'без лимита трафика',
    ].join(' · ');
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: Key('win-sub-${b['id']}'),
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          c.setPrefLive('subIdx', '$i');
          winTab.value = 0;
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
          decoration: BoxDecoration(
            color: on ? Colors.white.withValues(alpha: .04) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: dead
                        ? p.red
                        : (d.days <= 3 && !d.forever ? p.amb : p.grn),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _subName(b, i),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.txt, fontSize: 12.5),
                    ),
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.sub, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _winUpdate(BuildContext context, bool wide) {
    final st = updPill(c)!;
    final msix = c.s['packaged'] == true;
    final title = st.version.isEmpty
        ? 'Доступно обновление'
        : 'Доступно обновление ${st.version}';
    final sub = msix
        ? 'App Installer · установится само'
        : switch (st.kind) {
            'progress' => st.label,
            'ready' => 'Скачано — установить',
            _ => 'Нажмите, чтобы установить',
          };
    final body = Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const Key('win-update'),
        borderRadius: BorderRadius.circular(6),
        onTap: () => startUpdateFlow(context, c, p),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: wide ? 10 : 0, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: p.light ? .6 : .05),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: .06)),
          ),
          child: Row(
            mainAxisAlignment: wide
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Icon(
                st.kind == 'progress'
                    ? Icons.downloading_rounded
                    : Icons.download_rounded,
                size: 17,
                color: p.acc,
              ),
              if (wide) ...[
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.txt,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.sub, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return wide ? body : Tooltip(message: '$title — $sub', child: body);
  }

  // ------------------------------------------------------------------ pages

  Widget _winPage(
    String title,
    List<Widget> children, {
    List<Widget>? actions,
  }) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
    children: [
      _winTitle(title, actions: actions),
      ...children,
    ],
  );

  Widget _winTitle(String t, {List<Widget>? actions}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        Expanded(
          child: Text(
            t,
            key: Key('win-title-$t'),
            style: TextStyle(
              color: p.txt,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ...?actions,
      ],
    ),
  );

  Widget _winHome(BuildContext context, List<J> list, List<Widget> banners) {
    final shown = phoneFilter(c, list);
    final left = <Widget>[
      for (final b in banners)
        if (b is! _UpdateBanner) b,
      if (banners.any((b) => b is! _UpdateBanner)) const SizedBox(height: 10),
      _winConnect(context),
      const SizedBox(height: 10),
      _winCurrent(context),
      if (c.subs.isNotEmpty) ...[
        const SizedBox(height: 10),
        _SubCard(c: c, p: p, footer: _winPingBar(context)),
      ] else ...[
        const SizedBox(height: 14),
        ClipboardAddButton(c: c, p: p),
      ],
    ];
    final right = <Widget>[
      _winH(p, 'Быстрые настройки'),
      _winQuick(context),
      const SizedBox(height: 12),
      _winAdsCard(context),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final two = box.maxWidth >= 820;
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
          children: [
            _winTitle('Главная'),
            if (two)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: left,
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: (box.maxWidth * .36).clamp(280.0, 380.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: right,
                    ),
                  ),
                ],
              )
            else ...[
              ...left,
              const SizedBox(height: 16),
              ...right,
            ],
            if (shown.isEmpty && c.servers.isNotEmpty && _antiOn(c))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _emptyText(c),
                  style: TextStyle(color: p.sub, fontSize: 12.5),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Timer card: status, mode, power button, connection time, speeds, traffic graph.
  Widget _winConnect(BuildContext context) {
    final t = c.traffic;
    final down = (t?['Down'] ?? 0) as num, up = (t?['Up'] ?? 0) as num;
    final tun = c.settings['mode'] != 'proxy';
    return Container(
      key: const Key('win-connect'),
      decoration: winCardDeco(p),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              _StatusPill(c: c, p: p),
              const Spacer(),
              Tooltip(
                message: 'Сменить режим (переподключит)',
                child: InkWell(
                  key: const Key('win-mode'),
                  borderRadius: BorderRadius.circular(99),
                  onTap: () async {
                    await winSaveLive(c, {'mode': tun ? 'proxy' : 'tun'});
                    if (context.mounted) {
                      toast(
                        context,
                        tun
                            ? 'Режим: прокси-сервер'
                            : 'Режим: VPN (TUN) — весь трафик',
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .12),
                      ),
                      color: Colors.white.withValues(alpha: .04),
                    ),
                    child: Text(
                      tun ? 'Режим: TUN' : 'Режим: Прокси',
                      style: TextStyle(color: p.sub, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _miniPower(c, p),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _timer(c),
                        key: const Key('win-timer'),
                        style: TextStyle(
                          color: p.txt,
                          fontSize: 40,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .5,
                          fontFeatures: const [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Text(
                      'Время подключения',
                      style: TextStyle(color: p.sub, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _speed(p, Icons.south_rounded, down, size: 13.5),
                  const SizedBox(height: 10),
                  _speed(p, Icons.north_rounded, up, size: 13.5),
                ],
              ),
              const SizedBox(width: 8),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            key: const Key('win-graph'),
            height: 110,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LiveGraph(
                series: c.speed,
                p: p,
                active: c.connected && c.animSmooth,
                calm: true,
                span: 90,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _winCurrent(BuildContext context) {
    final cur = c.current;
    final sub = cur == null
        ? 'Выберите сервер в списке'
        : [
            'Текущий сервер',
            NoxController.proto(cur),
            if (NoxController.isBal(cur)) 'автовыбор',
          ].where((x) => x.isNotEmpty).toSet().join(' · ');
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const Key('win-current'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => winTab.value = 1,
        child: Container(
          decoration: winCardDeco(p),
          padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
          child: Row(
            children: [
              if (cur != null)
                _flag(p, cur, size: 30)
              else
                Icon(Icons.public_rounded, size: 30, color: p.sub),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cur == null
                          ? 'Сервер не выбран'
                          : _noFlag(_srvTitle(cur)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.txt,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.sub, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (cur != null) _PingDot(c: c, p: p, s: cur),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: p.sub, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// Ping check under the subscription: progress while pinging, else the button.
  Widget _winPingBar(BuildContext context) {
    final sub = _subSel(c) ?? (c.subs.isNotEmpty ? c.subs.first : null);
    final ids = [
      for (final s in phoneFilter(c, c.visible()))
        if (sub == null || s['subId'] == sub['id']) s['id'] as String,
    ];
    final pinging = c.s['pinging'] == true;
    final done = ((c.s['pingDone'] ?? 0) as num).toInt();
    final all = ((c.s['pingAll'] ?? 0) as num).toInt();
    final frac = all > 0 ? (done / all).clamp(0.0, 1.0) : 0.0;
    final pings = [
      for (final s in c.servers)
        if (ids.contains(s['id']) && ((s['ping'] ?? 0) as int) > 0)
          (s['ping'] as int),
    ];
    final best = pings.isEmpty ? null : pings.reduce(math.min);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        key: TourKeys.ping,
        color: p.acc.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          key: const Key('win-ping'),
          borderRadius: BorderRadius.circular(6),
          onTap: pinging || ids.isEmpty ? null : () => c.ping(ids),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(Icons.bolt_rounded, size: 16, color: p.acc),
                const SizedBox(width: 8),
                Text(
                  pinging
                      ? 'Пинг $done/$all…'
                      : 'Проверить пинг · ${ids.length} ${plural(ids.length, 'сервер', 'сервера', 'серверов')}',
                  style: TextStyle(color: p.txt, fontSize: 12.5),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: pinging
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: frac,
                            minHeight: 3,
                            color: p.acc,
                            backgroundColor: Colors.white.withValues(alpha: .1),
                          ),
                        )
                      : const SizedBox(),
                ),
                const SizedBox(width: 12),
                Text(
                  pinging
                      ? '${(frac * 100).round()}%'
                      : (best == null ? '' : 'лучший $best мс'),
                  style: TextStyle(color: p.sub, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _winQuick(BuildContext context) => Container(
    key: const Key('win-quick'),
    decoration: winCardDeco(p),
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
    child: Column(
      children: [
        _WinRow(
          key: const Key('win-mts'),
          p: p,
          lead: Icon(Icons.sim_card_outlined, size: 18, color: p.sub),
          title: 'МТС прокси',
          desc: 'через 192.168.192.192',
          on: c.mtsOn,
          onTap: () => toggleMts(context, c),
        ),
        _WinRow(
          key: const Key('win-anti'),
          p: p,
          lead: Icon(Icons.shield_outlined, size: 18, color: p.sub),
          title: 'Анти БПЛА',
          desc: 'обход при ограничениях связи',
          on: _antiOn(c),
          onTap: () => toggleAntiblock(context, c),
        ),
      ],
    ),
  );

  Widget _winAdsCard(BuildContext context) {
    final s = c.settings, on = s['blockAds'] == true, a = _ads(c);
    final n = _adN(a, 'session');
    return Container(
      key: const Key('win-ads'),
      decoration: winCardDeco(p),
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
      child: Column(
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const Key('win-ads-master'),
              borderRadius: BorderRadius.circular(6),
              onTap: () => winSaveLive(c, {'blockAds': !on}),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: p.acc.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.block_rounded, size: 17, color: p.acc),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Блокировка рекламы',
                            style: TextStyle(
                              color: p.txt,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            on
                                ? 'Заблокировано за сеанс: ${_num(n)} ${plural(n, 'запрос', 'запроса', 'запросов')}'
                                : 'Выключена',
                            key: const Key('win-ads-count'),
                            style: TextStyle(color: p.sub, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    winSwitch(p, on),
                  ],
                ),
              ),
            ),
          ),
          if (on) ...[
            Divider(height: 8, color: Colors.white.withValues(alpha: .06)),
            for (final v in _adVendors)
              _WinRow(
                key: Key('win-ad-${v.$1}'),
                p: p,
                lead: _badge(v.$4, v.$5),
                title: v.$2,
                desc: v.$3,
                on: s[v.$1] == true,
                onTap: () => winSaveLive(c, {v.$1: !(s[v.$1] == true)}),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('win-ads-more'),
                onPressed: () => winTab.value = 3,
                child: Text(
                  'Белый список и счётчик ›',
                  style: TextStyle(color: p.acc2, fontSize: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _winServers(BuildContext context, List<J> all, String q) {
    final subs = c.subs;
    final sIdx = (int.tryParse(c.pref('subIdx', '0')) ?? 0)
        .clamp(0, math.max(0, subs.length - 1))
        .toInt();
    var list = phoneFilter(c, all);
    final qq = q.trim().toLowerCase();
    if (qq.isNotEmpty) {
      list = [
        for (final s in list)
          if ('${s['name'] ?? ''} ${regionName[region('${s['name'] ?? ''}') ?? ''] ?? ''} ${NoxController.proto(s)}'
              .toLowerCase()
              .contains(qq))
            s,
      ];
    }
    final ids = [for (final s in list) s['id'] as String];
    Widget act(IconData i, String tip, VoidCallback f, {Key? key}) => Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: tip,
        child: OutlinedButton.icon(
          key: key,
          onPressed: f,
          icon: Icon(i, size: 16, color: p.txt),
          label: Text(tip, style: TextStyle(color: p.txt, fontSize: 12.5)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.white.withValues(alpha: .12)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          ),
        ),
      ),
    );
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
          sliver: SliverList.list(
            children: [
              _winTitle(
                'Серверы',
                actions: [
                  act(
                    Icons.bolt_rounded,
                    'Пинг',
                    () => c.ping(ids),
                    key: const Key('win-srv-ping'),
                  ),
                  act(Icons.refresh_rounded, 'Обновить', () async {
                    dynamic r;
                    for (final b in c.subs) {
                      r = await c.call('RefreshSub', [b['id']]);
                    }
                    if (context.mounted) await finishRefresh(context, c, r);
                  }),
                  act(
                    Icons.tune_rounded,
                    'Сортировка',
                    () => listSheet(
                      context,
                      c,
                      p,
                      caption: listCaption(c, list.length),
                    ),
                  ),
                  act(
                    Icons.add_rounded,
                    'Добавить',
                    () => addSheet(context, c, p),
                    key: TourKeys.add,
                  ),
                ],
              ),
              if (qq.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Поиск «${q.trim()}»: ${list.length}',
                    style: TextStyle(color: p.sub, fontSize: 12.5),
                  ),
                ),
              if (subs.length > 1) ...[
                _Seg(
                  p: p,
                  items: [
                    for (final (i, s) in subs.indexed)
                      (_subName(s, i), '${_subCount(c, s)}'),
                  ],
                  on: sIdx,
                  onTap: (i) => c.setPrefLive('subIdx', '$i'),
                ),
                const SizedBox(height: 6),
              ],
              if (list.isNotEmpty) _CountryChips(c: c, p: p, list: list),
              const SizedBox(height: 4),
            ],
          ),
        ),
        ..._listOrEmpty(context, list, 28).map(
          (s) => SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: s,
          ),
        ),
      ],
    );
  }

  Widget _winSubs(BuildContext context) => _winPage(
    'Подписки',
    [
      if (c.subs.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Подписок пока нет. Скопируйте ссылку на подписку и нажмите «Добавить из буфера» или «Добавить».',
            style: TextStyle(color: p.sub),
          ),
        ),
      for (final b in c.subs) _SubCard(c: c, p: p, fixed: b),
      const SizedBox(height: 14),
      ClipboardAddButton(c: c, p: p),
    ],
    actions: [
      FilledButton.icon(
        key: const Key('win-subs-add'),
        onPressed: () => addSheet(context, c, p),
        icon: const Icon(Icons.add_rounded, size: 16),
        label: const Text('Добавить'),
        style: FilledButton.styleFrom(
          backgroundColor: p.acc,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
      ),
    ],
  );

  Widget _winAdsPage(BuildContext context) {
    final s = c.settings, on = s['blockAds'] == true, a = _ads(c);
    final allow = [for (final x in (s['adsAllow'] as List?) ?? const []) '$x'];
    Widget sw2(String k, String t, String d, {Widget? lead, String? cnt}) =>
        _WinRow(
          key: Key('win-adp-$k'),
          p: p,
          lead: lead ?? Icon(Icons.block_rounded, size: 17, color: p.sub),
          title: t,
          desc: d,
          on: s[k] == true,
          count: cnt,
          onTap: () => winSaveLive(c, {k: !(s[k] == true)}),
        );
    return _winPage('Блокировка рекламы', [
      Container(
        decoration: winCardDeco(p),
        padding: const EdgeInsets.all(4),
        child: Column(
          children: [
            sw2(
              'blockAds',
              'Блокировать рекламу и счётчики',
              'Рекламные домены отвечают «нет такого адреса» (DNS) и отклоняются '
                  'маршрутизатором — раньше, чем «Россия напрямую». Работает в режимах TUN и прокси',
              lead: Icon(Icons.shield_rounded, size: 18, color: p.acc),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Container(
        key: const Key('win-ads-stats'),
        decoration: winCardDeco(p),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _num(_adN(a, 'session')),
                    style: TextStyle(
                      color: p.txt,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'заблокировано за сеанс · всего ${_num(_adN(a, 'total'))}',
                    style: TextStyle(color: p.sub, fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(
              key: const Key('win-ads-reset'),
              onPressed: () async {
                await c.call('ResetAdStats');
                await c.refresh();
              },
              child: Text('Сбросить', style: TextStyle(color: p.acc2)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _winH(p, 'Источники'),
      Opacity(
        opacity: on ? 1 : .45,
        child: IgnorePointer(
          ignoring: !on,
          child: Container(
            decoration: winCardDeco(p),
            padding: const EdgeInsets.all(4),
            child: Column(
              children: [
                for (final v in _adVendors)
                  sw2(
                    v.$1,
                    v.$2,
                    v.$3,
                    lead: _badge(v.$4, v.$5),
                    cnt: _num(_adSrc(a, v.$6)),
                  ),
                sw2(
                  'adsOther',
                  'Прочие сети',
                  'Список category-ads-all (v2fly) без Google/Яндекс/VK',
                  cnt: _num(_adSrc(a, 'other')),
                ),
                sw2(
                  'adsAnalytics',
                  'Аналитика Google (опц.)',
                  'google-analytics, app-measurement, Tag Manager',
                  cnt: _num(_adSrc(a, 'analytics')),
                ),
                sw2(
                  'adsAppMetrica',
                  'AppMetrica (опц.)',
                  'Может мешать некоторым приложениям Яндекса и банков',
                  cnt: _num(_adSrc(a, 'appmetrica')),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      _winH(p, 'Белый список'),
      _AllowList(c: c, p: p, items: allow),
    ]);
  }

  Widget _winSettings(BuildContext context) {
    final upd = c.s['update'] is Map;
    return _winPage('Настройки', [
      _linksRow(context, p),
      const SizedBox(height: 12),
      Container(
        decoration: winCardDeco(p),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            brandLogo(size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ПРОКСИ+',
                    style: TextStyle(
                      color: p.txt,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Версия ${c.s['version'] ?? ''}${c.s['packaged'] == true ? ' · MSIX' : ''}',
                    style: TextStyle(color: p.sub, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      _sectionLabel(p, 'Быстрые'),
      item(
        p,
        'МТС прокси',
        desc: c.mtsOn
            ? 'Включён: только AnyTLS, NaiveProxy, mieru, VLESS и прокси'
            : 'Через 192.168.192.192 (интернет МТС, APN wap.mts.ru)',
        trailing: sw(p, c.mtsOn),
        onTap: () => toggleMts(context, c),
      ),
      item(
        p,
        'Новый интерфейс Windows',
        desc: 'Выключите, чтобы вернуть прежний вид (как в 2.3)',
        trailing: sw(p, true),
        onTap: () => c.setPrefLive('winUi', '0'),
      ),
      item(
        p,
        upd ? 'Доступно обновление' : 'Обновления и сообщения',
        desc: upd ? 'Нажмите, чтобы установить' : 'Почта от разработчика',
        color: upd ? p.acc : null,
        arrow: true,
        onTap: () => updateSheet(context, c, p),
      ),
      _sectionLabel(p, 'Все настройки'),
      Builder(
        builder: (ctx) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: settingsItems(context, c, p, ctx),
        ),
      ),
    ]);
  }
}

/// Ad-block allow-list: domains (and their subdomains) never blocked.
class _AllowList extends StatefulWidget {
  final NoxController c;
  final Pal p;
  final List<String> items;
  const _AllowList({required this.c, required this.p, required this.items});
  @override
  State<_AllowList> createState() => _AllowListState();
}

class _AllowListState extends State<_AllowList> {
  final _ctl = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _save(List<String> l) => winSaveLive(widget.c, {'adsAllow': l});

  Future<void> _add() async {
    final d = normAllowDomain(_ctl.text);
    if (d == null) {
      setState(() => _err = 'Введите домен, например mc.yandex.ru');
      return;
    }
    setState(() => _err = null);
    _ctl.clear();
    if (widget.items.contains(d)) return;
    await _save([...widget.items, d]);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    return Container(
      key: const Key('win-allow'),
      decoration: winCardDeco(p),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Эти домены и их поддомены не блокируются (если сайт или приложение '
            'сломалось из-за блокировки).',
            style: TextStyle(color: p.sub, fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (final d in widget.items)
            Row(
              key: Key('allow-$d'),
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 16,
                  color: p.grn,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(d, style: TextStyle(color: p.txt, fontSize: 13)),
                ),
                IconButton(
                  tooltip: 'Убрать',
                  onPressed: () => _save([
                    for (final x in widget.items)
                      if (x != d) x,
                  ]),
                  icon: Icon(Icons.close_rounded, size: 16, color: p.sub),
                ),
              ],
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('allow-input'),
                  controller: _ctl,
                  onSubmitted: (_) => _add(),
                  style: TextStyle(color: p.txt, fontSize: 13),
                  cursorColor: p.acc,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'домен, например mc.yandex.ru',
                    hintStyle: TextStyle(color: p.ter, fontSize: 13),
                    errorText: _err,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('allow-add'),
                onPressed: _add,
                style: FilledButton.styleFrom(
                  backgroundColor: p.acc,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                child: const Text('Добавить'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The card draws the flag itself: drop a leading flag emoji from the name.
String _noFlag(String s) => s.replaceFirst(
  RegExp(
    r'^(\u{1F3F4}[\u{E0060}-\u{E007F}]*|[\u{1F1E6}-\u{1F1FF}]{2})\s*',
    unicode: true,
  ),
  '',
);
